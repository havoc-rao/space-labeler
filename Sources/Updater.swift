import AppKit
import Combine
import CryptoKit
import Foundation

/// Semantic version parsed from a tag or bundle string like "v0.1.0".
struct AppVersion: Hashable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts "0.1.0", "v0.1.0" or "V0.1.0". Rejects anything with
    /// non-numeric or extra components so prerelease tags ("v0.2.0-beta.1")
    /// fail loudly — they should never land in the `latest` release anyway.
    init?(raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else {
            return nil
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// Where update metadata comes from. Update this single constant if the
/// repository moves.
enum UpdaterConfig {
    static let repo = "havoc-rao/space-labeler"
    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }
    /// Machine-readable metadata the release workflow commits to `main`.
    /// Fetched from raw.githubusercontent.com — which has no API rate limit —
    /// so regular check-ins never consume GitHub's anonymous API quota. The
    /// `/releases/latest` API above remains the fallback.
    static var latestMetadataURL: URL {
        URL(string: "https://raw.githubusercontent.com/\(repo)/main/latest.json")!
    }
}

/// Drives the "check for updates" state and the download-and-restart flow.
///
/// The app is ad-hoc signed and not notarized, so updates ship as zip
/// artifacts attached to GitHub Releases. The release workflow publishes a
/// small `latest.json` (version + direct download URL + SHA-256) to `main`;
/// the app reads that from raw.githubusercontent.com first — no signing keys,
/// no Sparkle infrastructure, no GitHub API rate limit — and falls back to
/// the public `releases/latest` API. The installed bundle is replaced in
/// place by a detached shell script that waits for this process to exit,
/// then relaunches the new version.
@MainActor
final class UpdaterState: ObservableObject {
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(AppVersion)
        case applying
        case failed(String)
    }

    @Published private(set) var state: UpdateState = .idle
    /// True while the release zip is downloading.
    @Published private(set) var isDownloading = false

    /// The running app's marketing version, e.g. "0.1.0".
    static var currentVersion: AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return AppVersion(raw: short) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    // Update metadata is cached in UserDefaults so the settings screen can
    // show "new version available" instantly, before any network round trip.
    private static let lastCheckKey = "updater.lastCheckDate"
    private static let latestVersionKey = "updater.latestVersion"
    private static let latestDownloadURLKey = "updater.latestDownloadURL"
    private static let latestSHA256Key = "updater.latestSHA256"

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.session = URLSession(configuration: .ephemeral)
    }

    /// The newest version we know about — from the live check, or from the
    /// last successful check persisted in UserDefaults.
    var latestVersion: AppVersion? {
        if case .updateAvailable(let version) = state { return version }
        return cachedLatestVersion
    }

    var isChecking: Bool { state == .checking }

    /// Called at launch. Checks at most once per day (silently), but shows a
    /// previously cached update immediately.
    func autoCheckIfDue() {
        if let cached = cachedLatestVersion, cached > Self.currentVersion {
            state = .updateAvailable(cached)
        } else if isDueForCheck() {
            Task { await checkForUpdates() }
        }
    }

    func checkForUpdates() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let info = try await Self.fetchUpdateInfo(session: session)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            defaults.set(info.version.description, forKey: Self.latestVersionKey)
            defaults.set(info.downloadURL.absoluteString, forKey: Self.latestDownloadURLKey)
            if let sha256 = info.sha256 {
                defaults.set(sha256, forKey: Self.latestSHA256Key)
            }
            state = info.version > Self.currentVersion ? .updateAvailable(info.version) : .upToDate
        } catch {
            // Prefer showing a cached update over surfacing a network error.
            if let cached = cachedLatestVersion, cached > Self.currentVersion {
                state = .updateAvailable(cached)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Downloads the latest zip, extracts it alongside the installed app,
    /// then swaps the bundle and relaunches — the app quits as part of this.
    func downloadAndInstallLatest() {
        guard let version = cachedLatestVersion, version > Self.currentVersion,
            let url = cachedDownloadURL
        else { return }
        isDownloading = true
        Task {
            do {
                let newApp = try await Self.downloadAndExtract(
                    url: url,
                    session: session,
                    expectedSHA256: cachedSHA256
                )
                state = .applying
                try Self.launchInstaller(newApp: newApp)
                NSApp.terminate(nil)
            } catch {
                isDownloading = false
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func isDueForCheck() -> Bool {
        guard let last = defaults.object(forKey: Self.lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= 24 * 60 * 60
    }

    private var cachedLatestVersion: AppVersion? {
        guard let s = defaults.string(forKey: Self.latestVersionKey) else { return nil }
        return AppVersion(raw: s)
    }

    private var cachedDownloadURL: URL? {
        guard let s = defaults.string(forKey: Self.latestDownloadURLKey) else { return nil }
        return URL(string: s)
    }

    private var cachedSHA256: String? {
        defaults.string(forKey: Self.latestSHA256Key)
    }
}

private enum UpdateError: LocalizedError {
    case httpStatus(Int)
    case noZipAsset
    case invalidArchive
    case checksumMismatch
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "HTTP \(code)"
        case .noZipAsset: return "Latest release has no zip asset"
        case .invalidArchive: return "Downloaded archive does not contain SpaceLabeler.app"
        case .checksumMismatch: return "Downloaded update failed SHA-256 verification"
        case .processFailed(let message): return message
        }
    }
}

/// Shape of the repo's `latest.json` — written to `main` by the release
/// workflow, so the app can learn about new versions without paying GitHub's
/// API rate limit. `sha256` is the zip's digest, verified before install.
private struct LatestMetadata: Decodable {
    let version: String
    let url: String
    let sha256: String?
}

/// Resolved "what to install" from either metadata source.
private struct UpdateInfo {
    let version: AppVersion
    let downloadURL: URL
    let sha256: String?
}

/// Shape of the `GET /repos/{owner}/{repo}/releases/latest` response we care
/// about; unknown fields are simply ignored by JSONDecoder.
private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    /// The .zip we distribute, or nil if the release has no zip asset.
    var zipAsset: Asset? {
        assets.first { $0.name.hasSuffix(".zip") }
    }
}

extension UpdaterState {
    /// Latest release metadata: prefers the repo's `latest.json` (no API rate
    /// limit), falling back to the GitHub `releases/latest` API — which is the
    /// only source until a release has been built with the publishing step.
    fileprivate static func fetchUpdateInfo(session: URLSession) async throws -> UpdateInfo {
        if let info = try? await fetchMetadata(session: session) {
            return info
        }
        return try await fetchFromGitHubAPI(session: session)
    }

    /// Reads `latest.json` from raw.githubusercontent.com. Returns nil when the
    /// repo hasn't published one yet (404) or it is malformed.
    fileprivate static func fetchMetadata(session: URLSession) async throws -> UpdateInfo? {
        var request = URLRequest(url: UpdaterConfig.latestMetadataURL)
        request.timeoutInterval = 10
        request.setValue("SpaceLabeler/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            let meta = try? JSONDecoder().decode(LatestMetadata.self, from: data),
            let version = AppVersion(raw: meta.version),
            let url = URL(string: meta.url)
        else { return nil }
        return UpdateInfo(version: version, downloadURL: url, sha256: meta.sha256)
    }

    /// Legacy source: the GitHub `releases/latest` API. The asset's checksum
    /// is unknown here, so the downloaded zip is not verified — keep using
    /// `latest.json` (checksummed) by publishing releases with the workflow's
    /// "Publish latest.json" step.
    fileprivate static func fetchFromGitHubAPI(session: URLSession) async throws -> UpdateInfo {
        var request = URLRequest(url: UpdaterConfig.latestReleaseURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SpaceLabeler/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let zipAsset = release.zipAsset else { throw UpdateError.noZipAsset }
        guard let version = AppVersion(raw: release.tagName) else {
            throw UpdateError.processFailed("Unrecognized latest release tag: \(release.tagName)")
        }
        return UpdateInfo(version: version, downloadURL: zipAsset.browserDownloadURL, sha256: nil)
    }

    /// Downloads the zip under Application Support, verifies its SHA-256 when
    /// the expected digest is known, extracts it, and returns the staged
    /// SpaceLabeler.app bundle.
    fileprivate static func downloadAndExtract(
        url: URL,
        session: URLSession,
        expectedSHA256: String?
    ) async throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SpaceLabeler", isDirectory: true)
            .appendingPathComponent("Updater", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let zipURL = base.appendingPathComponent("download-\(stamp).zip")
        let stageURL = base.appendingPathComponent("stage-\(stamp)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (tmpURL, _) = try await session.download(for: request)
        try fm.moveItem(at: tmpURL, to: zipURL)

        if let expectedSHA256 {
            let digest = try sha256(of: zipURL)
            guard digest == expectedSHA256.lowercased() else {
                try? fm.removeItem(at: zipURL)
                throw UpdateError.checksumMismatch
            }
        }

        try await runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, stageURL.path])
        try? fm.removeItem(at: zipURL)

        let appURL = stageURL.appendingPathComponent("SpaceLabeler.app")
        guard fm.fileExists(atPath: appURL.path) else { throw UpdateError.invalidArchive }
        return appURL
    }

    /// Hex SHA-256 digest of a file, e.g. "f3316096…e26c8". Nonisolated so the
    /// test target can lock the expected digest format down without actor hops.
    nonisolated static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Writes the swap-and-relaunch script and detaches it. The script waits
    /// for this process to exit (the caller terminates the app right after),
    /// then overwrites the installed bundle in place and relaunches it.
    fileprivate static func launchInstaller(newApp: URL) throws {
        let fm = FileManager.default
        let installDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let destination = installDir.appendingPathComponent(newApp.lastPathComponent)
        let stageDir = newApp.deletingLastPathComponent()
        let script = """
            #!/bin/bash
            set -e
            NAME="SpaceLabeler"
            DEST="\(destination.path)"
            NEW="\(newApp.path)"
            STAGE="\(stageDir.path)"
            while pgrep -x "$NAME" >/dev/null 2>&1; do sleep 0.3; done
            rm -rf "$DEST"
            ditto "$NEW" "$DEST"
            rm -rf "$STAGE"
            open "$DEST"
            """
        let scriptURL = fm.temporaryDirectory
            .appendingPathComponent("space-labeler-update-\(Int(Date().timeIntervalSince1970)).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    /// Runs a process to completion, throwing if it exits non-zero.
    fileprivate static func runProcess(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: UpdateError.processFailed(
                            "\(executable) exited with status \(p.terminationStatus)"
                        )
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

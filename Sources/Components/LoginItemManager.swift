import AppKit
import Combine
import Security
import ServiceManagement

/// Login configuration is not the same as Background Task Management authorization.
@MainActor
final class LoginItemManager: ObservableObject {
    enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case legacyConfigured
    }

    static let shared = LoginItemManager(dependencies: .live)

    @Published private(set) var status: Status = .notRegistered
    @Published private(set) var errorMessage: String?

    /// Whether a login configuration exists. `legacyConfigured` does NOT imply system approval.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval || status == .legacyConfigured
    }

    struct Dependencies {
        var isFormallySigned: () throws -> Bool
        var serviceStatus: () -> Status
        var register: () throws -> Void
        var unregister: () throws -> Void
        var readLegacy: () throws -> Data?
        var writeLegacy: (Data) throws -> Void
        var removeLegacy: () throws -> Void
        var executableURL: URL
        var acceptedLegacyExecutables: [URL]
        var executableExists: () -> Bool
        var openSettings: () -> Void
    }

    private let dependencies: Dependencies
    static let legacyLabel = "com.jeremywatt.SpaceLabeler"

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        refresh()  // Observation only: never register at application startup.
    }

    func refresh() {
        errorMessage = nil
        do {
            status = try observedStatus()
        } catch {
            status = .notFound
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            // Validate before touching either backend. Never overwrite/remove a foreign plist.
            let legacy = try validatedLegacy()
            let formallySigned = try dependencies.isFormallySigned()
            if enabled {
                if legacy != nil {
                    status = .legacyConfigured
                    return  // No migration, reload, or second registration behind the user's back.
                }
                if formallySigned {
                    // A disabled/approval-pending record is resolved by the user in Settings,
                    // not by unregister/register cycling to evade their system preference.
                    if dependencies.serviceStatus() == .notRegistered {
                        try dependencies.register()
                    }
                } else {
                    guard dependencies.executableExists() else { throw Failure.missingExecutable }
                    try dependencies.writeLegacy(Self.legacyPlist(executableURL: dependencies.executableURL))
                    // Deliberately do not load/bootstrap/enable: RunAtLoad applies at next login.
                }
            } else {
                if legacy != nil {
                    try dependencies.removeLegacy()
                    // Never bootout/unload: launchd may own this very process. The old script's
                    // KeepAlive=false job can stay loaded until logout without respawning us.
                }
                if formallySigned, dependencies.serviceStatus() != .notRegistered {
                    try dependencies.unregister()
                }
            }
            status = try observedStatus()
        } catch {
            // Re-observe after partial failures, but retain the original actionable error.
            status = (try? observedStatus()) ?? .notFound
            errorMessage = error.localizedDescription
        }
    }

    func openSystemSettings() { dependencies.openSettings() }

    private func observedStatus() throws -> Status {
        if try validatedLegacy() != nil { return .legacyConfigured }
        return try dependencies.isFormallySigned() ? dependencies.serviceStatus() : .notRegistered
    }

    private func validatedLegacy() throws -> Data? {
        guard let data = try dependencies.readLegacy() else { return nil }
        guard Self.isOwnedLegacyPlist(data, acceptedExecutables: dependencies.acceptedLegacyExecutables)
        else { throw Failure.foreignLegacyPlist }
        return data
    }

    static func legacyPlist(executableURL: URL) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": legacyLabel,
                "ProgramArguments": [executableURL.path],
                "RunAtLoad": true,
                "KeepAlive": false,
            ], format: .xml, options: 0)
    }

    /// Restrict deletion to the exact non-respawning job emitted by our installer.
    static func isOwnedLegacyPlist(_ data: Data, acceptedExecutables: [URL]) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = plist as? [String: Any],
            Set(dictionary.keys) == Set(["Label", "ProgramArguments", "RunAtLoad", "KeepAlive"]),
            dictionary["Label"] as? String == legacyLabel,
            let arguments = dictionary["ProgramArguments"] as? [String], arguments.count == 1,
            let runAtLoad = dictionary["RunAtLoad"] as? NSNumber,
            CFGetTypeID(runAtLoad) == CFBooleanGetTypeID(), runAtLoad.boolValue,
            let keepAlive = dictionary["KeepAlive"] as? NSNumber,
            CFGetTypeID(keepAlive) == CFBooleanGetTypeID(), !keepAlive.boolValue
        else { return false }
        return acceptedExecutables.contains { $0.standardizedFileURL.path == arguments[0] }
    }

    private enum Failure: LocalizedError {
        case foreignLegacyPlist
        case missingExecutable
        case unsafeLegacyPath
        case signature(OSStatus)

        var errorDescription: String? {
            switch self {
            case .foreignLegacyPlist:
                return L10n.t("loginItem.foreignPlist")
            case .missingExecutable:
                return L10n.t("loginItem.missingExecutable")
            case .unsafeLegacyPath:
                return L10n.t("loginItem.unsafePath")
            case .signature(let code):
                return L10n.t("loginItem.signatureError", code)
            }
        }
    }

    fileprivate static func isFormallySigned() throws -> Bool {
        var code: SecCode?
        let copyResult = SecCodeCopySelf([], &code)
        guard copyResult == errSecSuccess, let code else { throw Failure.signature(copyResult) }
        var staticCode: SecStaticCode?
        let staticResult = SecCodeCopyStaticCode(code, [], &staticCode)
        guard staticResult == errSecSuccess, let staticCode else { throw Failure.signature(staticResult) }
        var information: CFDictionary?
        let result = SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        if result == errSecCSUnsigned { return false }
        guard result == errSecSuccess, let dictionary = information as? [String: Any]
        else { throw Failure.signature(result) }
        // A certificate-backed identity with a Team ID is required. Ad-hoc and unsigned
        // builds cannot claim the SMAppService result represents persisted authorization.
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        return flags & SecCodeSignatureFlags.adhoc.rawValue == 0 && !(team?.isEmpty ?? true)
    }
}

extension LoginItemManager.Dependencies {
    @MainActor
    static var live: Self {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let directory = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plist = directory.appendingPathComponent("\(LoginItemManager.legacyLabel).plist")
        let executable =
            Bundle.main.executableURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SpaceLabeler")
        let installed = home.appendingPathComponent("Applications/SpaceLabeler.app/Contents/MacOS/SpaceLabeler")
        let systemInstalled = URL(fileURLWithPath: "/Applications/SpaceLabeler.app/Contents/MacOS/SpaceLabeler")

        // Reject symlinks (including the LaunchAgents directory) and non-user-owned files.
        func validatePath(_ url: URL, directory expectedDirectory: Bool) throws {
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try manager.attributesOfItem(atPath: url.path)
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
            {
                return
            }
            guard attributes[.type] as? FileAttributeType == (expectedDirectory ? .typeDirectory : .typeRegular),
                (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
            else {
                throw NSError(
                    domain: "SpaceLabeler.LoginItem", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: L10n.t("loginItem.unsafePath")
                    ])
            }
        }

        return Self(
            isFormallySigned: { try LoginItemManager.isFormallySigned() },
            serviceStatus: {
                switch SMAppService.mainApp.status {
                case .notRegistered: return .notRegistered
                case .enabled: return .enabled
                case .requiresApproval: return .requiresApproval
                case .notFound: return .notFound
                @unknown default: return .notFound
                }
            },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() },
            readLegacy: {
                try validatePath(directory, directory: true)
                try validatePath(plist, directory: false)
                do { return try Data(contentsOf: plist) } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
                {
                    return nil
                }
            },
            writeLegacy: { data in
                try validatePath(directory, directory: true)
                try validatePath(plist, directory: false)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                // Never clobber a plist created since the initial observation. withoutOverwriting
                // makes a concurrent replacement fail rather than replacing another job.
                try data.write(to: plist, options: .withoutOverwriting)
            },
            removeLegacy: {
                // Recheck ownership/content immediately before removal; refuse foreign replacement.
                try validatePath(directory, directory: true)
                try validatePath(plist, directory: false)
                let data = try Data(contentsOf: plist)
                guard
                    LoginItemManager.isOwnedLegacyPlist(
                        data, acceptedExecutables: [executable, installed, systemInstalled])
                else {
                    throw NSError(
                        domain: "SpaceLabeler.LoginItem", code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: L10n.t("loginItem.changedPlist")
                        ])
                }
                try manager.removeItem(at: plist)
            },
            executableURL: executable,
            acceptedLegacyExecutables: [executable, installed, systemInstalled],
            executableExists: { manager.isExecutableFile(atPath: executable.path) },
            openSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }
}

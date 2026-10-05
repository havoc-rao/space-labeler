import Foundation
import XCTest

@testable import SpaceLabeler

@MainActor
final class LoginItemManagerTests: XCTestCase {
    private final class Fake {
        let executable = URL(fileURLWithPath: "/Applications/Space Labeler & Test.app/Contents/MacOS/SpaceLabeler")
        var formallySigned = false
        var serviceStatus: LoginItemManager.Status = .notRegistered
        var legacy: Data?
        var failure: Error?
        var exists = true
        var registers = 0
        var unregisters = 0
        var writes = 0
        var removals = 0
        var settings = 0

        var dependencies: LoginItemManager.Dependencies {
            .init(
                isFormallySigned: { self.formallySigned },
                serviceStatus: { self.serviceStatus },
                register: {
                    self.registers += 1
                    if let failure = self.failure { throw failure }
                    self.serviceStatus = .requiresApproval
                },
                unregister: {
                    self.unregisters += 1
                    if let failure = self.failure { throw failure }
                    self.serviceStatus = .notRegistered
                },
                readLegacy: { self.legacy },
                writeLegacy: {
                    self.writes += 1
                    if let failure = self.failure { throw failure }
                    self.legacy = $0
                },
                removeLegacy: {
                    self.removals += 1
                    if let failure = self.failure { throw failure }
                    self.legacy = nil
                },
                executableURL: executable,
                acceptedLegacyExecutables: [executable],
                executableExists: { self.exists },
                openSettings: { self.settings += 1 }
            )
        }
    }

    func testInitializationAndRefreshNeverRegister() {
        let fake = Fake()
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.refresh()
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(fake.registers, 0)
        XCTAssertEqual(fake.writes, 0)
    }

    func testPlistRoundTripEscapesPathsAndMatchesInstallerShape() throws {
        let fake = Fake()
        let data = try LoginItemManager.legacyPlist(executableURL: fake.executable)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "com.jeremywatt.SpaceLabeler")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [fake.executable.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, false)
        XCTAssertTrue(LoginItemManager.isOwnedLegacyPlist(data, acceptedExecutables: [fake.executable]))
        XCTAssertFalse(LoginItemManager.isOwnedLegacyPlist(data, acceptedExecutables: []))
    }

    func testAdHocEnableOnlyWritesConfigurationAndDisableOnlyRemovesIt() {
        let fake = Fake()
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(manager.status, .legacyConfigured)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(fake.writes, 1)
        XCTAssertEqual(fake.registers, 0)
        manager.setEnabled(true)
        XCTAssertEqual(fake.writes, 1, "Do not reload/replace an existing job")
        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertEqual(fake.removals, 1)
        XCTAssertEqual(fake.unregisters, 0)
    }

    func testExistingLegacyPlistTakesPrecedenceEvenForSignedBuild() throws {
        let fake = Fake()
        fake.formallySigned = true
        fake.legacy = try LoginItemManager.legacyPlist(executableURL: fake.executable)
        let manager = LoginItemManager(dependencies: fake.dependencies)
        XCTAssertEqual(manager.status, .legacyConfigured)
        manager.setEnabled(true)
        XCTAssertEqual(fake.registers, 0, "Do not create a second login mechanism")
    }

    func testDisableRemovesBothLegacyAndFormalRegistration() throws {
        let fake = Fake()
        fake.formallySigned = true
        fake.serviceStatus = .enabled
        fake.legacy = try LoginItemManager.legacyPlist(executableURL: fake.executable)
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(false)
        XCTAssertEqual(fake.removals, 1)
        XCTAssertEqual(fake.unregisters, 1)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testFormalRegistrationAndApprovalCanBeRevoked() {
        let fake = Fake()
        fake.formallySigned = true
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(fake.registers, 1)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.isEnabled, "Registered request remains on and can be revoked")
        manager.setEnabled(true)
        XCTAssertEqual(fake.registers, 1, "Never cycle registration to bypass system denial")
        manager.setEnabled(false)
        XCTAssertEqual(fake.unregisters, 1)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertEqual(fake.writes, 0)
    }

    func testFormalStatusMappingAndSettingsEntry() {
        let fake = Fake()
        fake.formallySigned = true
        let manager = LoginItemManager(dependencies: fake.dependencies)
        let statuses: [LoginItemManager.Status] = [.notRegistered, .enabled, .requiresApproval, .notFound]
        for status in statuses {
            fake.serviceStatus = status
            manager.refresh()
            XCTAssertEqual(manager.status, status)
        }
        manager.openSystemSettings()
        XCTAssertEqual(fake.settings, 1)
    }

    func testForeignOrMalformedPlistIsNotOverwrittenOrRemoved() throws {
        let fake = Fake()
        let foreign = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": LoginItemManager.legacyLabel,
                "ProgramArguments": [fake.executable.path],
                "RunAtLoad": true,
                "KeepAlive": true,
            ], format: .xml, options: 0)
        for data in [foreign, Data("not a plist".utf8)] {
            fake.legacy = data
            let manager = LoginItemManager(dependencies: fake.dependencies)
            XCTAssertEqual(manager.status, .notFound)
            XCTAssertNotNil(manager.errorMessage)
            manager.setEnabled(true)
            manager.setEnabled(false)
            XCTAssertEqual(fake.legacy, data)
            XCTAssertEqual(fake.writes, 0)
            XCTAssertEqual(fake.removals, 0)
        }
    }

    func testRunAtLoadFalseIsNotReportedAsConfigured() throws {
        let fake = Fake()
        fake.legacy = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": LoginItemManager.legacyLabel,
                "ProgramArguments": [fake.executable.path],
                "RunAtLoad": false,
                "KeepAlive": false,
            ], format: .xml, options: 0)
        let manager = LoginItemManager(dependencies: fake.dependencies)
        XCTAssertEqual(manager.status, .notFound)
        XCTAssertFalse(manager.isEnabled)
        manager.setEnabled(true)
        XCTAssertEqual(fake.writes, 0, "Do not override a user's modified/disabled configuration")
    }

    func testWriteAndRemoveFailuresPreserveObservedStatusAndReportError() throws {
        let fake = Fake()
        fake.failure = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertEqual(manager.errorMessage, "Permission denied")
        fake.legacy = try LoginItemManager.legacyPlist(executableURL: fake.executable)
        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .legacyConfigured)
        XCTAssertEqual(manager.errorMessage, "Permission denied")
        manager.refresh()
        XCTAssertNil(manager.errorMessage)
    }

    func testServiceFailureDoesNotClaimSuccess() {
        let fake = Fake()
        fake.formallySigned = true
        fake.failure = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertNotNil(manager.errorMessage)
        fake.serviceStatus = .enabled
        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testMissingExecutableDoesNotCreateLegacyPlist() {
        let fake = Fake()
        fake.exists = false
        let manager = LoginItemManager(dependencies: fake.dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(fake.writes, 0)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testReadAndSignatureFailuresAreObservable() {
        let fake = Fake()
        var dependencies = fake.dependencies
        dependencies.readLegacy = { throw NSError(domain: "Test", code: 1) }
        var manager = LoginItemManager(dependencies: dependencies)
        XCTAssertEqual(manager.status, .notFound)
        XCTAssertNotNil(manager.errorMessage)
        dependencies = fake.dependencies
        dependencies.isFormallySigned = { throw NSError(domain: "Test", code: 2) }
        manager = LoginItemManager(dependencies: dependencies)
        manager.setEnabled(true)
        XCTAssertEqual(manager.status, .notFound)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertEqual(fake.writes, 0)
    }
}

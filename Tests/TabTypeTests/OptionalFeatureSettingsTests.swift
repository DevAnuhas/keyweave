import Foundation
import XCTest
@testable import TabType

@MainActor
final class OptionalFeatureSettingsTests: XCTestCase {
    func testLocalOptInsCanBeEnabledAndPersist() throws {
        let domain = "dev.anuhas.keyweave.tests.optins.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        defaults.set("Synthetic writer", forKey: "authorName")
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.useScreenContext)
        XCTAssertFalse(settings.useClipboardContext)
        XCTAssertFalse(settings.useScreenshotAppearance)
        XCTAssertFalse(settings.collectTypingHistory)
        XCTAssertFalse(settings.recordWithoutAccepts)

        settings.useScreenContext = true
        settings.useClipboardContext = true
        settings.useScreenshotAppearance = true
        settings.collectTypingHistory = true
        settings.recordWithoutAccepts = true
        let reopened = AppSettings(defaults: defaults)
        XCTAssertTrue(reopened.useScreenContext)
        XCTAssertTrue(reopened.useClipboardContext)
        XCTAssertTrue(reopened.useScreenshotAppearance)
        XCTAssertTrue(reopened.collectTypingHistory)
        XCTAssertTrue(reopened.recordWithoutAccepts)
    }

    func testRemoteSettingsCannotGrantLocalConsentOrWeakenAppExclusions() throws {
        let domain = "dev.anuhas.keyweave.tests.remote-consent.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        defaults.set("Synthetic writer", forKey: "authorName")
        let settings = AppSettings(defaults: defaults)
        var local = AppOverride()
        local.enabled = false
        local.readConversation = false
        local.learnFromWriting = false
        settings.appOverrides = ["com.example.private": local]
        settings.disabledDomains = ["private.example"]
        var remote = settings.syncSnapshot
        remote.useScreenContext = true
        remote.useClipboardContext = true
        remote.useScreenshotAppearance = true
        remote.collectTypingHistory = true
        remote.recordWithoutAccepts = true
        remote.completionLength = "long"
        var remoteOverride = AppOverride()
        remoteOverride.enabled = true
        remoteOverride.readConversation = true
        remoteOverride.learnFromWriting = true
        remote.appOverrides = ["com.example.private": remoteOverride,
                               "com.example.new": remoteOverride]
        remote.disabledDomains = []
        settings.apply(remote)

        XCTAssertFalse(settings.useScreenContext)
        XCTAssertFalse(settings.useClipboardContext)
        XCTAssertFalse(settings.useScreenshotAppearance)
        XCTAssertFalse(settings.collectTypingHistory)
        XCTAssertFalse(settings.recordWithoutAccepts)
        XCTAssertEqual(settings.completionLength, "long", "Ordinary writing preferences still sync")
        XCTAssertEqual(settings.appOverrides["com.example.private"]?.enabled, false)
        XCTAssertEqual(settings.appOverrides["com.example.private"]?.readConversation, false)
        XCTAssertEqual(settings.appOverrides["com.example.private"]?.learnFromWriting, false)
        XCTAssertNil(settings.appOverrides["com.example.new"]?.readConversation)
        XCTAssertNil(settings.appOverrides["com.example.new"]?.learnFromWriting)
        XCTAssertTrue(settings.disabledDomains.contains("private.example"))
    }

    func testPerAppRecipesCannotBypassGlobalOptOut() throws {
        let domain = "dev.anuhas.keyweave.tests.effective-consent.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        defaults.set("Synthetic writer", forKey: "authorName")
        let settings = AppSettings(defaults: defaults)
        var override = AppOverride()
        override.readConversation = true
        override.learnFromWriting = true
        settings.appOverrides = ["com.example.synthetic": override]
        let engine = Engine(settings: settings, accessibilityTrusted: { false })
        var policy = AppPolicyStore.policy(forBundleId: "com.example.synthetic")
        policy.forceScreenContext = true
        XCTAssertFalse(engine.usesScreenContext(for: policy))
        XCTAssertFalse(engine.learnsFromWriting("com.example.synthetic"))
        settings.useScreenContext = true
        settings.collectTypingHistory = true
        XCTAssertTrue(engine.usesScreenContext(for: policy))
        XCTAssertTrue(engine.learnsFromWriting("com.example.synthetic"))
        policy.isEnabled = false
        XCTAssertFalse(engine.usesScreenContext(for: policy))
    }
    func testPrivacyRevisionChangesBeforeDeferredObserversRun() throws {
        let domain = "dev.anuhas.keyweave.tests.privacy-revision.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        let settings = AppSettings(defaults: defaults)
        let initial = settings.privacyRevision
        settings.useClipboardContext = true
        XCTAssertNotEqual(settings.privacyRevision, initial)
        let beforeExclusion = settings.privacyRevision
        var excluded = AppOverride()
        excluded.enabled = false
        settings.appOverrides = ["com.example.private": excluded]
        XCTAssertNotEqual(settings.privacyRevision, beforeExclusion)
        let beforeDomain = settings.privacyRevision
        settings.disabledDomains = ["private.example"]
        XCTAssertNotEqual(settings.privacyRevision, beforeDomain)
    }

    func testAppAndDomainExclusionsNarrowContextAndLearningConsent() throws {
        let domain = "dev.anuhas.keyweave.tests.scoped-consent.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        let settings = AppSettings(defaults: defaults)
        settings.useScreenContext = true
        settings.collectTypingHistory = true
        var excluded = AppOverride()
        excluded.readConversation = false
        excluded.learnFromWriting = false
        settings.appOverrides = ["com.example.private": excluded,
                                 "domain:private.example": excluded]
        let engine = Engine(settings: settings, accessibilityTrusted: { false })
        XCTAssertFalse(engine.usesScreenContext(for: AppPolicyStore.policy(forBundleId: "com.example.private")))
        XCTAssertFalse(engine.usesScreenContext(for: AppPolicyStore.policy(forBundleId: "com.example.browser", host: "sub.private.example")))
        XCTAssertFalse(engine.learnsFromWriting("com.example.browser", host: "sub.private.example"))
        settings.disabledDomains = ["blocked.example"]
        XCTAssertFalse(engine.learnsFromWriting("com.example.browser", host: "sub.blocked.example"))
        XCTAssertTrue(engine.learnsFromWriting("com.example.browser", host: "allowed.example"))
    }
}

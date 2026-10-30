import Combine
import Foundation
import XCTest
@testable import TabType

@MainActor
private final class SyntheticUpdateDriver: UpdateDriver {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var lastUpdateCheckDate: Date?
    let changed = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changed.eraseToAnyPublisher() }
    var starts = 0
    var checks = 0
    var startError: Error?
    func start() throws {
        starts += 1
        if let startError { throw startError }
    }
    func checkForUpdates() { checks += 1 }
}

final class UpdateLifecycleTests: XCTestCase {
    @MainActor
    func testConstructionIsPassiveAndExplicitStartSchedulesOnlyOnce() {
        let driver = SyntheticUpdateDriver()
        var constructions = 0
        let updater = Updater(allowed: true, makeDriver: {
            constructions += 1
            return driver
        })
        XCTAssertEqual(constructions, 0)
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.start()
        updater.start()
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(driver.starts, 1)
        XCTAssertTrue(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
        updater.automatic = false
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        driver.canCheckForUpdates = false
        driver.changed.send()
        updater.checkForUpdates()
        XCTAssertEqual(driver.checks, 1, "A busy updater must not start another session")
    }

    @MainActor
    func testManualCheckStillWorksWhenScheduledChecksAreOff() {
        let driver = SyntheticUpdateDriver()
        driver.automaticallyChecksForUpdates = false
        let updater = Updater(allowed: true, makeDriver: { driver })
        updater.start()
        updater.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        let checked = Date(timeIntervalSince1970: 1_793_347_200)
        driver.lastUpdateCheckDate = checked
        driver.changed.send()
        XCTAssertEqual(updater.lastCheckDate, checked)
    }

    @MainActor
    func testStartFailureIsVisibleAndCanBeRetriedWithoutStartingACheck() {
        let driver = SyntheticUpdateDriver()
        driver.startError = NSError(domain: "synthetic.update", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Missing update configuration"])
        let updater = Updater(allowed: true, makeDriver: { driver })
        updater.start()
        updater.checkForUpdates()
        XCTAssertFalse(updater.isRunning)
        XCTAssertEqual(updater.failure, "Missing update configuration")
        XCTAssertEqual(driver.checks, 0)
        driver.startError = nil
        updater.start()
        XCTAssertTrue(updater.isRunning)
        XCTAssertNil(updater.failure)
    }

    func testOnlyTheSignedForkConfigurationCanActivateUpdates() {
        func allows(id: String = "dev.anuhas.keyweave", app: Bool = true,
                    feed: String = "https://raw.githubusercontent.com/DevAnuhas/keyweave/main/Updates/appcast.xml",
                    key: String = "pc1gLnpongI0flX6p0FOVK509djxXgyrKN8rcMB4bRU=",
                    signed: Bool = true, verified: Bool = true, test: Bool = false) -> Bool {
            Updater.permits(bundleIdentifier: id, isApplication: app, feed: feed,
                            key: key, signedFeed: signed, verifiedExtraction: verified, isTestProcess: test)
        }
        XCTAssertTrue(allows())
        XCTAssertFalse(allows(id: "app.tabtype.TabType"))
        XCTAssertFalse(allows(app: false))
        XCTAssertFalse(allows(feed: "https://raw.githubusercontent.com/nilava/TabType/main/appcast.xml"))
        XCTAssertFalse(allows(key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
        XCTAssertFalse(allows(signed: false))
        XCTAssertFalse(allows(verified: false))
        XCTAssertFalse(allows(test: true))
    }
}

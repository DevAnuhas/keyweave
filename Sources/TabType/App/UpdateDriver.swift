import Combine
import Foundation
import Sparkle

/// The update service boundary. Construction must not schedule a check.
@MainActor
protocol UpdateDriver: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    var changes: AnyPublisher<Void, Never> { get }
    func start() throws
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateDriver: UpdateDriver {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    var changes: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            controller.updater.publisher(for: \.canCheckForUpdates).map { _ in () },
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).map { _ in () },
            controller.updater.publisher(for: \.lastUpdateCheckDate).map { _ in () }
        ).eraseToAnyPublisher()
    }

    func start() throws {
        // Never send system profiling, including a persisted setting from an
        // earlier build. Update checks use only the KeyWeave appcast.
        controller.updater.sendsSystemProfile = false
        try controller.updater.start()
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

import Foundation
import XCTest
@testable import TabType

final class LogTests: XCTestCase {
    func testConstructionPreservesExistingLogBytesAndDoesNotCreateDirectories() throws {
        try withDirectory { directory in
            let active = directory.appendingPathComponent("keyweave.log")
            let previous = directory.appendingPathComponent("keyweave.1.log")
            let oversized = oversizedLog(ending: "synthetic existing tail\n")
            let archive = Data("synthetic archive sentinel\n".utf8)
            try oversized.write(to: active, options: .withoutOverwriting)
            try archive.write(to: previous, options: .withoutOverwriting)

            for _ in 0..<3 {
                _ = Log(directory: directory)
                _ = Log(directory: directory.appendingPathComponent("absent"))
            }

            XCTAssertEqual(try Data(contentsOf: active), oversized)
            XCTAssertEqual(try Data(contentsOf: previous), archive)
            XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)),
                           ["keyweave.log", "keyweave.1.log"])
        }
    }

    func testFirstQueuedWriteRotatesAnOversizedLog() throws {
        try withDirectory { directory in
            let active = directory.appendingPathComponent("keyweave.log")
            let previous = directory.appendingPathComponent("keyweave.1.log")
            try oversizedLog(ending: "synthetic retained tail\n").write(to: active, options: .withoutOverwriting)
            try Data("synthetic old archive\n".utf8).write(to: previous, options: .withoutOverwriting)
            let log = Log(directory: directory)

            log.info("synthetic first write")
            log.flush()

            XCTAssertEqual(try Data(contentsOf: previous), Data("synthetic retained tail\n".utf8))
            let current = try String(contentsOf: active, encoding: .utf8)
            XCTAssertTrue(current.hasSuffix("] synthetic first write\n"))
            XCTAssertLessThan(current.utf8.count, 100)
        }
    }

    func testRepeatedShortSessionsCannotAvoidRotation() throws {
        try withDirectory { directory in
            let active = directory.appendingPathComponent("keyweave.log")
            let previous = directory.appendingPathComponent("keyweave.1.log")
            var retainedTail = "synthetic initial tail\n"
            try oversizedLog(ending: retainedTail).write(to: active, options: .withoutOverwriting)

            // Each instance represents a fresh session with only two writes,
            // well below the periodic check interval.
            for session in 1...3 {
                let beforeConstruction = try Data(contentsOf: active)
                let log = Log(directory: directory)
                log.flush()
                XCTAssertEqual(try Data(contentsOf: active), beforeConstruction)

                log.info("synthetic session \(session) started")
                log.flush()
                XCTAssertEqual(try Data(contentsOf: previous), Data(retainedTail.utf8))
                let current = try String(contentsOf: active, encoding: .utf8)
                XCTAssertTrue(current.hasSuffix("] synthetic session \(session) started\n"))
                XCTAssertLessThan(current.utf8.count, 100)

                retainedTail = "synthetic session \(session) tail\n"
                log.info(String(repeating: "B", count: Int(Log.maxBytes) + 1) + "\n" + retainedTail.dropLast())
                log.flush()
                XCTAssertGreaterThan(try Data(contentsOf: active).count, Int(Log.maxBytes))
            }
        }
    }

    func testLongSessionRechecksAfterFiveHundredAdditionalWrites() throws {
        try withDirectory { directory in
            let active = directory.appendingPathComponent("keyweave.log")
            let previous = directory.appendingPathComponent("keyweave.1.log")
            let log = Log(directory: directory)
            log.info(String(repeating: "A", count: Int(Log.maxBytes) + 1) + "\nsynthetic periodic tail")
            log.flush()
            XCTAssertGreaterThan(try Data(contentsOf: active).count, Int(Log.maxBytes))
            XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path))

            for write in 1...500 { log.info("synthetic periodic \(write)") }
            log.flush()

            let archive = try String(contentsOf: previous, encoding: .utf8)
            XCTAssertTrue(archive.hasPrefix("synthetic periodic tail\n"))
            XCTAssertEqual(archive.split(separator: "\n").count, 500)
            XCTAssertLessThanOrEqual(archive.utf8.count, Log.keptBytes)
            let current = try String(contentsOf: active, encoding: .utf8)
            XCTAssertTrue(current.hasSuffix("] synthetic periodic 500\n"))
            XCTAssertLessThan(current.utf8.count, 100)
        }
    }

    private func oversizedLog(ending: String) -> Data {
        var data = Data(repeating: 65, count: Int(Log.maxBytes) + 1)
        data.append(Data(("\n" + ending).utf8))
        return data
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyweave-log-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

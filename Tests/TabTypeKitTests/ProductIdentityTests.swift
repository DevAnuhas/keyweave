import Foundation
import XCTest
import TabTypeKit

final class ProductIdentityTests: XCTestCase {
    func testAppBundleAndPersistentIdentitiesBelongToKeyweave() throws {
        XCTAssertEqual(ProductIdentity.name, "KeyWeave")
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "dev.anuhas.keyweave")
        XCTAssertEqual(ProductIdentity.preferencesDomain, "dev.anuhas.keyweave")
        XCTAssertEqual(ProductIdentity.keychainService, "dev.anuhas.keyweave.sync")
        XCTAssertEqual(ProductIdentity.syncFolderName, "Keyweave Sync")
        XCTAssertEqual(ProductIdentity.syncFileExtension, "keyweavesync")

        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, ProductIdentity.name)
        XCTAssertEqual(plist["CFBundleName"] as? String, ProductIdentity.name)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, ProductIdentity.name)
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, ProductIdentity.bundleIdentifier)
        XCTAssertTrue((plist["NSHumanReadableCopyright"] as? String ?? "").contains("MIT"))
        XCTAssertTrue((plist["NSHumanReadableCopyright"] as? String ?? "").contains("TabType contributors"))
    }

    func testConstructingPathsAndReadingEveryGetterLeavesSyntheticStoresUntouched() throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("keyweave-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: home) }
        let sentinelPaths = [
            "Library/Application Support/TabType/Models/upstream-sentinel",
            "Library/Application Support/Cotypist/private-sentinel",
            "Library/Caches/TabType/upstream-sentinel",
            "Library/Logs/TabType/fit/upstream-sentinel",
            "Library/Mobile Documents/com~apple~CloudDocs/TabType Sync/upstream-sentinel",
        ]
        for relativePath in sentinelPaths {
            let sentinel = home.appendingPathComponent(relativePath)
            try manager.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic upstream sentinel".utf8).write(to: sentinel)
        }
        let before = try snapshot(home)

        let paths = AppPaths(homeDirectory: home)
        XCTAssertEqual(paths.homeDirectory, home)
        XCTAssertEqual(paths.supportDirectory.path, home.path + "/Library/Application Support/Keyweave")
        XCTAssertEqual(paths.modelsDirectory.path, home.path + "/Library/Application Support/Keyweave/Models")
        XCTAssertEqual(paths.cacheDirectory.path, home.path + "/Library/Caches/Keyweave")
        XCTAssertEqual(paths.logsDirectory.path, home.path + "/Library/Logs/Keyweave")
        XCTAssertEqual(paths.fitCapturesDirectory.path, home.path + "/Library/Logs/Keyweave/fit")
        XCTAssertEqual(paths.syncDirectory.path, home.path + "/Library/Mobile Documents/com~apple~CloudDocs/Keyweave Sync")

        XCTAssertEqual(try snapshot(home), before)
    }

    func testCurrentUsesTheExplicitSyntheticProcessHome() throws {
        guard let home = ProcessInfo.processInfo.environment["KEYWEAVE_TEST_HOME"], home.hasPrefix("/") else {
            throw XCTSkip("Run with an absolute KEYWEAVE_TEST_HOME to test the controlled process override")
        }
        let expectedHome = URL(fileURLWithPath: home, isDirectory: true)
        XCTAssertEqual(AppPaths.current.homeDirectory, expectedHome)
        XCTAssertEqual(AppPaths.current.modelsDirectory,
                       expectedHome.appendingPathComponent("Library/Application Support/Keyweave/Models", isDirectory: true))
    }

    func testReleaseHelperRefusesBeforeChangingFilesOrInvokingDistributionTools() throws {
        let manager = FileManager.default
        let fixture = try makeFixture()
        defer { try? manager.removeItem(at: fixture) }
        let script = fixture.appendingPathComponent("Scripts/release.sh")
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Scripts/release.sh"), to: script)
        let plist = fixture.appendingPathComponent("Resources/Info.plist")
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Resources/Info.plist"), to: plist)
        let originalPlist = try Data(contentsOf: plist)
        let calls = fixture.appendingPathComponent("tool-calls")
        let toolStub = "#!/bin/bash\nprintf '%s\\n' \"$0 $*\" >> \"$KEYWEAVE_TEST_CALLS\"\necho 1\n"
        for name in ["plutil", "codesign", "hdiutil", "security", "xcrun", "swift"] {
            try writeExecutable(toolStub, at: fixture.appendingPathComponent("bin/\(name)"))
        }
        try writeExecutable("#!/bin/bash\nprintf 'build called\\n' >> \"$KEYWEAVE_TEST_CALLS\"\nexit 90\n",
                            at: fixture.appendingPathComponent("Scripts/build.sh"))
        let before = try snapshot(fixture)

        let result = try runScript(script, arguments: [], fixture: fixture,
                                   environment: ["KEYWEAVE_TEST_CALLS": calls.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Release requires SIGN_IDENTITY"), result.output)
        XCTAssertEqual(try Data(contentsOf: plist), originalPlist)
        XCTAssertFalse(manager.fileExists(atPath: calls.path), "Release must refuse before calling tools")
        XCTAssertEqual(try snapshot(fixture), before)
    }

    func testBuildHelperPackagesInternalTargetWithIsolatedKeyweaveIdentityAndCaches() throws {
        let manager = FileManager.default
        let fixture = try makeFixture()
        defer { try? manager.removeItem(at: fixture) }
        let script = fixture.appendingPathComponent("Scripts/build.sh")
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Scripts/build.sh"), to: script)
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Resources/Info.plist"),
                             to: fixture.appendingPathComponent("Resources/Info.plist"))
        let calls = fixture.appendingPathComponent("tool-calls")
        try writeExecutable("""
        #!/bin/bash
        printf 'xcrun\\n' >> "$KEYWEAVE_TEST_CALLS"
        printf '%s\\n' "$@" >> "$KEYWEAVE_TEST_CALLS"
        derived=""
        config="Debug"
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -derivedDataPath) derived="$2"; shift ;;
                -configuration) config="$2"; shift ;;
            esac
            shift
        done
        products="$derived/Build/Products/$config"
        mkdir -p "$products/llama.framework" "$products/TabType_TabType.bundle"
        sparkle="$products/Sparkle.framework/Versions/B"
        mkdir -p "$sparkle/XPCServices/Downloader.xpc" "$sparkle/XPCServices/Installer.xpc" "$sparkle/Updater.app"
        printf 'synthetic helper' > "$sparkle/Autoupdate"
        ln -s B "$products/Sparkle.framework/Versions/Current"
        printf 'synthetic executable' > "$products/TabType"
        printf 'synthetic resource' > "$products/TabType_TabType.bundle/resource"
        """, at: fixture.appendingPathComponent("bin/xcrun"))
        try writeExecutable("#!/bin/bash\necho '1) synthetic \"Keyweave Dev\"'\n",
                            at: fixture.appendingPathComponent("bin/security"))
        for tool in ["codesign", "install_name_tool"] {
            try writeExecutable("#!/bin/bash\nprintf '\(tool)\\n' >> \"$KEYWEAVE_TEST_CALLS\"\nprintf '%s\\n' \"$@\" >> \"$KEYWEAVE_TEST_CALLS\"\n",
                                at: fixture.appendingPathComponent("bin/\(tool)"))
        }

        let result = try runScript(script, arguments: ["app"], fixture: fixture,
                                   environment: ["KEYWEAVE_TEST_CALLS": calls.path])

        XCTAssertEqual(result.status, 0, result.output)
        let app = fixture.appendingPathComponent("dist/KeyWeave.app")
        let executable = app.appendingPathComponent("Contents/MacOS/KeyWeave")
        XCTAssertTrue(manager.fileExists(atPath: executable.path), result.output)
        if manager.fileExists(atPath: executable.path) {
            XCTAssertEqual(try String(contentsOf: executable, encoding: .utf8), "synthetic executable")
            let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["CFBundleExecutable"] as? String, "KeyWeave")
            XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.anuhas.keyweave")
            XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("Contents/Resources/TabType_TabType.bundle/resource"),
                                      encoding: .utf8), "synthetic resource")
        }
        XCTAssertFalse(manager.fileExists(atPath: fixture.appendingPathComponent("dist/TabType.app").path))
        XCTAssertFalse(manager.fileExists(atPath: fixture.appendingPathComponent(".build-xcode").path))
        let arguments = try String(contentsOf: calls, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertTrue(arguments.contains("TabType"), "Internal target remains TabType")
        XCTAssertTrue(arguments.contains("dev.anuhas.keyweave"))
        XCTAssertTrue(arguments.contains("Keyweave Dev"))
        XCTAssertTrue(arguments.contains("-packageCachePath"))
        XCTAssertTrue(arguments.contains("-clonedSourcePackagesDirPath"))
        for option in ["-derivedDataPath", "-packageCachePath", "-clonedSourcePackagesDirPath"] {
            if let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) {
                XCTAssertTrue(arguments[index + 1].hasPrefix(fixture.path + "/.build-keyweave/"), option)
            } else {
                XCTFail("Missing isolated build option: \(option)")
            }
        }

        try Data().write(to: calls)
        let adHoc = try runScript(script, arguments: ["app"], fixture: fixture, environment: [
            "KEYWEAVE_TEST_CALLS": calls.path, "SIGN_IDENTITY": "Keyweave Synthetic Missing",
        ])
        XCTAssertEqual(adHoc.status, 0, adHoc.output)
        let adHocArguments = try String(contentsOf: calls, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertTrue(adHocArguments.contains("dev.anuhas.keyweave"))
        XCTAssertTrue(adHocArguments.contains("-"))
    }

    func testEvalBuildHelperUsesDedicatedScratchAndCacheDirectories() throws {
        let manager = FileManager.default
        let fixture = try makeFixture()
        defer { try? manager.removeItem(at: fixture) }
        let script = fixture.appendingPathComponent("Scripts/build.sh")
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Scripts/build.sh"), to: script)
        let calls = fixture.appendingPathComponent("tool-calls")
        try writeExecutable("#!/bin/bash\nprintf '%s\\n' \"$@\" >> \"$KEYWEAVE_TEST_CALLS\"\n",
                            at: fixture.appendingPathComponent("bin/swift"))

        let result = try runScript(script, arguments: ["eval"], fixture: fixture,
                                   environment: ["KEYWEAVE_TEST_CALLS": calls.path])

        XCTAssertEqual(result.status, 0, result.output)
        let arguments = try String(contentsOf: calls, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertTrue(arguments.contains("tabtype-eval"))
        for option in ["--scratch-path", "--cache-path", "--config-path", "--security-path"] {
            let index = try XCTUnwrap(arguments.firstIndex(of: option), option)
            let path = try XCTUnwrap(arguments.dropFirst(index + 1).first, option)
            XCTAssertTrue(path.hasPrefix(fixture.path + "/.build-keyweave/"), option)
        }
        XCTAssertFalse(manager.fileExists(atPath: fixture.appendingPathComponent(".build").path))
    }

    func testSigningSetupRecognizesExistingKeyweaveIdentityWithoutChangingKeychainOrTrust() throws {
        let manager = FileManager.default
        let fixture = try makeFixture()
        defer { try? manager.removeItem(at: fixture) }
        let script = fixture.appendingPathComponent("Scripts/setup-signing.sh")
        try manager.copyItem(at: repositoryRoot.appendingPathComponent("Scripts/setup-signing.sh"), to: script)
        let calls = fixture.appendingPathComponent("tool-calls")
        try writeExecutable("""
        #!/bin/bash
        if [ "$1" = "find-identity" ]; then
            echo '1) synthetic "Keyweave Dev"'
            exit 0
        fi
        printf 'unexpected keychain mutation\\n' >> "$KEYWEAVE_TEST_CALLS"
        exit 90
        """, at: fixture.appendingPathComponent("bin/security"))
        try writeExecutable("#!/bin/bash\nprintf 'unexpected certificate generation\\n' >> \"$KEYWEAVE_TEST_CALLS\"\nexit 91\n",
                            at: fixture.appendingPathComponent("bin/openssl"))

        let result = try runScript(script, arguments: [], fixture: fixture,
                                   environment: ["KEYWEAVE_TEST_CALLS": calls.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Keyweave Dev"), result.output)
        XCTAssertTrue(result.output.contains("already exists"), result.output)
        XCTAssertFalse(manager.fileExists(atPath: calls.path), "Existing Keyweave identity needs no keychain or trust changes")
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyweave-packaging-\(UUID().uuidString)", isDirectory: true)
        for directory in ["Scripts", "Resources", "bin"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        return root.resolvingSymlinksInPath()
    }

    private func writeExecutable(_ contents: String, at url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runScript(_ script: URL, arguments: [String], fixture: URL,
                           environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = fixture
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": fixture.appendingPathComponent("bin").path + ":/usr/bin:/bin",
            "KEYWEAVE_TEST_HOME": fixture.appendingPathComponent("synthetic-home").path,
            "SIGN_IDENTITY": "",
            "CONFIG": "Debug",
            "RELEASE": "0",
            "DEVELOPMENT_TEAM": "",
            "KEYCHAIN_PROFILE": "",
        ].merging(environment) { _, new in new }) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        let manager = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath()
        let enumerator = try XCTUnwrap(manager.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isRegularFileKey]))
        var contents: [String: Data] = [:]
        for case let url as URL in enumerator {
            let relativePath = String(url.path.dropFirst(canonicalRoot.path.count))
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            contents[relativePath] = values.isRegularFile == true ? try Data(contentsOf: url) : Data()
        }
        return contents
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

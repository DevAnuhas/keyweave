"""Compile the actual preferences source in disposable macOS app bundles.

The bundle ID deliberately equals the explicit synthetic preferences domain.
Only fresh, uniquely named test domains are seeded or removed; no application,
model, SwiftPM dependency, permission prompt, or real KeyWeave domain is used.
"""
import base64
import os
from pathlib import Path
import plistlib
import resource
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import Foundation
import TabTypeKit

@main
struct PreferencesProbe {
    @MainActor static func main() throws {
        let env = ProcessInfo.processInfo.environment
        let domain = AppPreferences.domain(environment: env)
        let sibling = domain + ".sibling"
        precondition(domain.hasPrefix(ProductIdentity.preferencesDomain + ".test."))
        if CommandLine.arguments[1] == "domain" {
            print(domain)
            return
        }
        precondition(Bundle.main.bundleIdentifier == domain,
                     "bundle=\(Bundle.main.bundleIdentifier ?? "nil") explicit=\(domain)")
        let bootstrap = UserDefaults()
        let own: [String: Any] = [
            "text": "owned synthetic value", "flag": true, "number": 37,
            "list": ["synthetic"], "map": ["synthetic": "value"],
            "bytes": Data([1, 2, 3]), "url": "/synthetic/file"
        ]
        if CommandLine.arguments[1] == "seed" {
            bootstrap.setPersistentDomain(own, forName: domain)
            bootstrap.setPersistentDomain([
                "text": "sibling sentinel", "fallbackOnly": "must stay hidden",
                "fallbackFlag": true, "fallbackNumber": 99,
                "fallbackList": ["hidden"], "fallbackMap": ["hidden": "value"],
                "fallbackBytes": Data([9]), "fallbackURL": "/synthetic/hidden"
            ], forName: sibling)
            precondition(bootstrap.synchronize())
            print("seeded disposable domains")
            return
        }
        if CommandLine.arguments[1] == "dump" {
            let stored = bootstrap.persistentDomain(forName: domain)!
            print(try PropertyListSerialization.data(fromPropertyList: stored,
                  format: .binary, options: 0).base64EncodedString())
            return
        }

        let preferences = AppPreferences.makeCurrent(environment: env)
        preferences.addSuite(named: sibling)
        preferences.setVolatileDomain([
            "text": "argument override must stay hidden",
            "argumentOnly": "must stay hidden", "flag": false
        ], forName: UserDefaults.argumentDomain)

        for _ in 0..<2 {
            precondition(preferences.object(forKey: "text") as? String == "owned synthetic value")
            precondition(preferences.string(forKey: "text") == "owned synthetic value")
            precondition(preferences.bool(forKey: "flag"))
            precondition(preferences.integer(forKey: "number") == 37)
            precondition(preferences.float(forKey: "number") == 37)
            precondition(preferences.double(forKey: "number") == 37)
            precondition(preferences.stringArray(forKey: "list") == ["synthetic"])
            precondition(preferences.array(forKey: "list") as? [String] == ["synthetic"])
            precondition(preferences.dictionary(forKey: "map") as? [String: String] == ["synthetic": "value"])
            precondition(preferences.data(forKey: "bytes") == Data([1, 2, 3]))
            precondition(preferences.url(forKey: "url")?.path == "/synthetic/file")
            precondition(preferences.dictionaryRepresentation() as NSDictionary == own as NSDictionary)
            precondition(preferences.object(forKey: "fallbackOnly") == nil)
            precondition(preferences.string(forKey: "argumentOnly") == nil)
            precondition(!preferences.bool(forKey: "fallbackFlag"))
            precondition(preferences.integer(forKey: "fallbackNumber") == 0)
            precondition(preferences.float(forKey: "fallbackNumber") == 0)
            precondition(preferences.double(forKey: "fallbackNumber") == 0)
            precondition(preferences.array(forKey: "fallbackList") == nil)
            precondition(preferences.stringArray(forKey: "fallbackList") == nil)
            precondition(preferences.dictionary(forKey: "fallbackMap") == nil)
            precondition(preferences.data(forKey: "fallbackBytes") == nil)
            precondition(preferences.url(forKey: "fallbackURL") == nil)
        }
        if CommandLine.arguments[1] == "write" {
            preferences.set("only explicit domain", forKey: "newValue")
            preferences.removeObject(forKey: "text")
            precondition(preferences.synchronize())
            let stored = bootstrap.persistentDomain(forName: domain)!
            precondition(stored["newValue"] as? String == "only explicit domain")
            precondition(stored["text"] == nil)
            precondition(preferences.string(forKey: "text") == nil)
            precondition(preferences.string(forKey: "newValue") == "only explicit domain")
        }
        print("PASS: matching bundle/domain constructor, getters, fallback isolation" +
              (CommandLine.arguments[1] == "write" ? ", writes and removal" : ""))
    }
}
'''


@unittest.skipUnless(sys.platform == "darwin", "requires macOS Foundation and Swift")
class AppPreferencesBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="keyweave-preferences-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name).resolve()
        cls.compiler = shutil.which("swiftc")
        if cls.compiler is None:
            raise unittest.SkipTest("swiftc is unavailable")
        module = cls.root / "TabTypeKit.swiftmodule"
        subprocess.run([
            cls.compiler, "-swift-version", "6", "-parse-as-library", "-emit-module",
            "-emit-library", "-module-name", "TabTypeKit",
            str(ROOT / "Sources/TabTypeKit/Identity/ProductIdentity.swift"),
            "-emit-module-path", str(module), "-o", str(cls.root / "libTabTypeKit.dylib")
        ], check=True, capture_output=True, text=True, timeout=60)
        harness = cls.root / "PreferencesProbe.swift"
        harness.write_text(HARNESS)
        cls.executable = cls.root / "PreferencesProbe"
        subprocess.run([
            cls.compiler, "-swift-version", "6", "-parse-as-library", "-I", str(cls.root),
            "-L", str(cls.root), "-lTabTypeKit", "-Xlinker", "-rpath", "-Xlinker", str(cls.root),
            str(ROOT / "Sources/TabType/Settings/AppPreferences.swift"), str(harness),
            "-o", str(cls.executable)
        ], check=True, capture_output=True, text=True, timeout=60)

    def setUp(self):
        self.fixture = Path(tempfile.mkdtemp(prefix="fixture-", dir=self.root))
        self.home = self.fixture / "synthetic-home"
        self.home.mkdir(mode=0o700)
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(("KEYWEAVE_", "TABTYPE_"))}
        self.environment["KEYWEAVE_TEST_HOME"] = str(self.home)
        # Foundation standardizes home aliases; ask the real pure function.
        self.domain = subprocess.run([str(self.executable), "domain"], env=self.environment,
                                     capture_output=True, text=True, check=True, timeout=15).stdout.strip()
        self.assertRegex(self.domain, r"^dev\.anuhas\.keyweave\.test\.[a-f0-9]{64}$")
        self.sibling = self.domain + ".sibling"
        self.addCleanup(self.remove_domains)
        self.app = self.fixture / "PreferencesProbe.app"
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        self.binary = contents / "MacOS/PreferencesProbe"
        shutil.copy2(self.executable, self.binary)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": self.domain,
            "CFBundleExecutable": "PreferencesProbe",
            "CFBundlePackageType": "APPL"
        }))
        # Seed through the same synthetic app's ordinary defaults initializer.
        self.assert_probe("seed")
        self.preference_files = {
            name: Path.home() / "Library/Preferences" / (name + ".plist")
            for name in (self.domain, self.sibling)
        }
        self.before = {name: path.read_bytes() for name, path in self.preference_files.items()}

    def remove_domains(self):
        for domain in (self.domain, self.sibling):
            subprocess.run(["/usr/bin/defaults", "delete", domain],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)

    def assert_probe(self, mode):
        def no_core_dump():
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        result = subprocess.run([str(self.binary), mode], env=self.environment,
                                capture_output=True, text=True, timeout=15,
                                preexec_fn=no_core_dump)
        self.assertEqual(result.returncode, 0,
                         f"{mode} exited {result.returncode}\n{result.stdout}\n{result.stderr[:5000]}")
        return result

    def test_matching_bundle_constructor_and_getters_preserve_existing_bytes(self):
        self.assert_probe("read")
        self.assertEqual({name: path.read_bytes() for name, path in self.preference_files.items()},
                         self.before)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_matching_bundle_writes_and_removal_use_only_explicit_domain(self):
        self.assert_probe("write")
        # cfprefsd can flush its plist asynchronously even after synchronize().
        # A fresh process proves persistence without mistaking that lag for loss.
        current = plistlib.loads(base64.b64decode(self.assert_probe("dump").stdout.strip()))
        self.assertEqual(current["newValue"], "only explicit domain")
        self.assertNotIn("text", current)
        self.assertEqual(self.preference_files[self.sibling].read_bytes(), self.before[self.sibling])
        self.assertEqual(list(self.home.iterdir()), [])


if __name__ == "__main__":
    unittest.main()

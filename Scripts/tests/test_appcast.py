import base64
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIGNATURE = base64.b64encode(bytes(64)).decode()


def feed(url="https://github.com/DevAnuhas/keyweave/releases/download/v2.4.0/KeyWeave-2.4.0-arm64.dmg"):
    body = f'''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>KeyWeave</title><item><title>KeyWeave 2.4.0</title><sparkle:version>17</sparkle:version><sparkle:shortVersionString>2.4.0</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="{url}" length="12345" type="application/octet-stream" sparkle:edSignature="{SIGNATURE}" /></item></channel></rss>'''
    return body + f'''<!-- sparkle-signatures:
edSignature: {SIGNATURE}
length: {len(body.encode())}
-->'''


class AppcastTests(unittest.TestCase):
    def validate(self, data):
        with tempfile.TemporaryDirectory(prefix="keyweave-appcast-tests-") as d:
            path = Path(d) / "feed.xml"
            path.write_text(data)
            return subprocess.run([sys.executable, str(ROOT / "Scripts/appcast.py"), "--validate-feed", str(path)],
                                  capture_output=True, text=True)

    def test_stable_fork_release_passes_metadata_validation(self):
        result = self.validate(feed())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 release", result.stdout)

    def test_upstream_or_mismatched_assets_are_rejected(self):
        for url in [
            "https://github.com/nilava/TabType/releases/download/v2.4.0/TabType.dmg",
            "https://github.com/DevAnuhas/keyweave/releases/download/v2.3.0/KeyWeave-2.3.0-arm64.dmg",
            "http://github.com/DevAnuhas/keyweave/releases/download/v2.4.0/KeyWeave-2.4.0-arm64.dmg",
            "https://github.com/DevAnuhas/keyweave/releases/download/v2.4.0/KeyWeave-2.4.0-arm64.dmg?redirect=1",
        ]:
            with self.subTest(url=url):
                result = self.validate(feed(url))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("matching KeyWeave release DMG", result.stderr)

    def test_unsigned_truncated_or_modified_metadata_is_rejected(self):
        for data in [feed().split("<!-- sparkle-signatures:")[0],
                     feed().replace("length: ", "length: 9"),
                     feed() + "unsigned trailing bytes"]:
            with self.subTest(data=data[-80:]):
                self.assertNotEqual(self.validate(data).returncode, 0)

    def test_wrong_identity_leaves_previous_feed_untouched(self):
        import plistlib
        with tempfile.TemporaryDirectory(prefix="keyweave-appcast-tests-") as d:
            root = Path(d)
            app = root / "Other.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "app.tabtype.TabType"}))
            output = root / "appcast.xml"
            output.write_bytes(b"previous feed sentinel")
            result = subprocess.run([sys.executable, str(ROOT / "Scripts/appcast.py"),
                                     "--app", str(app), "--output", str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unexpected application identity", result.stderr)
            self.assertEqual(output.read_bytes(), b"previous feed sentinel")


if __name__ == "__main__":
    unittest.main()

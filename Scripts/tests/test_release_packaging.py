"""Synthetic command-boundary regressions; never signs, mounts or contacts Apple."""
import json
import os
from pathlib import Path
import plistlib
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class ReleasePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="keyweaver-release-test-")
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        (self.root / "Scripts").mkdir()
        (self.root / "bin").mkdir()
        self.calls = self.root / "calls"
        self.environment = {**os.environ, "PATH": str(self.root / "bin") + ":/usr/bin:/bin",
                            "SIGN_IDENTITY": "", "DEVELOPMENT_TEAM": "", "KEYCHAIN_PROFILE": "",
                            "RELEASE": "0", "DMGBUILD_VENV": "", "DMG_WHEELHOUSE": "",
                            "PYTHONDONTWRITEBYTECODE": "1", "KEYWEAVE_TEST_CALLS": str(self.calls)}
        for name in ["xcrun", "codesign", "security", "hdiutil", "swift"]:
            self.tool(name, '#!/bin/bash\nprintf "%s\\n" "$0 $*" >> "$KEYWEAVE_TEST_CALLS"\nexit 91\n')

    def tearDown(self):
        self.temporary.cleanup()

    def tool(self, name, source):
        path = self.root / "bin" / name
        path.write_text(source)
        path.chmod(0o755)

    def script(self, name):
        destination = self.root / "Scripts" / name
        shutil.copyfile(ROOT / "Scripts" / name, destination)
        return destination

    def run_script(self, name, environment=None):
        return subprocess.run(["/bin/bash", str(self.script(name))], cwd=self.root,
                              env={**self.environment, **(environment or {})}, capture_output=True, text=True)

    def test_release_build_without_identity_refuses_before_tools_or_output(self):
        result = self.run_script("build.sh", {"RELEASE": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires SIGN_IDENTITY", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.root / "dist").exists())

    def test_ad_hoc_identity_cannot_be_used_for_release(self):
        result = self.run_script("build.sh", {"RELEASE": "1", "SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "AAAAAAAAAA"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Developer ID", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_development_certificate_is_rejected_before_build(self):
        self.tool("security", '#!/bin/bash\necho \'1) 1111111111111111111111111111111111111111 "Apple Development: Synthetic (AAAAAAAAAA)"\'\n')
        result = self.run_script("build.sh", {"RELEASE": "1", "SIGN_IDENTITY": "1111111111111111111111111111111111111111", "DEVELOPMENT_TEAM": "AAAAAAAAAA"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Developer ID Application", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.root / "dist").exists())

    def test_orchestrator_without_identity_never_invokes_distribution_tools(self):
        result = self.run_script("release.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release requires SIGN_IDENTITY", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_release_signs_framework_before_app_with_runtime_and_timestamp(self):
        resources = self.root / "Resources"
        resources.mkdir()
        (resources / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.anuhas.keyweave", "CFBundleExecutable": "KeyWeaver"
        }))
        (resources / "TabType.entitlements").write_bytes(plistlib.dumps({}))
        (self.root / "LICENSE").write_text("Synthetic MIT notice")
        self.tool("security", '#!/bin/bash\necho \'1) 1111111111111111111111111111111111111111 "Developer ID Application: Synthetic (AAAAAAAAAA)"\'\n')
        self.tool("xcrun", '''#!/bin/bash
derived=""
while [ "$#" -gt 0 ]; do
    case "$1" in -derivedDataPath) derived="$2"; shift ;; esac
    shift
done
products="$derived/Build/Products/Release"
mkdir -p "$products/llama.framework"
printf 'synthetic executable' > "$products/TabType"
printf 'synthetic framework' > "$products/llama.framework/llama"
''')
        self.tool("otool", '#!/bin/bash\necho "path @executable_path/../Frameworks"\n')
        self.tool("lipo", '#!/bin/bash\nexit 0\n')
        self.tool("codesign", f'''#!{sys.executable}
import json,os,sys
with open(os.environ["KEYWEAVE_TEST_CALLS"],"a") as stream:stream.write(json.dumps(sys.argv[1:])+"\\n")
if sys.argv[1]=="-d":
 print("CodeDirectory flags=0x10000(runtime)")
 print("Timestamp=synthetic timestamp")
''')
        result = self.run_script("build.sh", {"RELEASE": "1", "SIGN_IDENTITY": "1111111111111111111111111111111111111111", "DEVELOPMENT_TEAM": "AAAAAAAAAA"})
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        signs = [arguments for arguments in calls if arguments[0] == "--force"]
        self.assertEqual(len(signs), 2)
        self.assertTrue(signs[0][-1].endswith("/Contents/Frameworks/llama.framework"))
        self.assertTrue(signs[1][-1].endswith("/KeyWeaver.app"))
        for arguments in signs:
            self.assertIn("--timestamp", arguments)
            self.assertIn("--options", arguments)
            self.assertIn("runtime", arguments)
            self.assertNotIn("--deep", arguments)
        self.assertNotIn("--entitlements", signs[0])
        self.assertIn("--entitlements", signs[1])
        self.assertTrue((self.root / "dist/KeyWeaver.app/Contents/MacOS/KeyWeaver").is_file())

    def test_notary_without_profile_never_invokes_platform_tools(self):
        result = subprocess.run(["python3", str(self.script("notarize.py")), "app", str(self.root / "KeyWeaver.app")],
                                env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("KEYCHAIN_PROFILE", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_resume_rejects_changed_signature_before_notary_network(self):
        artifact = self.root / "release.dmg"
        artifact.write_bytes(b"synthetic disk image, never mount")
        receipt = self.root.parent / "private-receipt"
        receipt.mkdir()
        (receipt / "artifact.json").write_text(json.dumps({"kind": "dmg", "cdhash": "a" * 40}))
        (receipt / "submission-id.txt").write_text("11111111-2222-3333-4444-555555555555\n")
        self.tool("codesign", '#!/bin/bash\ncase "$1" in -d) echo "CDHash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; echo "Timestamp=synthetic timestamp" ;; esac\n')
        result = subprocess.run(["python3", str(self.script("notarize.py")), "dmg", str(artifact), "--resume", str(receipt)],
                                env={**self.environment, "KEYCHAIN_PROFILE": "synthetic", "DEVELOPMENT_TEAM": "AAAAAAAAAA"},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from the submitted code signature", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertEqual(artifact.read_bytes(), b"synthetic disk image, never mount")

    def test_ambiguous_existing_receipt_cannot_trigger_a_new_upload(self):
        artifact = self.root / "release.dmg"
        artifact.write_bytes(b"synthetic disk image, never mount")
        parent = self.root.parent / "receipts"
        receipt = parent / ("dmg-" + "b" * 40)
        receipt.mkdir(parents=True)
        (receipt / "upload-attempted.txt").write_text("Prior response was uncertain; inspect history.\n")
        self.tool("codesign", '#!/bin/bash\ncase "$1" in -d) echo "CDHash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; echo "Timestamp=synthetic timestamp" ;; esac\n')
        result = subprocess.run(["python3", str(self.script("notarize.py")), "dmg", str(artifact)],
                                env={**self.environment, "KEYCHAIN_PROFILE": "synthetic", "DEVELOPMENT_TEAM": "AAAAAAAAAA", "NOTARY_RECEIPTS_DIR": str(parent)},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Receipt already exists", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertEqual(artifact.read_bytes(), b"synthetic disk image, never mount")

    def test_dmgbuild_layout_matches_the_station_creation_method(self):
        app = self.root / "KeyWeaver.app"
        resources = self.root / "artwork"
        license_file = self.root / "LICENSE"
        settings = runpy.run_path(str(ROOT / "packaging/dmg/settings.py"), init_globals={
            "defines": {"app": str(app), "resources": str(resources), "license": str(license_file)}
        })
        self.assertEqual(settings["files"], [(str(app), "KeyWeaver.app"), (str(license_file), "License.txt")])
        self.assertEqual(settings["symlinks"], {"Applications": "/Applications"})
        self.assertEqual(settings["filesystem"], "HFS+")
        self.assertEqual(settings["format"], "UDZO")
        self.assertEqual(settings["icon"], str(app / "Contents/Resources/AppIcon.icns"))
        self.assertEqual(settings["background"], str(resources / "background.png"))
        self.assertEqual(settings["window_rect"], ((180, 180), (600, 500)))
        self.assertEqual(settings["icon_locations"], {"KeyWeaver.app": (150, 180), "Applications": (450, 180), "License.txt": (520, 320)})
        self.assertEqual(settings["icon_size"], 80)
        self.assertEqual(settings["text_size"], 13)
        self.assertFalse(settings["show_status_bar"])
        self.assertFalse(settings["show_toolbar"])
        self.assertNotIn("hide_extensions", settings, "Never apply FinderInfo extension flags to the signed app")

    def test_dmgbuild_dependencies_match_the_station_hash_pins(self):
        lines = [line for line in (ROOT / "packaging/dmg/requirements.txt").read_text().splitlines()
                 if line and not line.startswith("#")]
        self.assertEqual(lines, [
            "dmgbuild==1.6.7 --hash=sha256:37ee5771c377beb3203d9164aae8046ffed8531c06edf9227f5788b3c599b1bf",
            "ds-store==1.3.3 --hash=sha256:b92a371efbf1b4ccce2a04d1ed13fceacc4736c81ba09cf5aefb74c088160a35",
            "mac-alias==2.2.3 --hash=sha256:7362b521d2132ef92f606a37abfed5fcd849ceb2f28b6f9743e014b02af92f0d",
        ])

    def test_dmg_tool_setup_uses_an_owned_hash_pinned_offline_environment(self):
        requirements = self.root / "packaging/dmg"
        requirements.mkdir(parents=True)
        shutil.copyfile(ROOT / "packaging/dmg/requirements.txt", requirements / "requirements.txt")
        wheels = self.root / "wheels"
        wheels.mkdir()
        self.tool("uname", '#!/bin/bash\necho Darwin\n')
        self.tool("python3", f'''#!{sys.executable}
import json,os,pathlib,shutil,sys
args=sys.argv[1:]
with open(os.environ["KEYWEAVE_TEST_CALLS"],"a") as stream:stream.write(json.dumps(args)+"\\n")
if args[:2]==["-m","venv"]:
 target=pathlib.Path(args[2])/"bin";target.mkdir(parents=True)
 shutil.copyfile(sys.argv[0],target/"python3");(target/"python3").chmod(0o755)
''')
        result = self.run_script("setup-dmg.sh", {"DMG_WHEELHOUSE": str(wheels)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        creates = [args for args in calls if args[:2] == ["-m", "venv"]]
        self.assertEqual(len(creates), 1)
        self.assertEqual(Path(creates[0][2]).relative_to(self.root.resolve()), Path(".build-keyweave/tools/dmgbuild"))
        installs = [args for args in calls if args[:3] == ["-m", "pip", "install"]]
        self.assertEqual(len(installs), 1)
        for flag in ["--require-hashes", "--only-binary=:all:", "--no-index", "--find-links"]:
            self.assertIn(flag, installs[0])
        self.assertEqual(installs[0][installs[0].index("--find-links") + 1], str(wheels))
        checks = [args[1] for args in calls if args and args[0] == "-c" and "importlib.metadata" in args[1]]
        self.assertEqual(len(checks), 1)
        for value in ["dmgbuild", "1.6.7", "ds-store", "1.3.3", "mac-alias", "2.2.3"]:
            self.assertIn(value, checks[0])

    def make_dmg_fixture(self):
        app = self.root / "dist/KeyWeaver.app"
        for relative in ["Contents/MacOS", "Contents/Resources", "Contents/_CodeSignature"]:
            (app / relative).mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.anuhas.keyweave", "CFBundleExecutable": "KeyWeaver",
            "CFBundleShortVersionString": "2.2.0"
        }))
        (app / "Contents/MacOS/KeyWeaver").write_bytes(b"synthetic signed executable")
        (app / "Contents/Resources/AppIcon.icns").write_bytes(b"synthetic volume icon")
        (app / "Contents/_CodeSignature/CodeResources").write_bytes(b"synthetic resource seal")
        (self.root / "LICENSE").write_bytes(b"synthetic MIT license")
        resources = self.root / "packaging/dmg"
        resources.mkdir(parents=True)
        shutil.copyfile(ROOT / "packaging/dmg/settings.py", resources / "settings.py")
        for name, width, height in [("background.png", 600, 400), ("background@2x.png", 1200, 800)]:
            (resources / name).write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + width.to_bytes(4, "big") + height.to_bytes(4, "big"))
        venv = self.root / ".build-keyweave/tools/dmgbuild/bin"
        venv.mkdir(parents=True)
        probe = f'''#!{sys.executable}
import json,os,pathlib,shutil,sys
args=sys.argv[1:]
name=pathlib.Path(sys.argv[0]).name
with open(os.environ["KEYWEAVE_TEST_CALLS"],"a") as stream:stream.write(json.dumps({{"tool":name,"args":args}})+"\\n")
'''
        def write_probe(path, body):
            path.write_text(probe + body)
            path.chmod(0o755)
        for name in ["codesign", "xcrun", "spctl", "lipo"]:
            write_probe(self.root / "bin" / name, 'if args and args[0]=="-d":print("Timestamp=synthetic timestamp")\n')
        write_probe(venv / "python3", '''if args and args[0]=="-c":
 sys.exit(0)
os.execv(sys.executable,[sys.executable]+args)
''')
        write_probe(venv / "dmgbuild", '''values={}
for index,value in enumerate(args):
 if value=="-D":
  key,item=args[index+1].split("=",1);values[key]=item
payload=pathlib.Path(os.environ["KEYWEAVE_TEST_PAYLOAD"])
payload.mkdir()
shutil.copytree(values["app"],payload/"KeyWeaver.app")
shutil.copyfile(values["license"],payload/"License.txt")
(payload/"Applications").symlink_to("/Applications")
pathlib.Path(args[-1]).write_bytes(b"synthetic dmgbuild image")
pathlib.Path(os.environ["KEYWEAVE_TEST_STATE"]).write_text(json.dumps({"image":args[-1],"attached":False}))
''')
        write_probe(self.root / "bin/hdiutil", '''state_path=pathlib.Path(os.environ["KEYWEAVE_TEST_STATE"])
state=json.loads(state_path.read_text()) if state_path.exists() else {}
if args[0]=="create":sys.exit(89)
if args[0]=="attach":
 mount=pathlib.Path(args[args.index("-mountpoint")+1])
 shutil.copytree(os.environ["KEYWEAVE_TEST_PAYLOAD"],mount,dirs_exist_ok=True,symlinks=True)
 state["image"]=next(value for value in args if value.endswith(".dmg"))
 state["attached"]=True;state_path.write_text(json.dumps(state))
elif args[0]=="info":
 import plistlib
 images=[{"image-path":"/unrelated/synthetic.dmg","system-entities":[{"dev-entry":"/dev/disk888"}]}]
 if state.get("attached"):images.append({"image-path":state["image"],"system-entities":[{"dev-entry":"/dev/disk999"}]})
 sys.stdout.buffer.write(plistlib.dumps({"images":images}))
elif args[0]=="detach":
 if args[1]=="/dev/disk888":sys.exit(90)
 state["attached"]=False;state_path.write_text(json.dumps(state))
''')
        environment = {"SIGN_IDENTITY": "1111111111111111111111111111111111111111", "DEVELOPMENT_TEAM": "AAAAAAAAAA",
                       "KEYWEAVE_TEST_PAYLOAD": str(self.root / "payload"), "KEYWEAVE_TEST_STATE": str(self.root / "state.json")}
        return app, environment

    def test_package_uses_dmgbuild_without_mutating_app_or_detaching_other_images(self):
        app, environment = self.make_dmg_fixture()
        before = {str(path.relative_to(app)): path.read_bytes() for path in app.rglob("*") if path.is_file()}
        result = self.run_script("package.sh", environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual({str(path.relative_to(app)): path.read_bytes() for path in app.rglob("*") if path.is_file()}, before)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        builds = [call["args"] for call in calls if call["tool"] == "dmgbuild"]
        self.assertEqual(len(builds), 1)
        self.assertIn("-s", builds[0])
        self.assertTrue(builds[0][builds[0].index("-s") + 1].endswith("/packaging/dmg/settings.py"))
        self.assertTrue(any(value.endswith("/packaging/dmg") and value.startswith("resources=") for value in builds[0]))
        self.assertFalse(any(call["tool"] == "hdiutil" and call["args"][0] == "create" for call in calls))
        detaches = [call["args"][1] for call in calls if call["tool"] == "hdiutil" and call["args"][0] == "detach"]
        self.assertIn("/dev/disk999", detaches)
        self.assertNotIn("/dev/disk888", detaches)
        self.assertEqual((self.root / "dist/KeyWeaver-2.2.0-arm64.dmg").read_bytes(), b"synthetic dmgbuild image")
        self.assertFalse((self.root / "dist/KeyWeaver-2.2.0-arm64.dmg.lock").exists())

    def test_existing_dmg_is_never_overwritten(self):
        _, environment = self.make_dmg_fixture()
        image = self.root / "dist/KeyWeaver-2.2.0-arm64.dmg"
        image.write_bytes(b"existing accepted image")
        result = self.run_script("package.sh", environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(image.read_bytes(), b"existing accepted image")
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        self.assertFalse(any(call["tool"] == "dmgbuild" for call in calls))

    def test_final_verification_mounts_only_a_private_copy_and_detaches_it(self):
        app, environment = self.make_dmg_fixture()
        image = self.root / "dist/KeyWeaver-2.2.0-arm64.dmg"
        image.write_bytes(b"synthetic accepted image")
        archive = self.root / "dist/KeyWeaver-2.2.0-arm64.zip"
        with zipfile.ZipFile(archive, "w") as packaged:
            for path in app.rglob("*"):
                if path.is_file(): packaged.write(path, str(path.relative_to(app.parent)))
            packaged.write(self.root / "LICENSE", "LICENSE")
        payload = Path(environment["KEYWEAVE_TEST_PAYLOAD"])
        payload.mkdir()
        shutil.copytree(app, payload / "KeyWeaver.app")
        shutil.copyfile(self.root / "LICENSE", payload / "License.txt")
        (payload / "Applications").symlink_to("/Applications")
        script = self.script("package.sh")
        result = subprocess.run(["/bin/bash", str(script), "--verify"], cwd=self.root,
                                env={**self.environment, **environment}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        attaches = [call["args"] for call in calls if call["tool"] == "hdiutil" and call["args"][0] == "attach"]
        self.assertEqual(len(attaches), 1)
        attached_image = next(value for value in attaches[0] if value.endswith(".dmg"))
        self.assertNotEqual(Path(attached_image), image)
        self.assertIn(".KeyWeaver-package.", attached_image)
        self.assertFalse(json.loads(Path(environment["KEYWEAVE_TEST_STATE"]).read_text())["attached"])
        self.assertEqual(image.read_bytes(), b"synthetic accepted image")
        self.assertEqual(len((self.root / "dist/SHA256SUMS.txt").read_text().splitlines()), 2)
        self.assertEqual(list((self.root / "dist").glob(".KeyWeaver-package.*")), [])


if __name__ == "__main__":
    unittest.main()

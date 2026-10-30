#!/usr/bin/env python3
"""Generate a signed KeyWeave feed from the final notarized DMG; never publish it."""
import argparse
import base64
import datetime
from email.utils import format_datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
FEED = "https://raw.githubusercontent.com/DevAnuhas/keyweave/main/Updates/appcast.xml"
KEY = "pc1gLnpongI0flX6p0FOVK509djxXgyrKN8rcMB4bRU="
ACCOUNT = "dev.anuhas.keyweave.sparkle"


def require(value, message):
    if not value:
        raise ValueError(message)


def signature_bytes(value):
    require(len(base64.b64decode(value, validate=True)) == 64, "Invalid EdDSA signature length")


def validate_feed(data, allow_empty=False):
    """Metadata guard only. Sparkle's sign_update verifies the cryptography."""
    marker = re.search(rb'<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s+length: (\d+)\s*-->\s*$', data)
    require(marker is not None, "Missing signed-feed metadata")
    signature_bytes(marker[1])
    require(int(marker[2]) == marker.start(), "Signed-feed byte length differs")
    root = ET.fromstring(data)
    require(root.tag == "rss", "Expected an RSS appcast")
    items = root.findall("channel/item")
    require(items or allow_empty, "No releases in feed")
    builds = set()
    releases = []
    for item in items:
        version = item.findtext(NS + "shortVersionString", "")
        build = item.findtext(NS + "version", "")
        require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "Only stable release versions are allowed")
        require(build.isdecimal() and int(build) > 0 and build not in builds, "Invalid or duplicate build number")
        builds.add(build)
        require(item.find(NS + "channel") is None, "Prerelease channels are not published here")
        require(item.find(NS + "deltas") is None, "Delta assets need a separate publication policy")
        enclosures = item.findall("enclosure")
        require(len(enclosures) == 1, "Expected one full update enclosure")
        enclosure = enclosures[0]
        expected = f"https://github.com/DevAnuhas/keyweave/releases/download/v{version}/KeyWeave-{version}-arm64.dmg"
        require(enclosure.get("url") == expected, "Update archive must be the matching KeyWeave release DMG")
        require(enclosure.get("length", "").isdecimal() and int(enclosure.get("length")) > 0, "Invalid archive byte length")
        signature_bytes(enclosure.get(NS + "edSignature", ""))
        minimum = item.findtext(NS + "minimumSystemVersion", "")
        require(re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum) and int(minimum.split('.')[0]) >= 14, "Missing supported macOS requirement")
        hardware = item.findtext(NS + "hardwareRequirements")
        require(hardware in (None, "arm64"), "Unexpected update architecture")
        releases.append({"version": version, "build": build, "url": expected,
                         "signature": enclosure.get(NS + "edSignature"), "length": int(enclosure.get("length"))})
    return releases


def run(arguments):
    result = subprocess.run([str(x) for x in arguments], capture_output=True, text=True)
    require(result.returncode == 0, f"{Path(arguments[0]).name} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def generate(args):
    sys.dont_write_bytecode = True
    from notarize import signature
    app = args.app
    require(app is not None and app.is_dir() and not app.is_symlink(), "Expected a regular app bundle")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "dev.anuhas.keyweave" and info.get("CFBundleExecutable") == "KeyWeave", "Unexpected application identity")
    require(info.get("SUFeedURL") == FEED and info.get("SUPublicEDKey") == KEY
            and info.get("SURequireSignedFeed") is True and info.get("SUVerifyUpdateBeforeExtraction") is True,
            "App is missing pinned update trust")
    version, build = info.get("CFBundleShortVersionString", ""), info.get("CFBundleVersion", "")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) and build.isdecimal() and int(build) > 0, "Invalid release version/build")
    archive = args.archive
    require(archive is not None and archive.is_file() and not archive.is_symlink()
            and archive.name == f"KeyWeave-{version}-arm64.dmg", "Expected the final matching DMG")
    output = args.output
    require(not output.is_symlink() and not output.parent.is_symlink(), "Refusing a symlink output")
    team = os.environ.get("DEVELOPMENT_TEAM", "")
    require(re.fullmatch(r"[A-Z0-9]{10}", team), "DEVELOPMENT_TEAM is required")
    tools = Path(os.environ.get("SPARKLE_BIN_DIR", ROOT / ".build-keyweave/source-packages/artifacts/keyweave/Sparkle/bin"))
    if not tools.is_dir() and "SPARKLE_BIN_DIR" not in os.environ:
        tools = ROOT / ".build/artifacts/keyweave/Sparkle/bin"
    for name in ["generate_keys", "sign_update"]:
        require((tools / name).is_file(), "Build the pinned Sparkle dependency first")
    require(run([tools / "generate_keys", "--account", ACCOUNT, "-p"]) == KEY, "Signing key differs from the app public key")
    signature(app, "app", team)
    signature(archive, "dmg", team)
    for artifact in [app, archive]:
        run(["xcrun", "stapler", "validate", artifact])
    if output.exists():
        previous = validate_feed(output.read_bytes(), allow_empty=True)
        require(int(build) > max((int(item["build"]) for item in previous), default=0), "Build must increase beyond the published feed")
        run([tools / "sign_update", "--account", ACCOUNT, "--verify", output])
    # Use the existing packaging verifier to prove the final DMG/ZIP contain
    # this exact accepted app, before signing metadata derived from its plist.
    require(app.resolve() == ROOT / "dist/KeyWeave.app"
            and archive.resolve() == ROOT / "dist" / archive.name,
            "Feed generation requires the verified dist app and archive")
    run(["/bin/bash", ROOT / "Scripts/package.sh", "--verify"])
    archive_signature = run([tools / "sign_update", "--account", ACCOUNT, "-p", archive])
    signature_bytes(archive_signature)
    ET.register_namespace("sparkle", NS[1:-1])
    if output.exists():
        root = ET.fromstring(output.read_bytes())
        channel = root.find("channel")
    else:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "KeyWeave Updates"
        ET.SubElement(channel, "link").text = "https://github.com/DevAnuhas/keyweave"
        ET.SubElement(channel, "description").text = "Signed KeyWeave updates"
    require(channel is not None, "Missing feed channel")
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"KeyWeave {version}"
    ET.SubElement(item, "link").text = f"https://github.com/DevAnuhas/keyweave/releases/tag/v{version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.datetime.now(datetime.timezone.utc), usegmt=True)
    if args.notes:
        require(args.notes.is_file(), "Release notes file is missing")
        ET.SubElement(item, "description").text = args.notes.read_text(encoding="utf-8")
    for name, value in [("version", build), ("shortVersionString", version),
                        ("minimumSystemVersion", info.get("LSMinimumSystemVersion", "14.0")),
                        ("hardwareRequirements", "arm64")]:
        ET.SubElement(item, NS + name).text = value
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/DevAnuhas/keyweave/releases/download/v{version}/{archive.name}",
        "length": str(archive.stat().st_size), "type": "application/octet-stream",
        NS + "edSignature": archive_signature})
    items = [item, *channel.findall("item")]
    for previous_item in channel.findall("item"):
        channel.remove(previous_item)
    channel.extend(sorted(items, key=lambda entry: int(entry.findtext(NS + "version")), reverse=True)[:10])
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".appcast-", dir=output.parent) as directory:
        candidate = Path(directory) / "appcast.xml"
        candidate.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
        run([tools / "sign_update", "--account", ACCOUNT, candidate])
        releases = validate_feed(candidate.read_bytes())
        current = [entry for entry in releases if entry["build"] == build and entry["version"] == version]
        require(len(current) == 1, "Generated feed does not describe the built application")
        require(current[0]["length"] == archive.stat().st_size, "Feed length differs from the final archive")
        run([tools / "sign_update", "--account", ACCOUNT, "--verify", candidate])
        run([tools / "sign_update", "--account", ACCOUNT, "--verify", archive, current[0]["signature"]])
        candidate.chmod(0o644)
        os.replace(candidate, output)
    print(f"Signed and verified: {output}. Publish the release assets before the feed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-feed", type=Path, help="Validate feed metadata only; no keychain or platform operations")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "Updates/appcast.xml")
    args = parser.parse_args()
    if args.validate_feed:
        releases = validate_feed(args.validate_feed.read_bytes(), allow_empty=True)
        print(f"Metadata valid ({len(releases)} release(s)); signature cryptography is verified by Sparkle.")
    else:
        generate(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, ET.ParseError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)

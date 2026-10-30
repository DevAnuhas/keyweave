#!/usr/bin/env python3
"""Submit once, preserve private receipts, and staple only Apple's Accepted build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def run(arguments, directory=None, label=None, check=True):
    result = subprocess.run([str(value) for value in arguments], capture_output=True, text=True)
    if directory is not None and label is not None:
        (directory / (label + ".stdout")).write_text(result.stdout)
        (directory / (label + ".stderr")).write_text(result.stderr)
    if check and result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode}); inspect private receipts")
    return result


def signature(path, kind, team):
    identifier = "dev.anuhas.keyweave" + (".dmg" if kind == "dmg" else "")
    requirement = (f'=anchor apple generic and identifier "{identifier}" and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists and '
                   f'certificate leaf[subject.OU] = "{team}"')
    command = ["codesign", "--verify", "--strict", "--test-requirement", requirement]
    if kind == "app":
        command.append("--deep")
    run(command + [path])
    result = run(["codesign", "-d", "--verbose=4", path])
    text = result.stdout + result.stderr
    match = re.search(r"^CDHash=([0-9a-fA-F]{40})$", text, re.M)
    if not match or not re.search(r"^Timestamp=", text, re.M):
        raise RuntimeError("Missing code-directory hash or secure timestamp")
    if kind == "app" and not re.search(r"flags=.*runtime", text):
        raise RuntimeError("Hardened Runtime is missing")
    return match[1].lower(), text


def outside_repository(path):
    if path.resolve().is_relative_to(ROOT):
        raise RuntimeError("Notary receipts must stay outside the public repository")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["app", "dmg"])
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--resume", type=Path, help="Existing receipt; never uploads again")
    args = parser.parse_args()
    profile = os.environ.get("KEYCHAIN_PROFILE", "")
    team = os.environ.get("DEVELOPMENT_TEAM", "")
    timeout = os.environ.get("NOTARY_TIMEOUT", "55s")
    if not profile:
        raise RuntimeError("KEYCHAIN_PROFILE must name existing credentials; do not pass secrets")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise RuntimeError("DEVELOPMENT_TEAM must name the expected ten-character team")
    if not re.fullmatch(r"[1-9][0-9]*[smh]?", timeout):
        raise RuntimeError("NOTARY_TIMEOUT must be a positive duration such as 55s or 5m")
    if args.artifact.is_symlink() or not args.artifact.exists():
        raise RuntimeError("Expected an existing artifact, not a symlink")
    artifact = args.artifact.resolve()
    if args.kind == "app":
        if not artifact.is_dir() or artifact.suffix != ".app":
            raise RuntimeError("Expected an .app directory")
        with (artifact / "Contents/Info.plist").open("rb") as stream:
            plist = plistlib.load(stream)
        if plist.get("CFBundleIdentifier") != "dev.anuhas.keyweave" or plist.get("CFBundleExecutable") != "KeyWeaver":
            raise RuntimeError("Unexpected application identity")
        version = plist.get("CFBundleShortVersionString", "")
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
            raise RuntimeError("Unexpected application version")
    elif not artifact.is_file() or artifact.suffix != ".dmg":
        raise RuntimeError("Expected a regular .dmg file")
    cdhash, details = signature(artifact, args.kind, team)
    parent = Path(os.environ.get("NOTARY_RECEIPTS_DIR", str(Path.home() / "Library/Application Support/KeyWeaverReleaseReceipts")))
    outside_repository(parent)
    if args.resume:
        if args.resume.is_symlink() or not args.resume.is_dir():
            raise RuntimeError("Resume receipt is missing or is a symlink")
        receipt = args.resume.resolve()
        outside_repository(receipt)
        metadata = json.loads((receipt / "artifact.json").read_text())
        if metadata["kind"] != args.kind or metadata["cdhash"] != cdhash:
            raise RuntimeError("Artifact differs from the submitted code signature; do not resubmit")
        submission = (receipt / "submission-id.txt").read_text().strip()
    else:
        parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        receipt = parent / (args.kind + "-" + cdhash)
        try:
            receipt.mkdir(mode=0o700)
        except FileExistsError:
            raise RuntimeError(f"Receipt already exists: {receipt}. Inspect it and use --resume; do not resubmit")
        os.chmod(receipt, 0o700)
        metadata = {"kind": args.kind, "cdhash": cdhash, "artifact": str(artifact)}
        (receipt / "signature.txt").write_text(details)
        upload = receipt / ("submission.zip" if args.kind == "app" else "submission.dmg")
        if args.kind == "app":
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", artifact, upload], receipt, "archive")
        else:
            shutil.copy2(artifact, upload)
            run(["hdiutil", "verify", upload], receipt, "image-before")
        metadata["submission_sha256"] = digest(upload)
        (receipt / "artifact.json").write_text(json.dumps(metadata, indent=2) + "\n")
        (receipt / "upload-attempted.txt").write_text("Upload attempted once. Inspect history if no submission ID was received.\n")
        print(f"Submitting once. Private receipts: {receipt}", flush=True)
        result = run(["xcrun", "notarytool", "submit", upload, "--keychain-profile", profile,
                      "--no-wait", "--output-format", "json", "--no-progress"], receipt, "submit", check=False)
        try:
            submission = json.loads(result.stdout).get("id", "")
        except json.JSONDecodeError:
            submission = ""
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", submission):
            raise RuntimeError(f"Upload returned no submission ID (exit {result.returncode}); inspect {receipt} and account history before retrying")
        (receipt / "submission-id.txt").write_text(submission + "\n")
        if result.returncode:
            raise RuntimeError(f"Upload failed after receiving an ID. Resume {receipt}; never resubmit")
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", submission):
        raise RuntimeError("Invalid submission ID in receipt")
    upload = receipt / ("submission.zip" if args.kind == "app" else "submission.dmg")
    if digest(upload) != metadata["submission_sha256"]:
        raise RuntimeError("Preserved submission differs from its recorded hash")
    initial_hash = digest(artifact) if args.kind == "dmg" else None
    if args.kind == "dmg":
        acceptable = [metadata["submission_sha256"], metadata.get("stapled_sha256")]
        if initial_hash not in acceptable:
            raise RuntimeError("DMG differs from both the submitted and recorded stapled image")
    attempt = Path(tempfile.mkdtemp(prefix="check-", dir=receipt))
    print(f"Waiting up to {timeout} for {submission}. Receipts: {receipt}", flush=True)
    run(["xcrun", "notarytool", "wait", submission, "--keychain-profile", profile,
         "--timeout", timeout, "--output-format", "json", "--no-progress"], attempt, "wait", check=False)
    result = run(["xcrun", "notarytool", "info", submission, "--keychain-profile", profile,
                  "--output-format", "json"], attempt, "info")
    info = json.loads(result.stdout)
    if info.get("id") != submission:
        raise RuntimeError("Notary status returned an unexpected submission ID")
    status = info.get("status")
    if status not in ["Accepted", "Invalid", "Rejected"]:
        resume = f"Scripts/notarize.sh {args.kind} {shlex.quote(str(artifact))} --resume {shlex.quote(str(receipt))}"
        raise RuntimeError(f"Not complete ({status}). Resume without uploading again: {resume}")
    run(["xcrun", "notarytool", "log", submission, "--keychain-profile", profile, attempt / "log.json"], attempt, "log")
    log = json.loads((attempt / "log.json").read_text())
    if log.get("jobId") != submission or log.get("status") != status:
        raise RuntimeError("Notary log and authoritative status differ")
    if status != "Accepted":
        raise RuntimeError(f"Apple returned {status}; inspect {attempt / 'log.json'}")
    if signature(artifact, args.kind, team)[0] != cdhash:
        raise RuntimeError("Artifact signature changed while notarization ran")
    if args.kind == "app":
        run(["xcrun", "stapler", "staple", artifact], attempt, "staple")
        run(["xcrun", "stapler", "validate", artifact], attempt, "ticket")
        signature(artifact, "app", team)
        run(["spctl", "--assess", "--type", "execute", "--verbose=4", artifact], attempt, "gatekeeper")
        destination = artifact.parent / f"KeyWeaver-{version}-arm64.zip"
        if destination.is_symlink():
            raise RuntimeError("Refusing a symlink at the ZIP destination")
        with tempfile.TemporaryDirectory(prefix=".KeyWeaver-zip-", dir=artifact.parent) as directory:
            packaged = Path(directory) / "distribution.zip"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", artifact, packaged], attempt, "stapled-zip")
            with zipfile.ZipFile(packaged, "a", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.write(ROOT / "LICENSE", "LICENSE")
            os.replace(packaged, destination)
        (receipt / "distribution.sha256").write_text(digest(destination) + "\n")
    else:
        with tempfile.TemporaryDirectory(prefix=".KeyWeaver-dmg-", dir=artifact.parent) as directory:
            packaged = Path(directory) / "distribution.dmg"
            shutil.copy2(upload, packaged)
            run(["xcrun", "stapler", "staple", packaged], attempt, "staple")
            run(["xcrun", "stapler", "validate", packaged], attempt, "ticket")
            if signature(packaged, "dmg", team)[0] != cdhash:
                raise RuntimeError("DMG code-directory hash changed during stapling")
            run(["hdiutil", "verify", packaged], attempt, "image-after")
            run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", packaged], attempt, "gatekeeper")
            if artifact.is_symlink() or digest(artifact) != initial_hash:
                raise RuntimeError("Destination DMG changed; refusing to replace it")
            metadata["stapled_sha256"] = digest(packaged)
            os.replace(packaged, artifact)
        (receipt / "artifact.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (receipt / "completed.txt").write_text("Accepted, stapled, signature-verified and Gatekeeper-assessed.\n")
    print(f"Accepted and verified: {artifact}\nPrivate receipts: {receipt}")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)

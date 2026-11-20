"""Collect unchanged XCTest PNGs from the localized product flows on one native iPhone."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess

ROOT = Path("build/store")
MANIFEST = Path("release/worldwide/locales.json")
SCREENS = ["01-home", "02-ledger", "03-review", "04-detail", "05-calendar"]


def inject_locale(settings, locale):
    if isinstance(settings, dict):
        if settings.get("TestBundlePath", "").endswith("ShekatiUITests.xctest"):
            settings.setdefault("EnvironmentVariables", {})["SHEKATI_STORE_LOCALE"] = locale
            return 1
        return sum(inject_locale(value, locale) for value in settings.values())
    if isinstance(settings, list):
        return sum(inject_locale(value, locale) for value in settings)
    return 0


def capture(entry, original_run, destination, device):
    code = entry["store"]
    bundle = entry["bundle"]
    settings = plistlib.loads(original_run.read_bytes())
    if not inject_locale(settings, bundle):
        raise ValueError("ShekatiUITests target missing from xctestrun")
    # Test bundles use __TESTROOT__, which is relative to this plist's directory.
    test_run = original_run.with_name(f"store-{code}.xctestrun")
    test_run.write_bytes(plistlib.dumps(settings))
    result = Path(os.environ["RUNNER_TEMP"]) / f"store-{code}.xcresult"
    subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(test_run),
                    "-only-testing:ShekatiUITests/StoreScreenshotUITests/testLocalizedProductScreens",
                    "-destination", destination, "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result)], check=True)
    attachments = result.with_suffix(".attachments")
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(attachments)], check=True)
    folder = ROOT / code
    folder.mkdir(parents=True, exist_ok=True)
    shots = {}
    for test in json.loads((attachments / "manifest.json").read_text()):
        for item in test.get("attachments", []):
            label = item.get("suggestedHumanReadableName", "")
            match = re.search("Store-" + re.escape(bundle) + r"-(0[1-5]-[a-z]+)(?![a-z])", label)
            if not match or match[1] not in SCREENS:
                continue
            name = match[1]
            if name in shots:
                raise ValueError(f"Duplicate screenshot {name}")
            path = attachments / item["exportedFileName"]
            raw = path.read_bytes()
            if raw[:8] != b"\x89PNG\r\n\x1a\n" or list(struct.unpack(">II", raw[16:24])) != device["nativePortraitPixels"]:
                raise ValueError(f"{name}: unexpected format or device dimensions")
            (folder / (name + ".png")).write_bytes(raw)
            shots[name] = hashlib.sha256(raw).hexdigest()
    if set(SCREENS) != set(shots) or len(set(shots.values())) != 5:
        raise ValueError(f"{code}: five distinct native screens required; found {list(shots)}")
    proof = {"store": code, "bundle": bundle, "source": os.environ["GITHUB_SHA"], "run": os.environ["GITHUB_RUN_ID"],
             "device": device, "originalPNGHashes": shots}
    (folder / "capture.json").write_text(json.dumps(proof, indent=2))
    shutil.rmtree(result)
    shutil.rmtree(attachments)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", required=True, help="Comma separated App Store locale shortcodes")
    parser.add_argument("--destination", required=True)
    args = parser.parse_args()
    rows = {entry["store"]: entry for entry in json.loads(MANIFEST.read_text())["locales"]}
    device = json.loads(Path("build/capture-device.json").read_text())
    xctestrun, = Path("DerivedData/Build/Products").glob("*.xctestrun")
    for locale in args.locales.split(","):
        capture(rows[locale], xctestrun, args.destination, device)


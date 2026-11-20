"""Collect unchanged XCTest PNGs from the localized product flows on one native iPhone."""
import argparse
import hashlib
from itertools import combinations
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
from PIL import Image, ImageChops

ROOT = Path("build/store")
MANIFEST = Path("release/worldwide/locales.json")
SCREENS = ["01-home", "02-ledger", "03-review", "04-detail", "05-calendar"]


def verify_distinct_bodies(folder):
    bodies = {}
    for name in SCREENS:
        with Image.open(folder / (name + ".png")) as image:
            width, height = image.size
            body = image.crop((0, round(height * 0.14), width, round(height * 0.86)))
            bodies[name] = body.convert("RGB").resize((128, 192), Image.Resampling.BOX)

    differences = {}
    for first, second in combinations(SCREENS, 2):
        red, green, blue = ImageChops.difference(bodies[first], bodies[second]).split()
        peak = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        histogram = peak.histogram()
        # Count visible content changes, ignoring tiny rendering differences. The crop
        # excludes the status/navigation chrome and the selected tab at the bottom.
        changed = sum(histogram[13:]) / sum(histogram)
        if changed < 0.02:
            raise ValueError(f"{folder.name}: {first} and {second} show nearly identical screen bodies "
                             f"({changed:.2%} visibly changed)")
        differences[first + "/" + second] = round(changed, 5)
    return differences


def inject_locale(settings, locale):
    if isinstance(settings, dict):
        if settings.get("TestBundlePath", "").endswith("ShekatiUITests.xctest"):
            settings.setdefault("EnvironmentVariables", {})["SHEKATI_STORE_LOCALE"] = locale
            return 1
        return sum(inject_locale(value, locale) for value in settings.values())
    if isinstance(settings, list):
        return sum(inject_locale(value, locale) for value in settings)
    return 0


def capture(entry, original_run, destination, device, app_info):
    code = entry["store"]
    bundle = entry["bundle"]
    settings = plistlib.loads(original_run.read_bytes())
    if not inject_locale(settings, bundle):
        raise ValueError("ShekatiUITests target missing from xctestrun")
    # Test bundles use __TESTROOT__, which is relative to this plist's directory.
    test_run = original_run.with_name(f"store-{code}.xctestrun")
    test_run.write_bytes(plistlib.dumps(settings))
    result = Path(os.environ["RUNNER_TEMP"]) / f"store-{code}.xcresult"
    run = subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(test_run),
                    "-only-testing:ShekatiUITests/StoreScreenshotUITests/testLocalizedProductScreens",
                    "-destination", destination, "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result)])
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
    if run.returncode:
        # Keep partial original screenshots with the test failure for the independent reviewer.
        with (folder / "test-result.json").open("w") as report:
            subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)], stdout=report, check=True)
        raise RuntimeError(f"{code}: native UI test failed after capturing {list(shots)}")
    if set(SCREENS) != set(shots) or len(set(shots.values())) != 5:
        raise ValueError(f"{code}: five distinct native screens required; found {list(shots)}")
    body_differences = verify_distinct_bodies(folder)
    subprocess.run(["xcrun", "swift", "Tools/ScreenAudit/frame_store.swift", str(folder),
                    str(MANIFEST.parent / "metadata" / (code + ".json"))], check=True)
    proof = {"store": code, "bundle": bundle, "source": os.environ["GITHUB_SHA"], "run": os.environ["GITHUB_RUN_ID"],
             "version": app_info["CFBundleShortVersionString"], "build": app_info["CFBundleVersion"],
             "captureEnvironment": "Debug iPhone simulator with fictional records",
             "device": device, "originalPNGHashes": shots, "visibleBodyDifferences": body_differences, "storeArtworkHashes": {
                 name: hashlib.sha256((folder / "store" / (name + ".png")).read_bytes()).hexdigest() for name in shots}}
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
    products = Path("DerivedData/Build/Products")
    xctestrun, = products.glob("*.xctestrun")
    info_path, = products.glob("*-iphonesimulator/Shekati.app/Info.plist")
    app_info = plistlib.loads(info_path.read_bytes())
    failures = []
    for locale in args.locales.split(","):
        try:
            capture(rows[locale], xctestrun, args.destination, device, app_info)
        except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
            failures.append(f"{locale}: {error}")
            print(failures[-1], flush=True)
    if failures:
        raise SystemExit("\n".join(failures))


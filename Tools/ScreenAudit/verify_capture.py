"""Record exact native pixels and require both orientations for every UI scenario."""

import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys


TESTS = {
    "testEnglishPortraitAndLandscape",
    "testArabicPortraitAndLandscape",
    "testEnglishAccessibilityPortraitAndLandscape",
    "testArabicAccessibilityPortraitAndLandscape",
}

def pixel_reports(paths):
    if sys.platform == "darwin":
        inspector = Path(__file__).with_name("check_capture_pixels.swift")
        reports = subprocess.check_output(["xcrun", "swift", str(inspector), *paths], text=True)
        return "CoreGraphics", json.loads(reports)

    # Revalidate unmodified hosted-run artifacts on a workstation without Xcode.
    from PIL import Image

    def edge_fraction(lines):
        return next((i / len(lines) for i, dark in enumerate(lines) if not dark), 1.0)

    reports = []
    for path in paths:
        with Image.open(path) as source:
            orientation = source.getexif().get(274, 1)
            rgba = source.convert("RGBA")
            image = Image.new("RGB", rgba.size)
            image.paste(rgba, mask=rgba.getchannel("A"))
            pixels = image.load()
            width, height = image.size
            xs = range(0, width, max(1, width // 400))
            ys = range(0, height, max(1, height // 400))
            # Stop at the first nonblack pixel on each sampled line, as the native
            # verifier does. Its bitmap origin is at the lower left.
            columns = [all(max(pixels[x, height - 1 - y]) <= 8 for y in ys) for x in range(width)]
            rows = [all(max(pixels[x, y]) <= 8 for x in xs) for y in range(height)]
            reports.append({"path": path, "imageOrientation": orientation, "blackEdgeFractions": {
                "left": edge_fraction(columns), "right": edge_fraction(columns[::-1]),
                "top": edge_fraction(rows), "bottom": edge_fraction(rows[::-1]),
            }})
    return "Pillow", reports


def main():
    device = json.loads(Path("build/capture-device.json").read_text(encoding="utf-8"))
    folder = Path("build/ui-attachments")
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    expected_portrait = tuple(device["nativePortraitPixels"])
    expected_landscape = tuple(device["nativeLandscapePixels"])
    capture_paths = [str(folder / attachment["exportedFileName"])
                     for test in manifest
                     if test.get("testIdentifier", "").split("/")[-1].removesuffix("()") in TESTS
                     for attachment in test.get("attachments", [])
                     if attachment["exportedFileName"].lower().endswith(".png")]
    # Read metadata and pixels without altering files. Native screenshots may use EXIF
    # orientation to display their original pixels; verify the displayed dimensions.
    decoder, pixel_report = pixel_reports(capture_paths)
    by_file = {Path(item["path"]).name: item for item in pixel_report}
    coverage = {name: set() for name in TESTS}
    screenshots = []
    for test in manifest:
        identifier = test.get("testIdentifier", "")
        name = identifier.split("/")[-1].removesuffix("()")
        if name not in coverage:
            continue
        for attachment in test.get("attachments", []):
            path = folder / attachment["exportedFileName"]
            if path.suffix.lower() != ".png":
                continue
            raw = path.read_bytes()
            assert raw[:8] == b"\x89PNG\r\n\x1a\n", path.name
            raw_width, raw_height = struct.unpack(">II", raw[16:24])
            report = by_file[path.name]
            image_orientation = report["imageOrientation"]
            assert image_orientation in (1, 3, 6, 8), (path.name, "unknown or mirrored screenshot orientation", report)
            width, height = ((raw_height, raw_width) if image_orientation in (6, 8)
                             else (raw_width, raw_height))
            pixels = (width, height)
            assert pixels in (expected_portrait, expected_landscape), (path.name, pixels, device)
            orientation = "portrait" if width < height else "landscape"
            label = attachment.get("suggestedHumanReadableName", "")
            # XCTest appends "_0_<UUID>.png" to the requested attachment name.
            # Underscores delimit the caption even though regex \b calls them word characters.
            requested = re.findall(r"(?<![a-z0-9])(portrait|landscape)(?![a-z0-9])", label.lower())
            # Labels record the requested scenario; a landscape caption on a portrait PNG
            # is invalid even when that PNG happens to match another supported size.
            assert len(set(requested)) == 1, (path.name, "missing or ambiguous requested orientation", label)
            assert orientation == requested[0], (path.name, "capture orientation does not match requested scenario", label, pixels)
            frame = re.search(r"(\d+)x(\d+)pt", label)
            assert frame, (path.name, "missing measured window dimensions", label)
            window_pixels = tuple(int(value) * device["scale"] for value in frame.groups())
            assert pixels == window_pixels, (path.name, "PNG dimensions do not match actual window", pixels, window_pixels)
            coverage[name].add(orientation)
            screenshots.append({
                "file": path.name, "name": label,
                "test": identifier, "width": width, "height": height,
                "rawWidth": raw_width, "rawHeight": raw_height,
                "imageOrientation": image_orientation,
                "blackEdgeFractions": report["blackEdgeFractions"],
                "orientation": orientation, "windowPoints": [int(value) for value in frame.groups()],
                "sha256": hashlib.sha256(raw).hexdigest(),
            })
    for name, orientations in coverage.items():
        assert orientations == {"portrait", "landscape"}, (name, "missing native orientation evidence", orientations)
    # XCTest's app-window capture can have large black padding despite native pixel
    # dimensions. Edge-band thickness is independent of orientation metadata.
    for screenshot in screenshots:
        report = by_file[screenshot["file"]]
        assert max(report["blackEdgeFractions"].values()) <= 0.10, (
            screenshot["file"], "invalid contiguous black edge padding in the light-mode fixture", report,
        )
    proof = {
        "sourceCommit": os.environ.get("GITHUB_SHA") or subprocess.check_output(
            ["git", "rev-parse", "HEAD"], text=True).strip(),
        "workflowRun": os.environ.get("GITHUB_RUN_ID"), "device": device,
        "editing": "None. Original native XCTest attachments; no resizing or generated pixels.",
        "appearance": "light",
        "pixelValidation": f"{decoder} decoding; reject contiguous wholly black edge bands wider/taller than 10% of the image. Compare displayed dimensions using PNG orientation metadata, retaining raw dimensions and bytes.",
        "coverage": {name: sorted(orientations) for name, orientations in coverage.items()},
        "screenshots": screenshots,
    }
    Path("build/capture-provenance.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(f"Verified {len(screenshots)} original {device['deviceName']} screenshots and portrait/landscape coverage for all four scenarios.")


if __name__ == "__main__":
    main()

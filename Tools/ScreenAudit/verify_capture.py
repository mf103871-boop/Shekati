"""Record exact native pixels and require both orientations for every UI scenario."""

import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess


TESTS = {
    "testEnglishPortraitAndLandscape",
    "testArabicPortraitAndLandscape",
    "testEnglishAccessibilityPortraitAndLandscape",
    "testArabicAccessibilityPortraitAndLandscape",
}


def main():
    device = json.loads(Path("build/capture-device.json").read_text())
    folder = Path("build/ui-attachments")
    manifest = json.loads((folder / "manifest.json").read_text())
    expected_portrait = tuple(device["nativePortraitPixels"])
    expected_landscape = tuple(device["nativeLandscapePixels"])
    capture_paths = [str(folder / attachment["exportedFileName"])
                     for test in manifest
                     if test.get("testIdentifier", "").split("/")[-1].removesuffix("()") in TESTS
                     for attachment in test.get("attachments", [])
                     if attachment["exportedFileName"].lower().endswith(".png")]
    # Read metadata and pixels without altering files. Native screenshots may use EXIF
    # orientation to display their original pixels; verify the displayed dimensions.
    pixel_report = json.loads(subprocess.check_output([
        "xcrun", "swift", "Tools/ScreenAudit/check_capture_pixels.swift", *capture_paths,
    ], text=True))
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
            requested = re.findall(r"\b(portrait|landscape)\b", label.lower())
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
        "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "workflowRun": os.environ.get("GITHUB_RUN_ID"), "device": device,
        "editing": "None. Original native XCTest attachments; no resizing or generated pixels.",
        "appearance": "light",
        "pixelValidation": "Native CoreGraphics decoding; reject contiguous wholly black edge bands wider/taller than 10% of the image. Compare displayed dimensions using PNG orientation metadata, retaining raw dimensions and bytes.",
        "coverage": {name: sorted(orientations) for name, orientations in coverage.items()},
        "screenshots": screenshots,
    }
    Path("build/capture-provenance.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(f"Verified {len(screenshots)} original {device['deviceName']} screenshots and portrait/landscape coverage for all four scenarios.")


if __name__ == "__main__":
    main()

"""Record exact native pixels and require both orientations for every UI scenario."""

import hashlib
import json
import os
from pathlib import Path
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
            width, height = struct.unpack(">II", raw[16:24])
            pixels = (width, height)
            assert pixels in (expected_portrait, expected_landscape), (path.name, pixels, device)
            orientation = "portrait" if width < height else "landscape"
            coverage[name].add(orientation)
            screenshots.append({
                "file": path.name, "name": attachment.get("suggestedHumanReadableName"),
                "test": identifier, "width": width, "height": height,
                "orientation": orientation, "sha256": hashlib.sha256(raw).hexdigest(),
            })
    for name, orientations in coverage.items():
        assert orientations == {"portrait", "landscape"}, (name, "missing native orientation evidence", orientations)
    proof = {
        "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "workflowRun": os.environ.get("GITHUB_RUN_ID"), "device": device,
        "editing": "None. Original native XCTest attachments; no resizing or generated pixels.",
        "coverage": {name: sorted(orientations) for name, orientations in coverage.items()},
        "screenshots": screenshots,
    }
    Path("build/capture-provenance.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(f"Verified {len(screenshots)} original {device['deviceName']} screenshots and portrait/landscape coverage for all four scenarios.")


if __name__ == "__main__":
    main()

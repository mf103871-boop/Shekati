"""Create a fresh simulator of a declared size; never silently substitute sizes."""

import json
import os
from pathlib import Path
import subprocess


DEVICES = {
    "small": [("iPhone SE (3rd generation)", (750, 1334), 2)],
    "medium": [("iPhone 17 Pro", (1206, 2622), 3), ("iPhone 17", (1206, 2622), 3), ("iPhone 16 Pro", (1206, 2622), 3)],
    "large": [("iPhone 17 Pro Max", (1320, 2868), 3), ("iPhone 16 Pro Max", (1320, 2868), 3)],
}


def read_simctl(*arguments):
    return json.loads(subprocess.check_output(["xcrun", "simctl", *arguments, "-j"]))


def main():
    size = os.environ["SCREEN_SIZE"]
    candidates = DEVICES[size]
    device_types = {item["name"]: item["identifier"] for item in read_simctl("list", "devicetypes")["devicetypes"]}
    runtimes = [item for item in read_simctl("list", "runtimes")["runtimes"]
                if item.get("isAvailable") and item.get("platform") == "iOS"]
    if not runtimes:
        runtimes = [item for item in read_simctl("list", "runtimes")["runtimes"]
                    if item.get("isAvailable") and ".iOS-" in item["identifier"]]
    runtimes.sort(key=lambda item: tuple(map(int, item["version"].split("."))), reverse=True)
    errors = []
    for runtime in runtimes:
        for name, pixels, scale in candidates:
            if name not in device_types:
                continue
            result = subprocess.run(
                ["xcrun", "simctl", "create", f"Shekati screen audit {size}", device_types[name], runtime["identifier"]],
                capture_output=True, text=True,
            )
            if result.returncode:
                errors.append(f"{name} / {runtime['identifier']}: {result.stderr.strip()}")
                continue
            udid = result.stdout.strip()
            evidence = {
                "sizeClass": size, "deviceName": name, "deviceType": device_types[name],
                "udid": udid, "runtime": runtime["identifier"], "runtimeVersion": runtime["version"],
                "nativePortraitPixels": pixels, "nativeLandscapePixels": list(reversed(pixels)),
                "scale": scale, "portraitPoints": [value / scale for value in pixels],
                "freshSimulator": True,
            }
            Path("build").mkdir(exist_ok=True)
            Path("build/capture-device.json").write_text(json.dumps(evidence, indent=2) + "\n")
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"destination=platform=iOS Simulator,id={udid}\nudid={udid}\n")
            print(json.dumps(evidence, indent=2))
            return
    raise SystemExit(f"No compatible native {size} iPhone simulator; refusing a different-size fallback.\n" + "\n".join(errors))


if __name__ == "__main__":
    main()

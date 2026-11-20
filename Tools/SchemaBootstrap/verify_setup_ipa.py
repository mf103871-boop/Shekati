"""Check the download's identity before installing the side-by-side setup app."""

import argparse
import plistlib
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile

BUNDLE_ID = "com.mf103871.shekati.schema-setup"
CONTAINER_ID = "iCloud.com.mf103871.shekati"


def verify(ipa: Path) -> str:
    with ZipFile(ipa) as archive:
        info_files = []
        for name in archive.namelist():
            parts = PurePosixPath(name).parts
            if len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist":
                info_files.append(name)
        if len(info_files) != 1:
            raise ValueError("Expected a single top-level iPhone app in the supplied IPA")
        info = plistlib.loads(archive.read(info_files[0]))
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": "ShekatiSchemaBootstrap",
        "ShekatiCloudContainerIdentifier": CONTAINER_ID,
        "ShekatiCloudEnvironment": "Development",
        "UIDeviceFamily": [1],
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"Unexpected {key}: expected {value!r}")
    return str(info["CFBundleVersion"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    try:
        build = verify(args.ipa)
    except (BadZipFile, KeyError, OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Setup identity check failed: {error}\n")
    print(f"Verified packaged identity {BUNDLE_ID}, build {build}, declaring Development CloudKit.")

#!/usr/bin/env python3
"""Validate shipping iOS and App Store localizations without using the network."""
import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Shekati/Resources"
RELEASE = ROOT / "release/worldwide"
LINE = re.compile(r'^\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;\s*$')
TOKEN = r'"((?:[^"\\]|\\.)*)"'
TRANSLATOR_ANNOTATION = re.compile(r"@\s*(?:info|option|action|label)\b|(?<=[^\x00-\x7f])(?:Name|Comment)$", re.I)
CALENDAR_YEAR = re.compile(r"\b(?:19|20)\d{2}\b")

def known_source_keys():
    required=set()
    for source in (ROOT/"Shekati").rglob("*.swift"):
        swift=source.read_text(encoding="utf-8-sig")
        literal_calls=re.findall(r'(?:\btr|\btranslated|Localization\.text)\(\s*'+TOKEN,swift)
        for pair in re.findall(r'(?:\btr|\btranslated)\([^()\n]*?\?\s*'+TOKEN+r'\s*:\s*'+TOKEN,swift):
            literal_calls.extend(pair)
        if source.stem.endswith("Arabic") or source.stem == "Localization":
            table=swift.split("static let arabic:",1)[-1]
            literal_calls.extend(k for k,_ in re.findall(TOKEN+r'\s*:\s*'+TOKEN,table))
        if source.name == "CashFlowReport.swift":
            literal_calls.extend(re.findall(r'\(\s*'+TOKEN+r'\s*,\s*outlook\.',swift))
        for value in literal_calls:
            if "\\(" not in value:
                required.add(json.loads('"'+value+'"'))
    return required

def read_strings(file):
    result = {}
    for number, line in enumerate(file.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip() or line.strip().startswith(("/*", "//")):
            continue
        match = LINE.fullmatch(line)
        if not match:
            raise ValueError(f"{file.relative_to(ROOT)}:{number} invalid strings syntax")
        key, value = map(json.loads, match.groups())
        if key in result or not value.strip() or "\ufffd" in value:
            raise ValueError(f"{file.relative_to(ROOT)}:{number} duplicate, empty or damaged entry: {key!r}")
        result[key] = value
    return result

def inspect(require_release):
    manifest = json.loads((RELEASE/"locales.json").read_text(encoding="utf8"))
    info = plistlib.loads((RESOURCES/"Info.plist").read_bytes())
    reference = read_strings(RESOURCES/"en.lproj/Localizable.strings")
    problems = []
    uncovered = known_source_keys()-reference.keys()
    if uncovered:
        problems.append("Source keys absent from English table: "+", ".join(sorted(uncovered)))
    expected = {entry["bundle"] for entry in manifest["locales"]} | {"en"}
    if set(info["CFBundleLocalizations"]) != expected:
        problems.append("Info.plist and locale inventory disagree")
    if len({row["store"] for row in manifest["locales"]}) != len(manifest["locales"]):
        problems.append("Duplicate storefront locale")
    for entry in manifest["locales"]:
        try:
            app,store = entry["bundle"],entry["store"]
            bundle = RESOURCES / f"{app}.lproj"
            ui = read_strings(bundle / "Localizable.strings")
            if ui.keys() != reference.keys():
                raise ValueError(f"{len(reference.keys()-ui.keys())} missing, {len(ui.keys()-reference.keys())} extra UI keys")
            for key, translated in ui.items():
                if TRANSLATOR_ANNOTATION.search(translated):
                    raise ValueError(f"Translator annotation in {key!r}")
                if set(CALENDAR_YEAR.findall(translated)) - set(CALENDAR_YEAR.findall(reference[key])):
                    raise ValueError(f"Unexpected calendar year in {key!r}")
            permissions = read_strings(bundle / "InfoPlist.strings")
            if set(permissions) != {"CFBundleDisplayName","NSFaceIDUsageDescription","NSCameraUsageDescription"}:
                raise ValueError("Permission or display-name key mismatch")
            expected_name = "شيكاتي" if app == "ar" else "Shekati"
            metadata = json.loads((RELEASE/"metadata"/f"{store}.json").read_text(encoding="utf8"))
            if any(name != expected_name for name in (metadata["name"], permissions["CFBundleDisplayName"], ui["Shekati"])):
                raise ValueError("Brand name mismatch")
            for field,unit,limit in [("subtitle","chars",30),("description","chars",4000),("keywords","bytes",100)]:
                value = metadata[field]
                length = len(value.encode("utf8")) if unit == "bytes" else len(value)
                if not (0 < length <= limit):
                    raise ValueError(f"{field} has {length} {unit}; limit {limit}")
                if TRANSLATOR_ANNOTATION.search(value):
                    raise ValueError(f"Translator annotation in store {field}")
            for label, url in (
                ("Terms of use", "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"),
                ("Privacy policy", "https://mf103871-boop.github.io/Shekati/privacy.html"),
            ):
                if ui[label] + "\n" + url not in metadata["description"]:
                    raise ValueError(f"Missing localized subscription disclosure: {label}")
            for product in ("monthly","annual"):
                item=metadata["subscriptionLocalizations"][product]
                if not (0<len(item["name"])<=30 and 0<len(item["description"])<=45):
                    raise ValueError(f"{product}: subscription name or description has invalid length")
            headings = metadata["screenshotHeadings"]
            if len(headings) != len(manifest["requiredScreens"]) or any(
                not title.strip() or TRANSLATOR_ANNOTATION.search(title) for title in headings
            ):
                raise ValueError("Missing or damaged screenshot heading")
            if ui["Shekati Plus"] not in headings[manifest["requiredScreens"].index("scan-review")]:
                raise ValueError("Scan screenshot must identify the Plus feature")
            if require_release:
                if entry["linguisticReview"] != "passed" or entry["nativeVisualReview"] != "passed":
                    raise ValueError("Linguistic and native UI reviewer evidence pending")
                screenshots=entry["screenshots"]
                if len(screenshots)!=len(manifest["requiredScreens"]):
                    raise ValueError("Missing native release screenshots")
                for screen in screenshots:
                    if not (RELEASE/screen).is_file():
                        raise ValueError(f"Screenshot missing: {screen}")
        except (OSError,ValueError,KeyError) as error:
            problems.append(f'{entry["store"]}: {error}')
    print(f'Checked {len(manifest["locales"])} store locales, {len(expected)} app bundles, {len(reference)} source keys.')
    for issue in problems: print(issue)
    return 1 if problems else 0

if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--require-release",action="store_true",help="also require reviewer sign-offs and native captures")
    sys.exit(inspect(parser.parse_args().require_release))

"""Compare this release's SwiftData delta; optionally check a read-only cktool export.

This script only reads the checkout and the optional .ckdb file. A successful export
check verifies required application fields, not mirroring metadata, permissions or sync.
"""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "7664b5d89d4212bb46b6a92ebeaca5b31cc2b5d0"
MODELS = ROOT / "Shekati/Models"
NEW_FIELDS = {
    "ChequeRecord": {"bankAccountID": "UUID?", "chequeBookID": "UUID?",
                     "replacesChequeID": "UUID?", "ledgerBaselineStatusRaw": "String?"},
    "BankAccountRecord": {"id": "UUID", "name": "String", "currencyCode": "String",
                          "openingMinor": "Int64", "createdAt": "Date"},
    "ChequeBookRecord": {"id": "UUID", "accountID": "UUID", "name": "String"},
    "LedgerEventRecord": {"id": "UUID", "parentID": "UUID?", "chequeID": "UUID?",
                          "accountID": "UUID?", "kindRaw": "String", "dayISO": "String",
                          "amountMinor": "Int64", "party": "String", "relatedID": "UUID?",
                          "currencyCode": "String"},
}
CK_TYPE = {"UUID": {"STRING"}, "String": {"STRING"}, "Int64": {"INT64", "INT(64)"},
           "Date": {"TIMESTAMP"}}


def swift_fields(text):
    types = {}
    for section in re.split(r"@Model\s+final class ", text)[1:]:
        name = section.split(" ", 1)[0]
        declarations = section.split("\n    init(", 1)[0]
        types[name] = dict(re.findall(
            r"^\s*(?:@Attribute\([^\n]*?\)\s+)?var\s+(\w+):\s*([\w\[\]]+\??)",
            declarations, re.M))
    return types


def check_source():
    old = subprocess.run(["git", "show", f"{BASELINE}:Shekati/Models/ChequeRecord.swift"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    before = swift_fields(old)
    after = {}
    for file in MODELS.glob("*.swift"):
        after.update(swift_fields(file.read_text(encoding="utf-8-sig")))
    expected = {name: fields.copy() for name, fields in before.items()}
    for name, fields in NEW_FIELDS.items():
        expected.setdefault(name, {}).update(fields)
    if expected != after:
        missing_or_changed = sorted(f"{t}.{f}" for t, cols in expected.items()
                                    for f, typ in cols.items() if after.get(t, {}).get(f) != typ)
        extras = sorted(f"{t}.{f}" for t, cols in after.items()
                        for f in cols if f not in expected.get(t, {}))
        raise SystemExit(f"Source delta changed: missing/changed {missing_or_changed}; extra {extras}")
    for entrypoint in (ROOT / "Shekati/App/ShekatiApp.swift",
                       ROOT / "Tools/SchemaBootstrap/Sources/SchemaInitializer.swift"):
        if any(f"{name}.self" not in entrypoint.read_text(encoding="utf-8") for name in expected):
            raise SystemExit(f"Schema registration incomplete: {entrypoint.name}")
    print(f"Build 9 vs candidate: {len(expected) - len(before)} new record types, "
          f"{len(NEW_FIELDS['ChequeRecord'])} additive cheque fields. Existing field types match.")


def check_export(path):
    text = path.read_text(encoding="utf-8-sig")
    starts = list(re.finditer(r'(?im)^\s*RECORD\s+TYPE\s+"?([\w]+)"?\s*\(', text))
    sections = {m.group(1): text[m.end():starts[i + 1].start() if i + 1 < len(starts) else len(text)]
                for i, m in enumerate(starts)}
    problems = []
    for record, fields in NEW_FIELDS.items():
        body = sections.get("CD_" + record, "")
        for field, swift_type in fields.items():
            token = "CD_" + field
            match = re.search(r'(?im)^\s*"?' + token + r'"?\s+([A-Za-z0-9]+(?:\(64\))?)', body)
            if not match or match.group(1).upper() not in CK_TYPE[swift_type.rstrip("?")]:
                problems.append("CD_" + record + "." + token)
    if problems:
        raise SystemExit("Missing/unexpected exported field type: " + ", ".join(problems))
    print(f"All {sum(map(len, NEW_FIELDS.values()))} required additive app fields present in {path.name}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", type=Path, help="Existing schema exported by cktool")
    args = parser.parse_args()
    check_source()
    if args.export:
        check_export(args.export)

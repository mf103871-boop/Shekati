from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import sqlite3
import subprocess

root = Path.cwd()
qa = Path(__file__).resolve().parent
temp = Path(os.environ["RUNNER_TEMP"])
evidence = root / "upgrade-evidence"
evidence.mkdir(exist_ok=True)
bundle = "com.mf103871.shekati"
commits = {16: "7133895e2aa6546ab7999f9890cbe5af41e67d47", 17: "9fca85268c9a4bde4b563c7447bff062b793b0fc"}


def command(*args, output=False, cwd=None):
    result = subprocess.run([str(a) for a in args], cwd=cwd, capture_output=output, text=True, check=True)
    return result.stdout.strip() if output else None


def save(name, value):
    (evidence / name).write_text(json.dumps(value, indent=2, sort_keys=True))


def checkout(build):
    directory = temp / f"ShekatiProduct{build}"
    directory.mkdir()
    archive = temp / f"product{build}.tar"
    command("git", "archive", "--format=tar", f"--output={archive}", commits[build])
    command("tar", "-xf", archive, "-C", directory)
    for path in ("ShekatiUITests/InPlaceUpgradeAcceptanceTests.swift", "ShekatiTests/InPlaceUpgradeStoreTests.swift"):
        shutil.copyfile(root / path, directory / path)
    command("xcodegen", "generate", cwd=directory)
    return directory


def export(result, name):
    dest = evidence / name
    dest.mkdir(exist_ok=True)
    if result.is_dir():
        for key in ("summary", "tests"):
            with (dest / f"{key}.json").open("w") as f:
                subprocess.run(["xcrun", "xcresulttool", "get", "test-results", key, "--path", str(result)], stdout=f, check=True)
        command("xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", dest / "attachments")


def test(directory, build, name, identifier):
    result = temp / f"{name}.xcresult"
    try:
        command("xcodebuild", "test", "-project", directory / "Shekati.xcodeproj", "-scheme", "Shekati",
                "-destination", f"platform=iOS Simulator,id={sim}", "-derivedDataPath", temp / f"Derived{build}",
                "-parallel-testing-enabled", "NO", "-resultBundlePath", result,
                "-only-testing:" + identifier, "CODE_SIGNING_ALLOWED=NO")
    finally:
        export(result, name)


def container_state(build):
    appdir = Path(command("xcrun","simctl","get_app_container",sim,bundle,"app",output=True))
    data = Path(command("xcrun","simctl","get_app_container",sim,bundle,"data",output=True))
    info = plistlib.loads((appdir / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == bundle and info["CFBundleVersion"] == str(build)
    store = data / "Library/Application Support/Shekati/Shekati.store"
    assert store.is_file()
    with sqlite3.connect(store.as_uri() + "?mode=ro", uri=True) as db:
        store_id = db.execute("select Z_UUID from Z_METADATA").fetchone()[0]
    receipt = {"CFBundleVersion": str(build), "CFBundleIdentifier": bundle, "CFBundleShortVersionString": info["CFBundleShortVersionString"],
               "source": commits[build], "dataContainerID": data.name, "coreDataStoreUUID": store_id, "store": "Library/Application Support/Shekati/Shekati.store"}
    save(f"installed-{build}.json", receipt)
    return receipt


def native_state(build):
    folder = evidence / f"store{build}" / "attachments"
    groups = json.loads((folder / "manifest.json").read_text())
    artifacts = [a for g in groups for a in g["attachments"] if a["suggestedHumanReadableName"].startswith(f"Persisted-upgrade-fixture-build-{build}")]
    assert len(artifacts) == 1, artifacts
    return json.loads((folder / artifacts[0]["exportedFileName"]).read_bytes())


command("git", "diff", "--exit-code", commits[17], "HEAD", "--", "Shekati", "Packages", "project.yml")
runtimes = json.loads(command("xcrun","simctl","list","runtimes","-j",output=True))["runtimes"]
runtime = next(x["identifier"] for x in runtimes if x.get("isAvailable") and x["name"] == "iOS 26.2")
types = json.loads(command("xcrun","simctl","list","devicetypes","-j",output=True))["devicetypes"]
air = next(x["identifier"] for x in types if x["name"] == "iPhone Air")
sim = command("xcrun","simctl","create","Shekati upgrade fixture",air,runtime,output=True)
command("xcrun","simctl","bootstatus",sim,"-b")
command("xcrun","simctl","addmedia",sim,qa/"front.png",qa/"back.png")
save("simulator.json", {"device":"iPhone Air","runtime":runtime,"identifier":sim,"installs":commits})

states = {}
receipts = {}
for build in (16, 17):
    product = checkout(build)
    method = "testPrepareAndReopenBuild16" if build == 16 else "testReopenAndInspectBuild17"
    test(product, build, f"screen{build}", "ShekatiUITests/InPlaceUpgradeAcceptanceTests/" + method)
    receipts[build] = container_state(build)
    test(product, build, f"store{build}", "ShekatiTests/InPlaceUpgradeStoreTests/testReadRealApplicationStoreWithoutWriting")
    states[build] = native_state(build)

assert receipts[16]["coreDataStoreUUID"] == receipts[17]["coreDataStoreUUID"], "Core Data store was replaced"
assert states[16] == states[17], "Persisted account, cheque, ledger entries or images changed"
save("comparison.json", {"match": True, "coreDataStoreUUID": receipts[16]["coreDataStoreUUID"],
                         "sameDataContainerIdentifier": receipts[16]["dataContainerID"] == receipts[17]["dataContainerID"],
                         "source": commits, "state": states[17],
                         "SHA256": hashlib.sha256(json.dumps(states[17], sort_keys=True).encode()).hexdigest()})

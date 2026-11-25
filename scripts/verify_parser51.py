#!/usr/bin/env python3
"""Static parser/source-archive audit; never executes packaged JS or Swift."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import zipfile

p = argparse.ArgumentParser()
p.add_argument("source", help="worktree directory or source ZIP")
p.add_argument("--references", help="directory containing reference IPA files")
a = p.parse_args()
src = pathlib.Path(a.source)

def read_source(name):
    if src.is_dir():
        return (src / name).read_bytes()
    with zipfile.ZipFile(src) as archive:
        return archive.read(name)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def source_audit(text):
    checks = {
        "blank_site_name_falls_back_to_dictionary_key": (
            'if let name = ydsString(obj["siteName"])' in text
            and "name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty" in text
            and "bs.bookSourceName = sourceKey" in text
        ),
        "scalar_coercion_helpers": all(
            f"func {name}(" in text for name in ("ydsString", "ydsInt", "ydsBool")
        ),
        "request_url_object_form": (
            'raw as? [String: Any]' in text and 'dict["url"]' in text
        ),
        "scheme_case_and_absolute_url_handling": (
            "func ydsHasURLScheme(" in text and "ydsHasURLScheme(target)" in text
        ),
        "protocol_relative_url_handling": 'target.hasPrefix("//")' in text,
        "slash_boundary_normalization": (
            'base.hasSuffix("/") && target.hasPrefix("/")' in text
            and 'base + "/" + target' in text
        ),
    }
    return checks

def extracted_script_check(ref_dir, ipa_name, archive_path, data):
    parent = ref_dir.parent
    for manifest_path in parent.glob("extracted-*/EXTRACTION-MANIFEST.json"):
        try:
            manifest = json.loads(manifest_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if pathlib.Path(manifest.get("ipa", "")).name != ipa_name:
            continue
        entry = next((item for item in manifest.get("files", [])
                      if item.get("archive_path") == archive_path), None)
        extracted = parent / manifest_path.parent.name / archive_path
        actual = extracted.read_bytes() if extracted.is_file() else None
        return {
            "manifest": str(manifest_path),
            "archive_member": archive_path,
            "manifest_sha256": entry.get("sha256") if entry else None,
            "extracted_sha256": sha(actual) if actual is not None else None,
            "archive_sha256": sha(data),
            "matches_archive": bool(entry) and actual == data and entry.get("sha256") == sha(data),
        }
    return {"manifest": None, "archive_member": archive_path, "matches_archive": False}

def audit_ipa(path, ref_dir):
    raw = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        info_path = next((name for name in names
                          if name.endswith(".app/Info.plist")), None)
        if info_path is None:
            raise ValueError(f"No app Info.plist: {path.name}")
        info = plistlib.loads(archive.read(info_path))
        assets = {}
        for name in ("ruleEngine.js", "legado-engine.js"):
            member = f"Payload/YueduReader.app/{name}"
            data = archive.read(member) if member in names else None
            assets[name] = {
                "sha256": sha(data) if data is not None else None,
                "bytes": len(data) if data is not None else None,
                "extraction": extracted_script_check(ref_dir, path.name, member, data)
                if data is not None else None,
            }
        bad = archive.testzip()
    return {
        "filename": path.name,
        "bytes": len(raw),
        "sha256": sha(raw),
        "zip_entries": len(names),
        "crc": "PASS" if bad is None else f"FAIL:{bad}",
        "app_info_path": info_path,
        "bundle": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "scripts": assets,
    }

parser_data = read_source("Modules/Core/BookSource/BookSourceStore.swift")
parser_text = parser_data.decode("utf-8")
checks = source_audit(parser_text)
result = {
    "method": "static-source-and-archive-audit-not-runtime",
    "source": str(src),
    "parser_sha256": sha(parser_data),
    "yds_checks": checks,
    "references": [],
    "target_reference_pair": None,
}
if a.references:
    ref_dir = pathlib.Path(a.references)
    archives = [audit_ipa(path, ref_dir) for path in sorted(ref_dir.glob("*.ipa"))]
    targets = [item for item in archives if item["bundle"] == "com.zhangruilin.yuedureader"
               and (item["version"], item["build"]) in (("3.0.2", "156"), ("3.0.3", "160"))]
    by_version = {(item["version"], item["build"]): item for item in targets}
    wanted = (("3.0.2", "156"), ("3.0.3", "160"))
    if any(key not in by_version for key in wanted):
        raise SystemExit("Required Build 156 / Build 160 reference IPA is missing")
    pair = [by_version[key] for key in wanted]
    script_names = ("ruleEngine.js", "legado-engine.js")
    script_comparison = {
        name: {
            "byte_identical": pair[0]["scripts"][name]["sha256"] == pair[1]["scripts"][name]["sha256"],
            "sha256_by_version": {
                pair[index]["version"]: pair[index]["scripts"][name]["sha256"]
                for index in range(2)
            },
            "extraction_matches_archive": all(
                pair[index]["scripts"][name]["extraction"]
                and pair[index]["scripts"][name]["extraction"]["matches_archive"]
                for index in range(2)
            ),
        }
        for name in script_names
    }
    for item in pair:
        if item["crc"] != "PASS":
            raise SystemExit(f"Reference archive CRC failed: {item['filename']}")
        for name in script_names:
            if not item["scripts"][name]["sha256"]:
                raise SystemExit(f"Missing {name} in {item['filename']}")
            if not item["scripts"][name]["extraction"]["matches_archive"]:
                raise SystemExit(f"Extracted bytes do not match original: {item['filename']}:{name}")
    result["references"] = archives
    result["target_reference_pair"] = {
        "versions": [f"{item['version']} ({item['build']})" for item in pair],
        "scripts": script_comparison,
        "scope_note": "Readable packaged JS assets only; not evidence of native YDS importer behavior or runtime execution.",
    }
    if not all(item["byte_identical"] for item in script_comparison.values()):
        raise SystemExit("Target reference JS asset hashes differ")
if not all(checks.values()):
    raise SystemExit("One or more static YDS implementation checks failed")
print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))

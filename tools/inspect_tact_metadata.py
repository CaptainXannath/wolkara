#!/usr/bin/env python3
"""Read-only TACT provenance report. Never sends requests or changes game data.

Reports only the active Forever build and allowlisted public content identifiers.
Pass the installation root containing .build.info and Data/config, not Documents.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

LIMIT = 2 * 1024 * 1024
HASH = re.compile(r"[0-9a-fA-F]{32}\Z")
MANIFESTS = ("patch-index", "patch", "encoding", "root", "install", "download")
CATALOGUES = ("archives", "patch-archives", "file-index", "patch-file-index")


def _read(path):
    with path.open("rb") as stream:
        data = stream.read(LIMIT + 1)
    if not data or len(data) > LIMIT:
        raise ValueError("Metadata absent or larger than 2 MiB")
    return data


def _lines(data):
    return [line.strip() for line in data.decode("utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def active_row(data):
    lines = _lines(data)
    if len(lines) < 2:
        raise ValueError("No build metadata rows")
    fields = [item.split("!", 1)[0] for item in lines[0].split("|")]
    required = {"Product", "Active", "Version", "Build Key", "CDN Key"}
    if len(set(fields)) != len(fields) or not required.issubset(fields):
        raise ValueError("Invalid build metadata columns")
    rows = []
    for line in lines[1:]:
        values = line.split("|")
        if len(values) != len(fields):
            raise ValueError("Incomplete build metadata row")
        row = dict(zip(fields, values))
        if row["Product"] == "wowf" and row["Active"] == "1":
            rows.append(row)
    if len(rows) != 1:
        raise ValueError("Expected exactly one active Forever build")
    row = rows[0]
    if not re.fullmatch(r"[0-9.]{1,64}", row["Version"]):
        raise ValueError("Invalid public build version")
    for field in ("Build Key", "CDN Key"):
        if not HASH.fullmatch(row[field]):
            raise ValueError("Invalid configuration key")
    return row


def config(data, key):
    if not HASH.fullmatch(key) or hashlib.md5(data).hexdigest() != key.lower():
        raise ValueError("Configuration checksum mismatch")
    result = {}
    for line in _lines(data):
        name, separator, value = line.partition(" = ")
        if not separator or not name or name in result:
            raise ValueError("Malformed or duplicate configuration field")
        result[name] = value.split()
    return result


def _local_config(root, key):
    if not HASH.fullmatch(key):
        raise ValueError("Invalid configuration key")
    path = root / "Data" / "config" / key[:2] / key[2:4] / key
    return config(_read(path), key)


def inspect(root, target):
    if not HASH.fullmatch(target):
        raise ValueError("Invalid target E-Key")
    row = active_row(_read(root / ".build.info"))
    build = _local_config(root, row["Build Key"])
    cdn = _local_config(root, row["CDN Key"])
    result = {"version": row["Version"], "configuration_checksums": "verified",
              "target_matches": [], "catalogues": {}}
    for field in MANIFESTS:
        for position, value in enumerate(build.get(field, [])):
            if value.lower() == target.lower():
                result["target_matches"].append({"source": "active-build-config",
                                                 "field": field, "token": position})
    keys = build.get("patch-index", [])
    if len(keys) == 2 and all(HASH.fullmatch(key) for key in keys):
        result["patch_index_manifest"] = {"ckey": keys[0], "ekey": keys[1],
                                          "resource": "encoded-data-object"}
        sizes = build.get("patch-index-size", [])
        if len(sizes) == 2 and all(re.fullmatch(r"[0-9]{1,10}", size) for size in sizes):
            result["patch_index_manifest"].update(decoded_bytes=int(sizes[0]),
                                                  encoded_bytes=int(sizes[1]))
    for field in CATALOGUES:
        present = missing = invalid = 0
        for key in cdn.get(field, []):
            if not HASH.fullmatch(key):
                invalid += 1
            elif (root / "Data" / "indices" / (key + ".index")).is_file():
                present += 1
            else:
                missing += 1
        result["catalogues"][field] = {"present": present, "missing": missing,
                                       "invalid": invalid, "check": "presence-only"}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--ekey", required=True)
    args = parser.parse_args()
    try:
        result = inspect(args.root, args.ekey)
    except (OSError, UnicodeError, ValueError):
        # Exception text can include local personal paths or metadata values.
        parser.exit(1, "Metadata unavailable, ambiguous, malformed or checksum-invalid.\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

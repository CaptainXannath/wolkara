#!/usr/bin/env python3
"""Package pinned Mozilla TLS certificate candidates for native trust filtering."""
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys
import urllib.request

SOURCE_URL = "https://curl.se/ca/cacert-2026-11-05.pem"
SOURCE_SHA256 = "427c064216761a1e72a8b30f0d954d08cb6e4435a82091fb865afd20c8497285"
SOURCE_COUNT = 118
MAX_SOURCE_BYTES = 4 * 1024 * 1024
REPO = Path(__file__).resolve().parents[1]


def certificates_from_pem(data):
    if len(data) > MAX_SOURCE_BYTES:
        raise ValueError("Public certificate source exceeds its size limit")
    blocks = re.findall(
        rb"-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----",
        data,
    )
    if (
        not blocks
        or len(blocks) > 1024
        or data.count(b"-----BEGIN CERTIFICATE-----") != len(blocks)
        or data.count(b"-----END CERTIFICATE-----") != len(blocks)
    ):
        raise ValueError("Incomplete or invalid public certificate source")
    certificates = [base64.b64decode(b"".join(block.split()), validate=True) for block in blocks]
    if any(not certificate or len(certificate) > 65536 for certificate in certificates):
        raise ValueError("Invalid public certificate size")
    if len(set(certificates)) != len(certificates):
        raise ValueError("Duplicate public certificates")
    return certificates


def pinned_source():
    cache = REPO / "build" / "public-roots" / "cacert-2026-11-05.pem"
    data = b""
    if cache.exists():
        with cache.open("rb") as cached:
            data = cached.read(MAX_SOURCE_BYTES + 1)
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as response:
            data = response.read(MAX_SOURCE_BYTES + 1)
        if len(data) > MAX_SOURCE_BYTES or hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
            raise ValueError("Public certificate source checksum mismatch")
        cache.parent.mkdir(parents=True, exist_ok=True)
        temporary = cache.with_name(f"{cache.name}.{os.getpid()}.download")
        temporary.write_bytes(data)
        os.replace(temporary, cache)
    return data


def package(output):
    data = pinned_source()
    certificates = certificates_from_pem(data)
    if len(certificates) != SOURCE_COUNT:
        raise ValueError("Unexpected public certificate count")
    source_notice = (
        "Mozilla TLS CA candidates, converted from the unmodified PEM source.\n"
        f"Source: {SOURCE_URL}\nSHA-256: {SOURCE_SHA256}\n"
        "License: Mozilla Public License 2.0, included in Mozilla-CA-LICENSE.\n"
        "The PEM source is included as PublicRootCertificates.pem.\n"
        "The device evaluates each candidate using its native trust store.\n"
    )
    resources = {
        "PublicRootCertificates.plist": plistlib.dumps(certificates, fmt=plistlib.FMT_BINARY),
        "PublicRootCertificates.pem": data,
        "PublicRootCertificates-source.txt": source_notice.encode("utf-8"),
        "Mozilla-CA-LICENSE": (REPO / "Mozilla-CA-LICENSE").read_bytes(),
    }
    output.mkdir(parents=True, exist_ok=True)
    for name, contents in resources.items():
        temporary = output / f"{name}.{os.getpid()}.tmp"
        temporary.write_bytes(contents)
        os.replace(temporary, output / name)
    print(f"Packaged {len(certificates)} public Mozilla certificate candidates")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: package_public_roots.py APP_RESOURCE_DIRECTORY")
    try:
        package(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        raise SystemExit(f"Cannot package public certificates: {error}") from error

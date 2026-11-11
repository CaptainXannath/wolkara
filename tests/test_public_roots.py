"""Public CA conversion and packaging use synthetic data except the pinned source check."""
import base64
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from tools import package_public_roots as roots


def pem(data):
    return b"-----BEGIN CERTIFICATE-----\n" + base64.b64encode(data) + b"\n-----END CERTIFICATE-----\n"


class PublicRootsTests(unittest.TestCase):
    def test_conversion_preserves_der(self):
        data = b"# Synthetic PEM source\n" + pem(b"synthetic first") + pem(b"synthetic second")
        self.assertEqual(roots.certificates_from_pem(data), [b"synthetic first", b"synthetic second"])

    def test_invalid_sources(self):
        malformed = [
            b"",
            pem(b""),
            pem(b"duplicate") * 2,
            b"-----BEGIN CERTIFICATE-----\neA==\n",
            pem(b"x" * 65537),
            b"x" * (roots.MAX_SOURCE_BYTES + 1),
        ]
        for data in malformed:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                roots.certificates_from_pem(data)

    def test_source_checksum_failure_preserves_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            cache = repo / "build/public-roots/cacert-2026-11-05.pem"
            cache.parent.mkdir(parents=True)
            cache.write_bytes(b"invalid cached data")
            with patch.object(roots, "REPO", repo), patch.object(roots.urllib.request, "urlopen") as download:
                download.return_value.__enter__.return_value.read.return_value = b"invalid downloaded data"
                with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                    roots.pinned_source()
            self.assertEqual(cache.read_bytes(), b"invalid cached data")

    def test_failed_source_leaves_existing_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            target = output / "PublicRootCertificates.plist"
            target.write_bytes(b"existing resource")
            with patch.object(roots, "pinned_source", return_value=pem(b"one synthetic certificate")):
                with self.assertRaises(ValueError):
                    roots.package(output)
            self.assertEqual(target.read_bytes(), b"existing resource")

    def test_package_includes_source_and_license(self):
        source = pem(b"first") + pem(b"second")
        with tempfile.TemporaryDirectory() as directory, patch.object(roots, "pinned_source", return_value=source), patch.object(roots, "SOURCE_COUNT", 2):
            output = Path(directory)
            roots.package(output)
            self.assertEqual(plistlib.loads((output / "PublicRootCertificates.plist").read_bytes()), [b"first", b"second"])
            self.assertEqual((output / "PublicRootCertificates.pem").read_bytes(), source)
            self.assertEqual((output / "Mozilla-CA-LICENSE").read_bytes(), (roots.REPO / "Mozilla-CA-LICENSE").read_bytes())
            self.assertIn(roots.SOURCE_SHA256, (output / "PublicRootCertificates-source.txt").read_text())


if __name__ == "__main__":
    unittest.main()

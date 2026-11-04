"""Synthetic TACT provenance fixtures; no vendor metadata or game bytes."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "inspect_tact_metadata", Path(__file__).resolve().parents[1] / "tools/inspect_tact_metadata.py")
tact = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tact)


class TactMetadataTests(unittest.TestCase):
    CKEY = "11" * 16
    EKEY = "22" * 16
    ARCHIVE = "33" * 16

    def fixture(self, root):
        build = (f"# Build Configuration\npatch-index = {self.CKEY} {self.EKEY}\n"
                 "patch-index-size = 1234 1000\nprivate-token = never-print-this\n").encode()
        cdn = f"# CDN Configuration\npatch-archives = {self.ARCHIVE}\n".encode()
        keys = []
        for data in (build, cdn):
            key = hashlib.md5(data).hexdigest()
            path = root / "Data/config" / key[:2] / key[2:4] / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            keys.append(key)
        header = "Product!STRING:0|Active!DEC:1|Version!STRING:0|Build Key!HEX:16|CDN Key!HEX:16"
        row = f"wowf|1|1.60.1.12345|{keys[0]}|{keys[1]}"
        (root / ".build.info").write_text(header + "\n" + row + "\n", encoding="utf-8")
        return build, keys, header, row

    def test_build_manifest_provenance_is_distinct_from_archive_catalogue(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            report = tact.inspect(root, self.EKEY)
            self.assertEqual(report["target_matches"], [
                {"source": "active-build-config", "field": "patch-index", "token": 1}])
            self.assertEqual(report["patch_index_manifest"], {
                "ckey": self.CKEY, "ekey": self.EKEY, "resource": "encoded-data-object",
                "decoded_bytes": 1234, "encoded_bytes": 1000})
            self.assertEqual(report["catalogues"]["patch-archives"]["missing"], 1)
            self.assertNotIn("never-print-this", str(report))

    def test_exact_token_matching(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            self.assertEqual(tact.inspect(root, "44" * 16)["target_matches"], [])

    def test_checksum_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            tact.config(b"patch-index = fake\n", "11" * 16)

    def test_duplicate_config_fields_rejected(self):
        data = b"patch = one\npatch = two\n"
        with self.assertRaises(ValueError):
            tact.config(data, hashlib.md5(data).hexdigest())

    def test_ambiguous_active_build_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, _, header, row = self.fixture(root)
            with self.assertRaises(ValueError):
                tact.active_row((header + "\n" + row + "\n" + row).encode())

    def test_configuration_path_injection_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                tact._local_config(Path(directory), "../../private-token")

    def test_presence_does_not_claim_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            indices = root / "Data/indices"
            indices.mkdir()
            (indices / (self.ARCHIVE + ".index")).write_bytes(b"arbitrary")
            report = tact.inspect(root, self.EKEY)
            self.assertEqual(report["catalogues"]["patch-archives"], {
                "present": 1, "missing": 0, "invalid": 0, "check": "presence-only"})


if __name__ == "__main__":
    unittest.main()

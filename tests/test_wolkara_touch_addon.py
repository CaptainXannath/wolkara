"""Run original Lua UI logic against synthetic APIs, without opening the game."""
import pathlib
import shutil
import struct
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons" / "WolkaraTouch"


class WolkaraTouchAddonTests(unittest.TestCase):
    def test_payload_is_self_contained(self):
        toc = (ADDON / "WolkaraTouch.toc").read_text()
        self.assertIn("## Interface: 16001", toc)
        payload = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
        self.assertEqual(payload, ["WolkaraTouch.lua"])
        self.assertTrue((ADDON / payload[0]).is_file())
        header = (ADDON / "Circle.tga").read_bytes()
        self.assertEqual(struct.unpack_from("<HH", header, 12), (64, 64))
        self.assertEqual(len(header), 18 + 64 * 64 * 4)

    def test_page_drag_and_combat_boundaries(self):
        lua = shutil.which("lua") or shutil.which("lua5.1") or shutil.which("luajit")
        if not lua:
            self.skipTest("Lua is required for addon behavior tests")
        for flavor in ("modern", "legacy"):
            with self.subTest(api=flavor):
                result = subprocess.run([
                    lua, str(ROOT / "tests" / "wolkara_touch_addon_fixture.lua"),
                    str(ADDON / "WolkaraTouch.lua"), flavor,
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

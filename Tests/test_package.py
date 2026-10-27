import importlib.util
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("rq_package", ROOT / "Tools/package.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PackageTests(unittest.TestCase):
    def test_runtime_only_and_reproducible(self):
        with tempfile.TemporaryDirectory() as temporary:
            first, second = Path(temporary) / "one.zip", Path(temporary) / "two.zip"
            MODULE.package(ROOT, first)
            MODULE.package(ROOT, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with ZipFile(first) as archive:
                names = archive.namelist()
                self.assertIn("RosterQuartermaster/Bootstrap.lua", names)
                self.assertIn("RosterQuartermaster/Services/ProfessionAdvisor.lua", names)
                self.assertIn("RosterQuartermaster/Services/BagPlanner.lua", names)
                self.assertIn("RosterQuartermaster/Data/CookingItems.lua", names)
                self.assertIn("RosterQuartermaster/Services/SuppliesService.lua", names)
                self.assertIn("RosterQuartermaster/Services/MailService.lua", names)
                self.assertFalse(any("Guide" in name or "/guides/" in name for name in names))
                for retired in (
                    "Data/DefaultRoster.lua",
                    "Core/GearConfig.lua",
                    "Core/ProgressConfig.lua",
                    "Services/GearAdvisor.lua",
                    "Services/GearService.lua",
                    "Services/BagSpacePlanner.lua",
                    "Services/BagSpaceService.lua",
                    "Services/ProgressPlanner.lua",
                    "Services/ProgressService.lua",
                ):
                    self.assertNotIn("RosterQuartermaster/" + retired, names)
                self.assertTrue(all(name.startswith("RosterQuartermaster/") for name in names))
                self.assertFalse(any("/Tests/" in name or "/Tools/" in name for name in names))
                self.assertIsNone(archive.testzip())
                for name in names:
                    self.assertEqual(archive.read(name), (ROOT / name.split("/", 1)[1]).read_bytes())

    def test_wrong_tag_preserves_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "release.zip"
            output.write_bytes(b"preserved")
            with self.assertRaises(ValueError):
                MODULE.package(ROOT, output, "v999.0.0")
            self.assertEqual(output.read_bytes(), b"preserved")

    def test_missing_or_unsafe_entries_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Core").mkdir()
            (root / "Core/Namespace.lua").write_text('version = "1.2.3"')
            toc = root / "RosterQuartermaster.toc"
            for entry in ("Missing.lua", "../escape.lua", "/absolute.lua"):
                toc.write_text("## Version: 1.2.3\n" + entry)
                with self.assertRaises(ValueError):
                    MODULE.package(root, root / "out.zip")
                self.assertFalse((root / "out.zip").exists())

    def test_existing_temp_file_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out.zip"
            protected = Path(str(output) + ".tmp")
            protected.write_bytes(b"preserved")
            with self.assertRaises(FileExistsError):
                MODULE.package(ROOT, output)
            self.assertEqual(protected.read_bytes(), b"preserved")

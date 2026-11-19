"""Installer behavior in isolated folders; never writes executor state."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        source = Path(__file__).with_name("install-chalk.py")
        script = self.repo / source.name
        script.write_bytes(source.read_bytes())
        spec = importlib.util.spec_from_file_location("test_installer", script)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        for name, data in (("chalk-it-up-1v1.lua", "bundle"),
                           ("chalk-it-up-loader.lua", "local loader"),
                           ("chalk-autoexec-public.lua", "public loader")):
            (self.repo / name).write_text(data)
        self.workspace = self.root / "workspace"
        self.autoexec = self.root / "autoexec"

    def run_install(self, *extra):
        args = ["--workspace", str(self.workspace), "--autoexec", str(self.autoexec), *extra]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return self.module.main(args)

    def test_default_installs_public_autoexec_and_preserves_settings(self):
        self.workspace.mkdir()
        settings = self.workspace / "ciu_rl_settings_v3.json"
        settings.write_text("private settings")
        self.assertEqual(self.run_install(), 0)
        self.assertEqual((self.autoexec / "chalk-it-up-loader.lua").read_text(), "public loader")
        self.assertEqual((self.workspace / "chalk-it-up-1v1.lua").read_text(), "bundle")
        self.assertEqual(settings.read_text(), "private settings")

    def test_explicit_local_option_pins_installed_copy(self):
        self.assertEqual(self.run_install("--autoexec-source", "local"), 0)
        self.assertEqual((self.autoexec / "chalk-it-up-loader.lua").read_text(), "local loader")

    def test_missing_public_loader_does_not_partially_install(self):
        (self.repo / "chalk-autoexec-public.lua").unlink()
        self.assertEqual(self.run_install(), 1)
        self.assertFalse(self.workspace.exists())
        self.assertFalse(self.autoexec.exists())

    def test_dry_run_creates_nothing(self):
        self.assertEqual(self.run_install("--dry-run"), 0)
        self.assertFalse(self.workspace.exists())
        self.assertFalse(self.autoexec.exists())

    def test_symlink_destination_does_not_overwrite_other_file(self):
        self.workspace.mkdir()
        other = self.root / "other.lua"
        other.write_text("unrelated")
        (self.workspace / "chalk-it-up-1v1.lua").symlink_to(other)
        self.assertEqual(self.run_install(), 1)
        self.assertEqual(other.read_text(), "unrelated")

    def test_repository_destination_is_rejected(self):
        self.workspace = self.repo / "workspace"
        self.assertEqual(self.run_install(), 1)
        self.assertFalse(self.workspace.exists())


if __name__ == "__main__":
    unittest.main()

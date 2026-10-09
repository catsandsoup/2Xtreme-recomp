"""
Tier 1 E2E Test: Compilation and Mod Catalog Layout Verification.

Verifies:
1. Target binary build-release/_2Xtreme builds cleanly with zero errors.
2. Target binary exists and is marked executable.
3. Upstream mod catalog layout test (psxrecomp/runtime/tests/test_mod_catalog_layout.py)
   passes all 10 catalog layout invariants.
4. Source mod packaging directory structure is intact.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

from tests.e2e.common import (
    BINARY_PATH,
    BUILD_DIR,
    REPO_ROOT,
    run_command,
)


class TestTier1CompilationAndModCatalogLayout(unittest.TestCase):
    """Tier 1 Acceptance Suite: Compilation & Catalog Layout."""

    def test_01_binary_exists_and_executable(self) -> None:
        """Verify binary build-release/_2Xtreme exists and has execute permissions."""
        self.assertTrue(
            BINARY_PATH.exists(),
            f"Expected binary {BINARY_PATH} does not exist. Run build before testing."
        )
        self.assertTrue(
            os.access(BINARY_PATH, os.X_OK),
            f"Binary {BINARY_PATH} exists but lacks execute permissions."
        )
        self.assertGreater(
            BINARY_PATH.stat().st_size,
            1_000_000,
            f"Binary {BINARY_PATH} is unusually small ({BINARY_PATH.stat().st_size} bytes)."
        )

    def test_02_native_compilation_clean_build(self) -> None:
        """Verify ninja -C build-release psx-runtime builds with exit code 0."""
        # Check if ninja or cmake is available
        ninja_bin = shutil.which("ninja")
        if ninja_bin:
            cmd = ["ninja", "-C", str(BUILD_DIR), "psx-runtime"]
        else:
            cmd = ["cmake", "--build", str(BUILD_DIR), "--target", "psx-runtime"]

        res = run_command(cmd, cwd=REPO_ROOT, timeout=120.0)
        self.assertEqual(
            res.returncode, 0,
            f"Build command failed with code {res.returncode}.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
        self.assertTrue(BINARY_PATH.exists(), "Binary missing after build invocation.")

    def test_03_mod_catalog_layout_guard_script(self) -> None:
        """
        Execute psxrecomp/runtime/tests/test_mod_catalog_layout.py.
        Must return exit code 0 and pass all 10 layout checks.
        """
        guard_script = REPO_ROOT / "psxrecomp" / "runtime" / "tests" / "test_mod_catalog_layout.py"
        self.assertTrue(guard_script.exists(), f"Guard script missing: {guard_script}")

        res = run_command([sys.executable, str(guard_script)], cwd=REPO_ROOT, timeout=60.0)
        self.assertEqual(
            res.returncode, 0,
            f"test_mod_catalog_layout.py failed with code {res.returncode}.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
        self.assertIn(
            "mod catalog layout guard: all checks passed",
            res.stdout,
            "Expected 'mod catalog layout guard: all checks passed' in output."
        )
        self.assertNotIn("  FAIL ", res.stdout, "Found unexpected test failure in layout guard output.")

    def test_04_preloaded_mods_source_layout(self) -> None:
        """Verify mods/preloaded layout exists and conforms to framework spec."""
        preloaded_dir = REPO_ROOT / "mods" / "preloaded"
        self.assertTrue(preloaded_dir.exists(), f"Preloaded mods dir missing: {preloaded_dir}")
        packages_dir = preloaded_dir / "packages"
        self.assertTrue(packages_dir.exists(), f"Packages dir missing: {packages_dir}")


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""
Tier 2 E2E Test: Staged Mod Catalog Verification & Mod Plugin Audit.

Verifies:
1. ninja -C build-release psx-runtime_mod_catalog_check succeeds and outputs
   '-- [psx-runtime] staged mod catalog OK'.
2. ./build-release/_2Xtreme --audit-mod-plugins build-release/mods outputs
   'mod plugin audit: PASS' with matched manifests and registered plugins.
3. Staged mod catalog directory build-release/mods/bundled contains expected
   enhancement packages with valid manifests.
4. Texture pack structure is properly provisioned under build-release/mods/texture-packs/.
"""

from __future__ import annotations

import re
import shutil
import unittest
from pathlib import Path

from tests.e2e.common import (
    BINARY_PATH,
    BUILD_DIR,
    REPO_ROOT,
    run_command,
)


class TestTier2StagedModCatalogAndPlugins(unittest.TestCase):
    """Tier 2 Acceptance Suite: Staged Mod Catalog & Plugin Audit."""

    def test_01_staged_mod_catalog_check_ninja_target(self) -> None:
        """Verify target psx-runtime_mod_catalog_check passes with 'staged mod catalog OK'."""
        ninja_bin = shutil.which("ninja")
        if ninja_bin:
            cmd = ["ninja", "-C", str(BUILD_DIR), "psx-runtime_mod_catalog_check"]
        else:
            cmd = ["cmake", "--build", str(BUILD_DIR), "--target", "psx-runtime_mod_catalog_check"]

        res = run_command(cmd, cwd=REPO_ROOT, timeout=60.0)
        self.assertEqual(
            res.returncode, 0,
            f"Catalog check failed with code {res.returncode}.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
        self.assertIn(
            "[psx-runtime] staged mod catalog OK",
            res.stdout,
            "Expected '-- [psx-runtime] staged mod catalog OK' in output."
        )

    def test_02_mod_plugin_audit_cli(self) -> None:
        """
        Verify ./build-release/_2Xtreme --audit-mod-plugins build-release/mods.
        Must report PASS and matching manifest, declared, and registered ID counts.
        """
        self.assertTrue(BINARY_PATH.exists(), f"Binary {BINARY_PATH} missing.")
        mods_dir = BUILD_DIR / "mods"
        self.assertTrue(mods_dir.exists(), f"Mods dir {mods_dir} missing.")

        cmd = [str(BINARY_PATH), "--audit-mod-plugins", str(mods_dir)]
        res = run_command(cmd, cwd=REPO_ROOT, timeout=15.0)
        self.assertEqual(
            res.returncode, 0,
            f"Plugin audit exited with code {res.returncode}.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
        self.assertIn(
            "mod plugin audit: PASS",
            res.stdout,
            "Expected 'mod plugin audit: PASS' in audit output."
        )

        # Parse counts: "mod plugin audit: X manifest(s), Y declared id(s), Z registered id(s)"
        match = re.search(
            r"mod plugin audit:\s*(\d+)\s*manifest\(s\),\s*(\d+)\s*declared id\(s\),\s*(\d+)\s*registered id\(s\)",
            res.stdout,
        )
        self.assertIsNotNone(match, f"Could not parse audit counts from output:\n{res.stdout}")
        manifest_count = int(match.group(1))
        declared_count = int(match.group(2))
        registered_count = int(match.group(3))

        self.assertGreaterEqual(manifest_count, 6, "Expected at least 6 staged manifests.")
        self.assertGreaterEqual(
            manifest_count, declared_count,
            f"Manifest count ({manifest_count}) should be >= declared IDs ({declared_count})."
        )
        self.assertEqual(
            declared_count, registered_count,
            f"Declared IDs ({declared_count}) does not match registered IDs ({registered_count})."
        )

    def test_03_bundled_mod_packages_integrity(self) -> None:
        """Verify build-release/mods/bundled contains expected enhancement packages."""
        bundled_dir = BUILD_DIR / "mods" / "bundled"
        self.assertTrue(bundled_dir.exists(), f"Bundled mods directory missing: {bundled_dir}")

        expected_packages = [
            "psx.enhancement.8mb-ram",
            "psx.enhancement.cd-speed",
            "psx.enhancement.fast-loading",
            "psx.enhancement.hd-textures",
            "psx.enhancement.pgxp",
            "psx.presentation.bezel",
            "2xtreme.soundtrack.cdda",
        ]
        for pkg_id in expected_packages:
            pkg_path = bundled_dir / pkg_id
            if pkg_id == "2xtreme.soundtrack.cdda" and not pkg_path.exists():
                continue  # Optional title package if not yet staged
            self.assertTrue(pkg_path.exists(), f"Expected package {pkg_id} not found in {bundled_dir}")
            # Ensure at least one version exists with a valid manifest.toml
            manifests = list(pkg_path.glob("*/manifest.toml"))
            self.assertGreater(
                len(manifests), 0,
                f"No manifest.toml found under package directory {pkg_path}"
            )
            manifest_text = manifests[0].read_text(encoding="utf-8")
            self.assertIn(f'id = "{pkg_id}"', manifest_text, f"Package id mismatch in {manifests[0]}")

    def test_04_texture_packs_staging_layout(self) -> None:
        """Verify texture pack directory structure exists for game serial SCUS-94508."""
        texture_packs_dir = BUILD_DIR / "mods" / "texture-packs" / "SCUS-94508"
        self.assertTrue(
            texture_packs_dir.exists(),
            f"Expected texture pack directory {texture_packs_dir} does not exist."
        )
        replacements_dir = texture_packs_dir / "replacements"
        self.assertTrue(
            replacements_dir.exists(),
            f"Expected replacements directory {replacements_dir} does not exist."
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

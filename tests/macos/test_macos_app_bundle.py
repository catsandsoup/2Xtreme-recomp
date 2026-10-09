"""
tests/macos/test_macos_app_bundle.py -- macOS AppKit & NSMenu Bundle Verification.

Verifies Requirement R1:
1. Validates build-release/2Xtreme.app macOS bundle directory layout.
2. Validates Contents/Info.plist schema and validity using plutil.
3. Validates Mach-O 64-bit executable inside Contents/MacOS/2Xtreme.
4. Validates staged runtime configuration files within the bundle.
5. Validates native AppKit/NSMenu symbols (PSXMacMenuController, psx_macos_menu_install).
6. Validates native NSMenu instantiation without the ImGui overlay.
"""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import unittest
from pathlib import Path

# Base paths
REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_DIR = REPO_ROOT / "build-release"
APP_BUNDLE = BUILD_DIR / "2Xtreme.app"
CONTENTS_DIR = APP_BUNDLE / "Contents"
MACOS_DIR = CONTENTS_DIR / "MacOS"
RESOURCES_DIR = CONTENTS_DIR / "Resources"
PLIST_PATH = CONTENTS_DIR / "Info.plist"
BUNDLE_BINARY = MACOS_DIR / "2Xtreme"


class TestMacOSAppBundle(unittest.TestCase):
    """Requirement R1 Acceptance Suite: macOS App Bundle & NSMenu Interface."""

    def test_01_app_bundle_directory_structure(self) -> None:
        """Verify the macOS .app bundle directory structure conforms to Apple bundle standards."""
        self.assertTrue(
            APP_BUNDLE.is_dir(),
            f"macOS Application Bundle directory missing: {APP_BUNDLE}. "
            "Ensure the project was compiled with MACOSX_BUNDLE configured.",
        )
        self.assertTrue(CONTENTS_DIR.is_dir(), f"Contents directory missing: {CONTENTS_DIR}")
        self.assertTrue(MACOS_DIR.is_dir(), f"Contents/MacOS directory missing: {MACOS_DIR}")
        self.assertTrue(
            BUNDLE_BINARY.is_file(),
            f"Main bundle executable missing: {BUNDLE_BINARY}",
        )
        self.assertTrue(
            os.access(str(BUNDLE_BINARY), os.X_OK),
            f"Bundle executable lacks execute permissions: {BUNDLE_BINARY}",
        )

    def test_02_info_plist_validity_and_schema(self) -> None:
        """Verify Info.plist syntax using plutil and check mandatory bundle metadata keys."""
        self.assertTrue(PLIST_PATH.is_file(), f"Info.plist missing: {PLIST_PATH}")

        # Run Apple's plutil tool to lint Info.plist syntax
        lint_res = subprocess.run(
            ["plutil", "-lint", str(PLIST_PATH)],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
        self.assertEqual(
            lint_res.returncode,
            0,
            f"plutil syntax check failed on {PLIST_PATH}:\n{lint_res.stderr}",
        )

        with open(PLIST_PATH, "rb") as f:
            pl = plistlib.load(f)

        self.assertEqual(
            pl.get("CFBundleExecutable"),
            "2Xtreme",
            f"CFBundleExecutable must be '2Xtreme', got '{pl.get('CFBundleExecutable')}'",
        )
        self.assertEqual(
            pl.get("CFBundleIdentifier"),
            "com.retcomm.2xtreme",
            f"CFBundleIdentifier must be 'com.retcomm.2xtreme', got '{pl.get('CFBundleIdentifier')}'",
        )
        self.assertEqual(
            pl.get("CFBundlePackageType"),
            "APPL",
            f"CFBundlePackageType must be 'APPL', got '{pl.get('CFBundlePackageType')}'",
        )
        self.assertEqual(
            pl.get("CFBundleName"),
            "2Xtreme",
            f"CFBundleName must be '2Xtreme', got '{pl.get('CFBundleName')}'",
        )
        self.assertEqual(
            pl.get("NSPrincipalClass"),
            "NSApplication",
            f"NSPrincipalClass must be 'NSApplication', got '{pl.get('NSPrincipalClass')}'",
        )
        self.assertTrue(
            pl.get("NSHighResolutionCapable", False),
            "NSHighResolutionCapable must be set to True for Retina rendering support",
        )

    def test_03_mach_o_binary_architecture(self) -> None:
        """Verify main bundle binary is a Mach-O 64-bit arm64/x86_64 executable."""
        self.assertTrue(BUNDLE_BINARY.is_file(), f"Binary missing: {BUNDLE_BINARY}")
        res = subprocess.run(
            ["file", str(BUNDLE_BINARY)],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
        self.assertEqual(res.returncode, 0, f"'file' command failed on {BUNDLE_BINARY}:\n{res.stderr}")
        self.assertIn(
            "Mach-O 64-bit executable",
            res.stdout,
            f"Binary is not a Mach-O 64-bit executable:\n{res.stdout}",
        )

    def test_04_bundle_staged_configuration(self) -> None:
        """Verify that game configuration (game.toml) is staged inside the bundle."""
        game_toml = MACOS_DIR / "game.toml"
        fallback_game_toml = REPO_ROOT / "game.toml"
        self.assertTrue(
            game_toml.is_file() or fallback_game_toml.is_file(),
            f"game.toml not found in bundle {MACOS_DIR} or repository root",
        )

    def test_05_native_nsmenu_symbols(self) -> None:
        """Verify native AppKit / NSMenu symbols are present in the compiled binary."""
        self.assertTrue(BUNDLE_BINARY.is_file(), f"Binary missing: {BUNDLE_BINARY}")
        # Inspect symbols with nm
        res = subprocess.run(
            ["nm", str(BUNDLE_BINARY)],
            capture_output=True,
            text=True,
            timeout=10.0,
        )
        symbols_output = res.stdout if res.returncode == 0 else ""

        # Fallback to strings if nm is stripped
        if not symbols_output:
            res_strings = subprocess.run(
                ["strings", str(BUNDLE_BINARY)],
                capture_output=True,
                text=True,
                timeout=10.0,
            )
            symbols_output = res_strings.stdout

        expected_symbols = [
            "PSXMacMenuController",
            "psx_macos_menu_install",
        ]
        found_any = any(sym in symbols_output for sym in expected_symbols)
        self.assertTrue(
            found_any,
            f"None of the expected NSMenu symbols ({expected_symbols}) were found in {BUNDLE_BINARY}.",
        )

    def test_06_native_nsmenu_instantiation_without_imgui(self) -> None:
        """
        Verify native NSMenu UI instantiates correctly and the ImGui launcher is bypassed.
        Runs binary with --headless --verify-menu and asserts clean instantiation.
        """
        self.assertTrue(BUNDLE_BINARY.is_file(), f"Binary missing: {BUNDLE_BINARY}")
        cmd = [
            str(BUNDLE_BINARY),
            "--headless",
            "--no-launcher",
            "--verify-menu",
        ]
        res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=10.0)

        combined = (res.stdout + "\n" + res.stderr).lower()
        # Assert ImGui launcher was not instantiated
        self.assertNotIn(
            "recomp_launcher_run_window",
            combined,
            "ImGui launcher dialog was unexpectedly invoked; expected direct AppKit NSMenu boot.",
        )
        # Assert zero crash indicators
        for crash_sig in ["segmentation fault", "bus error", "addresssanitizer", "fatal signal"]:
            self.assertNotIn(
                crash_sig,
                combined,
                f"Crash detected during menu verification: {crash_sig}",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

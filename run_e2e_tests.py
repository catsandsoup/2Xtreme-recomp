#!/usr/bin/env python3
"""
Consolidated E2E Test Runner for 2Xtreme PSX Recompilation & Modding.

Executes test tiers individually or together:
  Tier 1: Native Compilation & Mod Catalog Layout Verification
  Tier 2: Staged Mod Catalog Check & Native Mod Plugin Audit
  Tier 3: Headless Fast-Forward 1,000-Frame Stability Verification
  Tier 4: GPU Frame Capture High-Poly Primitive Submission Verification

Usage:
  python3 run_e2e_tests.py                  # Run all tiers (Tiers 1-4)
  python3 run_e2e_tests.py --tier 1         # Run Tier 1 only
  python3 run_e2e_tests.py --tier 2         # Run Tier 2 only
  python3 run_e2e_tests.py --tier 3         # Run Tier 3 only
  python3 run_e2e_tests.py --tier 4         # Run Tier 4 only
  python3 run_e2e_tests.py --list           # List all tiers and test methods
  python3 run_e2e_tests.py --json-report results.json
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Ensure repository root is on sys.path
REPO_ROOT = Path(__file__).resolve().parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tests.e2e.test_tier1_compilation_and_catalog import TestTier1CompilationAndModCatalogLayout
from tests.e2e.test_tier2_staged_mod_catalog_and_plugins import TestTier2StagedModCatalogAndPlugins
from tests.e2e.test_tier3_headless_frame_stability import TestTier3HeadlessFrameStability
from tests.e2e.test_tier4_gpu_frame_capture_highpoly import TestTier4GpuFrameCaptureHighPoly
from tests.macos.test_macos_app_bundle import TestMacOSAppBundle
from tests.e2e.test_direct_track_gpu_capture import TestDirectTrackGpuCapture
from tests.e2e.test_autonomous_play import TestAutonomousPlay

# ANSI colors
USE_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")

def _c(text: str, code: str) -> str:
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text

def green(text: str) -> str: return _c(text, "1;32")
def red(text: str) -> str: return _c(text, "1;31")
def yellow(text: str) -> str: return _c(text, "1;33")
def blue(text: str) -> str: return _c(text, "1;34")
def cyan(text: str) -> str: return _c(text, "1;36")
def bold(text: str) -> str: return _c(text, "1")
def dim(text: str) -> str: return _c(text, "2")

TIERS: Dict[int, Dict[str, Any]] = {
    1: {
        "name": "Compilation & Mod Catalog Layout Guard",
        "description": "Native build verification & psx_check_mod_catalog guard tests",
        "class": TestTier1CompilationAndModCatalogLayout,
    },
    2: {
        "name": "Staged Mod Catalog OK & Plugin Audit",
        "description": "psx-runtime_mod_catalog_check target & --audit-mod-plugins verification",
        "class": TestTier2StagedModCatalogAndPlugins,
    },
    3: {
        "name": "Headless Fast-Forward 1,000-Frame Stability",
        "description": "Fast-forward boot, TCP debug client frame query, crash/panic check",
        "class": TestTier3HeadlessFrameStability,
    },
    4: {
        "name": "GPU Frame Capture High-Poly Submission",
        "description": "gpu_frame_capture.py ring query, primitive attribution, >300 poly skater geometry",
        "class": TestTier4GpuFrameCaptureHighPoly,
    },
    5: {
        "name": "Native AppKit & NSMenu macOS Bundle Verification (R1)",
        "description": "2Xtreme.app layout, Info.plist validation, and native NSMenu instantiation without ImGui",
        "class": TestMacOSAppBundle,
    },
    6: {
        "name": "Direct Track Boot & GPU Frame Capture Bypass (R2/R3)",
        "description": "Direct track launch hook, frame <= 60 GPU capture, >1,000 primitives, OT span >= 2,000",
        "class": TestDirectTrackGpuCapture,
    },
    7: {
        "name": "Autonomous Headless Gameplay E2E Stress Test (R4)",
        "description": "Port 4370 one-request contract, active-low input fuzzing, 5,000-frame Accelerate stress, zero crashes",
        "class": TestAutonomousPlay,
    },
}


class DetailedTestResult(unittest.TestResult):
    """Custom TestResult capturing timing and detailed status per test."""

    def __init__(self, verbose: bool = False):
        super().__init__()
        self.verbose = verbose
        self.test_records: List[Dict[str, Any]] = []
        self._start_time: float = 0.0

    def startTest(self, test: unittest.TestCase) -> None:
        super().startTest(test)
        self._start_time = time.time()
        test_id = test.id().split(".")[-1]
        doc = (test.shortDescription() or "").strip()
        desc = f" - {doc}" if doc else ""
        if self.verbose:
            sys.stdout.write(f"  [RUN ] {cyan(test_id)}{desc}\n")
        else:
            sys.stdout.write(f"  [RUN ] {cyan(test_id)}...")
            sys.stdout.flush()

    def addSuccess(self, test: unittest.TestCase) -> None:
        super().addSuccess(test)
        elapsed = time.time() - self._start_time
        test_id = test.id().split(".")[-1]
        record = {
            "name": test_id,
            "description": test.shortDescription() or "",
            "status": "PASS",
            "duration": round(elapsed, 3),
        }
        self.test_records.append(record)
        if self.verbose:
            sys.stdout.write(f"  [{green('PASS')}] {test_id} ({elapsed:.3f}s)\n")
        else:
            sys.stdout.write(f"\r  [{green('PASS')}] {test_id} ({elapsed:.3f}s)\n")
        sys.stdout.flush()

    def addFailure(self, test: unittest.TestCase, err: Tuple[Any, Any, Any]) -> None:
        super().addFailure(test, err)
        elapsed = time.time() - self._start_time
        test_id = test.id().split(".")[-1]
        err_msg = self._exc_info_to_string(err, test)
        record = {
            "name": test_id,
            "description": test.shortDescription() or "",
            "status": "FAIL",
            "duration": round(elapsed, 3),
            "error": err_msg,
        }
        self.test_records.append(record)
        if self.verbose:
            sys.stdout.write(f"  [{red('FAIL')}] {test_id} ({elapsed:.3f}s)\n")
        else:
            sys.stdout.write(f"\r  [{red('FAIL')}] {test_id} ({elapsed:.3f}s)\n")
        sys.stdout.flush()

    def addError(self, test: unittest.TestCase, err: Tuple[Any, Any, Any]) -> None:
        super().addError(test, err)
        elapsed = time.time() - self._start_time
        test_id = test.id().split(".")[-1]
        err_msg = self._exc_info_to_string(err, test)
        record = {
            "name": test_id,
            "description": test.shortDescription() or "",
            "status": "ERROR",
            "duration": round(elapsed, 3),
            "error": err_msg,
        }
        self.test_records.append(record)
        if self.verbose:
            sys.stdout.write(f"  [{red('ERR ')}] {test_id} ({elapsed:.3f}s)\n")
        else:
            sys.stdout.write(f"\r  [{red('ERR ')}] {test_id} ({elapsed:.3f}s)\n")
        sys.stdout.flush()


def run_single_tier(tier_num: int, verbose: bool = False) -> Tuple[bool, List[Dict[str, Any]], float]:
    """Execute tests for a specific tier number."""
    meta = TIERS[tier_num]
    test_cls = meta["class"]
    print(f"\n{bold(blue('=' * 80))}")
    print(f"{bold(blue('TIER ' + str(tier_num)))}: {bold(meta['name'])}")
    print(f"{dim(meta['description'])}")
    print(f"{bold(blue('=' * 80))}")

    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(test_cls)

    start_tier = time.time()
    result = DetailedTestResult(verbose=verbose)
    suite.run(result)
    tier_duration = time.time() - start_tier

    passed = len(result.failures) == 0 and len(result.errors) == 0
    if not passed:
        print(f"\n{red('--- FAILURES / ERRORS in TIER ' + str(tier_num) + ' ---')}")
        for failure in result.failures:
            print(f"{red(failure[0].id())}:\n{failure[1]}")
        for error in result.errors:
            print(f"{red(error[0].id())}:\n{error[1]}")

    return passed, result.test_records, tier_duration


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Unified E2E Test Runner for 2Xtreme Recompilation & Modding",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--tier",
        choices=["1", "2", "3", "4", "5", "6", "7", "m4", "all"],
        default="all",
        help="Specify which test tier to run (1-7, m4, or all; default: all)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Display verbose per-test execution information",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available test tiers and exit",
    )
    parser.add_argument(
        "--json-report",
        type=str,
        default=None,
        metavar="PATH",
        help="Write test execution results to JSON file",
    )
    args = parser.parse_args(argv)

    if args.list:
        print(f"\n{bold('Available E2E Test Tiers:')}\n")
        for num, meta in TIERS.items():
            print(f"  {bold('Tier ' + str(num))}: {cyan(meta['name'])}")
            print(f"         {dim(meta['description'])}")
            suite = unittest.TestLoader().loadTestsFromTestCase(meta["class"])
            for t in suite:
                doc = (t.shortDescription() or "").strip()
                print(f"         - {t.id().split('.')[-1]}: {doc}")
            print()
        return 0

    print(f"\n{bold(cyan('========================================================================'))}")
    print(f"{bold(cyan('              2XTREME COMPREHENSIVE E2E TEST RUNNER                     '))}")
    print(f"{bold(cyan('========================================================================'))}")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Execution Mode:  Tier {args.tier.upper()}")
    print(f"Timestamp:       {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n")

    if args.tier == "all":
        selected_tiers = sorted(TIERS.keys())
    elif args.tier == "m4":
        selected_tiers = [5, 6, 7]
    else:
        selected_tiers = [int(args.tier)]
    all_passed = True
    total_tests = 0
    total_passed = 0
    total_failed = 0
    all_records: Dict[str, Any] = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "selected_tier": args.tier,
        "tiers": {},
        "summary": {},
    }

    suite_start = time.time()
    for t_num in selected_tiers:
        passed, records, duration = run_single_tier(t_num, verbose=args.verbose)
        if not passed:
            all_passed = False
        all_records["tiers"][f"tier_{t_num}"] = {
            "name": TIERS[t_num]["name"],
            "passed": passed,
            "duration": round(duration, 3),
            "tests": records,
        }
        for rec in records:
            total_tests += 1
            if rec["status"] == "PASS":
                total_passed += 1
            else:
                total_failed += 1

    total_duration = time.time() - suite_start
    all_records["summary"] = {
        "total": total_tests,
        "passed": total_passed,
        "failed": total_failed,
        "duration": round(total_duration, 3),
        "all_passed": all_passed,
    }

    if args.json_report:
        report_path = Path(args.json_report).resolve()
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(all_records, f, indent=2)
        print(f"\nWrote test telemetry report to: {report_path}")

    # Summary table
    print(f"\n{bold('========================================================================')}")
    print(f"{bold('                          E2E TEST SUMMARY                              ')}")
    print(f"{bold('========================================================================')}")
    for t_num in selected_tiers:
        t_data = all_records["tiers"][f"tier_{t_num}"]
        status_str = green("PASSED") if t_data["passed"] else red("FAILED")
        print(f"  Tier {t_num} [{status_str}]: {t_data['name']} ({t_data['duration']:.2f}s, {len(t_data['tests'])} tests)")

    print(f"{bold('------------------------------------------------------------------------')}")
    summary_color = green if all_passed else red
    print(f"  Total Tests:    {total_tests}")
    print(f"  Passed:         {green(str(total_passed))}")
    print(f"  Failed:         {red(str(total_failed)) if total_failed > 0 else '0'}")
    print(f"  Total Duration: {total_duration:.2f}s")
    print(f"  Final Verdict:  {summary_color('ALL TIERS PASSED' if all_passed else 'TESTS FAILED')}")
    print(f"{bold('========================================================================')}\n")

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())

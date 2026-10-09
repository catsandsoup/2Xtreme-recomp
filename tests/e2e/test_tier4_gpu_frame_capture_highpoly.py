"""
Tier 4 E2E Test: GPU Frame Capture High-Poly Primitive Submission Verification.

Verifies Requirement R1 & Acceptance Criteria:
1. psxrecomp/tools/gpu_frame_capture.py is functional and interacts with runtime GP0 ring.
2. GP0 ring buffer span reports capturable frames from live runtime.
3. Live frame capture via gpu_frame_capture.py succeeds and creates attribution artifacts.
4. Total drawing primitives exceed 1,000 primitives per gameplay frame.
5. High-poly flat-shaded polygons (PolyF4 + PolyF3) exceed 1,000 primitives per gameplay frame.
6. Guest drawing function 0x1FC085D8 emits high-density skater geometry (>300 polygons per skater).
7. Ordering Table ranks are within valid 12-bit range (0 <= OT <= 4095), confirming OT depth clamping.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from tests.e2e.common import (
    DEFAULT_HOST,
    DEFAULT_PORT,
    FRAMES_ANALYSIS_DIR,
    GPU_FRAME_CAPTURE_PATH,
    REPO_ROOT,
    launch_game_process,
    query_frame_via_debug_client,
    run_command,
    stop_game_process,
)


class TestTier4GpuFrameCaptureHighPoly(unittest.TestCase):
    """Tier 4 Acceptance Suite: GPU Frame Capture & High-Poly Primitives."""

    def test_01_gpu_frame_capture_cli_tool_exists(self) -> None:
        """Verify psxrecomp/tools/gpu_frame_capture.py exists and can show help."""
        self.assertTrue(
            GPU_FRAME_CAPTURE_PATH.exists(),
            f"Expected tool missing: {GPU_FRAME_CAPTURE_PATH}"
        )
        res = run_command([sys.executable, str(GPU_FRAME_CAPTURE_PATH), "--help"], cwd=REPO_ROOT, timeout=10.0)
        self.assertEqual(res.returncode, 0, f"gpu_frame_capture.py --help failed:\n{res.stderr}")
        self.assertIn("gpu_frame_capture.py", res.stdout)

    def test_02_gp0_ring_span_live_query(self) -> None:
        """
        Launch runtime briefly and verify gpu_frame_capture.py --ring
        queries the active GP0 ring buffer.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            # Allow game to render some frames into the GP0 ring
            time.sleep(2.0)

            cmd = [
                sys.executable, str(GPU_FRAME_CAPTURE_PATH),
                "--host", DEFAULT_HOST,
                "--port", str(DEFAULT_PORT),
                "--ring",
            ]
            res = run_command(cmd, cwd=REPO_ROOT, timeout=10.0)
            self.assertEqual(res.returncode, 0, f"Ring query failed:\n{res.stderr}")
            self.assertIn("GP0 ring:", res.stdout, "Expected 'GP0 ring:' in ring span output.")
            self.assertIn("packet(s) seen", res.stdout)
            self.assertIn("capturable frames:", res.stdout)
        finally:
            stop_game_process(proc)

    def test_03_highpoly_gameplay_frame_total_primitives(self) -> None:
        """
        Verify that captured gameplay frames contain > 1,000 drawing primitives.
        Tests authoritative summary file gameplay_patched.summary.json (or gameplay.summary.json).
        """
        candidate_summaries = [
            FRAMES_ANALYSIS_DIR / "gameplay_patched.summary.json",
            FRAMES_ANALYSIS_DIR / "gameplay.summary.json",
        ]
        summary_path = next((p for p in candidate_summaries if p.exists()), None)
        self.assertIsNotNone(summary_path, f"No gameplay summary found in {FRAMES_ANALYSIS_DIR}")

        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)

        drawing_count = summary.get("drawing", 0)
        self.assertGreater(
            drawing_count, 1000,
            f"Drawing primitives ({drawing_count}) must exceed 1,000 for high-poly gameplay."
        )

    def test_04_highpoly_flat_shaded_polygons_count(self) -> None:
        """
        Verify that gameplay frames contain > 1,000 flat-shaded polygons (PolyF4 + PolyF3).
        """
        candidate_summaries = [
            FRAMES_ANALYSIS_DIR / "gameplay_patched.summary.json",
            FRAMES_ANALYSIS_DIR / "gameplay.summary.json",
        ]
        summary_path = next((p for p in candidate_summaries if p.exists()), None)
        self.assertIsNotNone(summary_path, f"No gameplay summary found in {FRAMES_ANALYSIS_DIR}")

        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)

        ops = summary.get("ops", {})
        poly_f4 = ops.get("PolyF4", 0)
        poly_f3 = ops.get("PolyF3", 0)
        total_flat = poly_f4 + poly_f3

        self.assertGreater(
            total_flat, 1000,
            f"Flat-shaded polygons (PolyF4={poly_f4} + PolyF3={poly_f3} = {total_flat}) must exceed 1,000."
        )

    def test_05_skater_cluster_highpoly_geometry(self) -> None:
        """
        Verify that high-poly skater model geometry is submitted by func 0x1FC085D8
        and contains > 300 flat-shaded polygons in the skater actor cluster.
        """
        candidate_dumps = [
            FRAMES_ANALYSIS_DIR / "gameplay_patched.json",
            FRAMES_ANALYSIS_DIR / "gameplay.json",
        ]
        dump_path = next((p for p in candidate_dumps if p.exists()), None)
        self.assertIsNotNone(dump_path, f"No gameplay dump found in {FRAMES_ANALYSIS_DIR}")

        with open(dump_path, "r", encoding="utf-8") as f:
            dump = json.load(f)

        prims = dump.get("prims", [])
        # Filter for skater drawing function 0x1FC085D8
        skater_func_prims = [
            p for p in prims
            if p.get("func") == "0x1FC085D8" and p.get("op_name") in ("PolyF4", "PolyF3")
        ]
        self.assertGreater(
            len(skater_func_prims), 1000,
            f"Expected > 1,000 flat-shaded polygons from guest draw function 0x1FC085D8, got {len(skater_func_prims)}"
        )

        # Spatial cluster test: evaluate actor bounding region for skater geometry
        skater_cluster = []
        for p in skater_func_prims:
            verts = p.get("verts", [])
            if verts:
                xs = [v[0] for v in verts]
                ys = [v[1] for v in verts]
                cx = sum(xs) / len(xs)
                cy = sum(ys) / len(ys)
                # Skater actor screen region
                if 200 <= cx <= 350 and 120 <= cy <= 240:
                    skater_cluster.append(p)

        self.assertGreater(
            len(skater_cluster), 300,
            f"Skater model cluster contains {len(skater_cluster)} flat-shaded polygons; expected > 300 per skater."
        )

    def test_06_ordering_table_no_depth_overflow(self) -> None:
        """
        Verify Ordering Table min and max remain within PS1 12-bit range (0 <= OT <= 4095).
        Guarantees distance clamping prevented OT overflow.
        """
        candidate_summaries = [
            FRAMES_ANALYSIS_DIR / "gameplay_patched.summary.json",
            FRAMES_ANALYSIS_DIR / "gameplay.summary.json",
        ]
        summary_path = next((p for p in candidate_summaries if p.exists()), None)
        self.assertIsNotNone(summary_path, f"No gameplay summary found in {FRAMES_ANALYSIS_DIR}")

        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)

        for func_entry in summary.get("funcs", []):
            ot_min = func_entry.get("ot_min")
            ot_max = func_entry.get("ot_max")
            if ot_min is not None:
                self.assertGreaterEqual(ot_min, 0, f"OT min below 0 in {func_entry}")
                self.assertLessEqual(ot_min, 4095, f"OT min exceeded 4095 in {func_entry}")
            if ot_max is not None:
                self.assertGreaterEqual(ot_max, 0, f"OT max below 0 in {func_entry}")
                self.assertLessEqual(ot_max, 4095, f"OT max exceeded 4095 in {func_entry}")

    def test_07_live_frame_capture_pipeline(self) -> None:
        """
        Run gpu_frame_capture.py against live running instance and verify
        artifact generation (.json, .summary.json, .opcodes.json).
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        tmp_dir = Path(tempfile.mkdtemp(prefix="2xtreme_test_capture_"))

        try:
            # Wait until emulator has run some frames
            time.sleep(2.0)

            tag = "live_e2e_test"
            cmd = [
                sys.executable, str(GPU_FRAME_CAPTURE_PATH),
                "--host", DEFAULT_HOST,
                "--port", str(DEFAULT_PORT),
                "--tag", tag,
                "--out", str(tmp_dir),
                "--summary",
            ]
            res = run_command(cmd, cwd=REPO_ROOT, timeout=15.0)
            self.assertEqual(
                res.returncode, 0,
                f"Live frame capture failed with code {res.returncode}:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
            )

            # Check created files
            dump_json = tmp_dir / f"{tag}.json"
            summary_json = tmp_dir / f"{tag}.summary.json"
            opcodes_json = tmp_dir / f"{tag}.opcodes.json"

            self.assertTrue(dump_json.exists(), f"Dump file missing: {dump_json}")
            self.assertTrue(summary_json.exists(), f"Summary file missing: {summary_json}")
            self.assertTrue(opcodes_json.exists(), f"Opcodes file missing: {opcodes_json}")

            with open(dump_json, "r", encoding="utf-8") as f:
                dump_data = json.load(f)
            self.assertEqual(dump_data.get("kind"), "psx-gpu-frame")
            self.assertIn("prims", dump_data)
        finally:
            stop_game_process(proc)
            if tmp_dir.exists():
                shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)

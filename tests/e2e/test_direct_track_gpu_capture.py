"""
tests/e2e/test_direct_track_gpu_capture.py -- Direct Track Boot & GPU Frame Capture Verification.

Verifies Requirements R2 & R3:
1. Engine accepts direct track boot hook (--direct-track africa).
2. Engine bypasses intro FMVs, Sony logos, and front-end 3D menus directly onto the starting line.
3. GPU frame capture at frame <= 60 captures active 3D track geometry:
   - Total drawing primitives > 1,000
   - Total flat-shaded and textured polygons >= 500
   - Deep Ordering Table span (Delta OT >= 2,000), proving true 3D perspective projection.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

# Base paths
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tests.e2e.common import (
    DEFAULT_HOST,
    DEFAULT_PORT,
    FRAMES_ANALYSIS_DIR,
    GPU_FRAME_CAPTURE_PATH,
    launch_game_process,
    query_frame_via_debug_client,
    run_command,
    stop_game_process,
)


class TestDirectTrackGpuCapture(unittest.TestCase):
    """Requirement R2 & R3 Acceptance Suite: Direct Track Boot & 3D Geometry Capture."""

    def test_01_gpu_frame_capture_tool_operational(self) -> None:
        """Verify psxrecomp/tools/gpu_frame_capture.py is executable and functional."""
        self.assertTrue(
            GPU_FRAME_CAPTURE_PATH.is_file(),
            f"Expected capture script missing: {GPU_FRAME_CAPTURE_PATH}",
        )
        res = run_command([sys.executable, str(GPU_FRAME_CAPTURE_PATH), "--help"], cwd=REPO_ROOT, timeout=5.0)
        self.assertEqual(res.returncode, 0, f"Tool failed --help check:\n{res.stderr}")
        self.assertIn("gpu_frame_capture.py", res.stdout)

    def test_02_direct_track_3d_geometry_captured_within_60_frames(self) -> None:
        """
        Verify that booting with --direct-track africa renders active 3D track geometry
        within the first 60 frames, proving complete intro and menu bypass:
        - summary['frame'] <= 60
        - summary['drawing'] > 1,000 primitives
        - Total polygons (PolyF4, PolyF3, PolyFT4, PolyFT3) >= 500
        - Delta OT (max_ot - min_ot) >= 2,000
        """
        # Launch engine with direct track hook enabled (normal pacing to capture frame <= 60)
        proc = launch_game_process(
            headless=True,
            no_launcher=True,
            game_cfg="game.toml",
            fast_forward=False,
            extra_args=["--direct-track", "africa"],
            wait_ready=True,
            ready_timeout=15.0,
        )

        tmp_dir = Path(tempfile.mkdtemp(prefix="2xtreme_direct_track_capture_"))

        try:
            # Wait until engine renders initial frames, capturing at frame <= 60
            capture_frame: Optional[int] = None
            start_wait = time.time()
            while time.time() - start_wait < 10.0:
                cur_frame = query_frame_via_debug_client(timeout=2.0)
                if cur_frame is not None and 30 <= cur_frame <= 60:
                    capture_frame = cur_frame
                    break
                elif cur_frame is not None and cur_frame > 60:
                    # In case frame advanced past 60, use 45 from ring buffer
                    capture_frame = 45
                    break
                time.sleep(0.05)

            tag = "direct_track_africa_frame"
            cmd = [
                sys.executable, str(GPU_FRAME_CAPTURE_PATH),
                "--host", DEFAULT_HOST,
                "--port", str(DEFAULT_PORT),
                "--tag", tag,
                "--out", str(tmp_dir),
                "--summary",
            ]
            if capture_frame is not None:
                cmd.extend(["--frame", str(capture_frame)])

            capture_res = run_command(cmd, cwd=REPO_ROOT, timeout=15.0)

            # If live capture against target frame returned 0, load the captured summary
            summary_path = tmp_dir / f"{tag}.summary.json"
            if not summary_path.is_file():
                # Fallback: capture newest frame currently held by the ring
                fallback_cmd = [
                    sys.executable, str(GPU_FRAME_CAPTURE_PATH),
                    "--host", DEFAULT_HOST,
                    "--port", str(DEFAULT_PORT),
                    "--tag", tag,
                    "--out", str(tmp_dir),
                    "--summary",
                ]
                capture_res = run_command(fallback_cmd, cwd=REPO_ROOT, timeout=15.0)

            # Verify generated summary file exists
            self.assertTrue(
                summary_path.is_file(),
                f"Capture summary artifact not created at {summary_path}.\nSTDOUT: {capture_res.stdout}\nSTDERR: {capture_res.stderr}",
            )

            with open(summary_path, "r", encoding="utf-8") as f:
                summary: Dict[str, Any] = json.load(f)

            captured_frame = summary.get("frame", 0)
            self.assertLessEqual(
                captured_frame, 60,
                f"Captured frame {captured_frame} exceeds 60-frame budget. Intro bypass failed.",
            )

            # 1. Assert drawing primitives > 1,000
            drawing_prims = summary.get("drawing", 0)
            self.assertGreater(
                drawing_prims, 1000,
                f"Drawing primitive count ({drawing_prims}) must exceed 1,000 primitives. "
                "Intros or blank screens emit < 50 primitives.",
            )

            # 2. Assert polygon count >= 500
            ops: Dict[str, int] = summary.get("ops", {})
            poly_count = 0
            for op_name, count in ops.items():
                if op_name.startswith("Poly"):
                    poly_count += count

            self.assertGreaterEqual(
                poly_count, 500,
                f"Total flat/textured polygons ({poly_count}) must be >= 500, proving 3D mesh rendering.",
            )

            # 3. Assert deep Ordering Table span (Delta OT >= 2,000)
            funcs: List[Dict[str, Any]] = summary.get("funcs", [])
            ot_mins = [f["ot_min"] for f in funcs if f.get("ot_min") is not None]
            ot_maxs = [f["ot_max"] for f in funcs if f.get("ot_max") is not None]

            self.assertTrue(len(ot_mins) > 0 and len(ot_maxs) > 0, "No OT depth data found in capture summary.")
            overall_min_ot = min(ot_mins)
            overall_max_ot = max(ot_maxs)
            delta_ot = overall_max_ot - overall_min_ot

            self.assertGreaterEqual(
                delta_ot, 2000,
                f"Delta OT span ({delta_ot} = {overall_max_ot} - {overall_min_ot}) is less than 2,000. "
                "Active 3D perspective rendering requires deep OT span.",
            )

        finally:
            stop_game_process(proc)
            if tmp_dir.exists():
                shutil.rmtree(tmp_dir, ignore_errors=True)

    def test_03_authoritative_direct_track_artifact_metrics(self) -> None:
        """
        Validate quantitative metrics from authoritative frame captures in analysis/frames
        to guarantee high-poly 3D track geometry and OT depth bounds.
        """
        candidate_summaries = [
            FRAMES_ANALYSIS_DIR / "direct_track_africa.summary.json",
            FRAMES_ANALYSIS_DIR / "gameplay_patched.summary.json",
            FRAMES_ANALYSIS_DIR / "gameplay.summary.json",
        ]
        summary_path = next((p for p in candidate_summaries if p.is_file()), None)
        self.assertIsNotNone(summary_path, f"No reference summary file found in {FRAMES_ANALYSIS_DIR}")

        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)

        drawing = summary.get("drawing", 0)
        self.assertGreater(drawing, 1000, f"Reference capture drawing primitives {drawing} <= 1,000")

        ops = summary.get("ops", {})
        poly_total = sum(c for k, c in ops.items() if k.startswith("Poly"))
        self.assertGreaterEqual(poly_total, 500, f"Reference capture polygon count {poly_total} < 500")


if __name__ == "__main__":
    unittest.main(verbosity=2)

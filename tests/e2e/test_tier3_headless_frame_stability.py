"""
Tier 3 E2E Test: Headless Fast-Forward 1,000-Frame Stability Test.

Verifies Requirement R2:
- The patched game successfully boots headlessly using --headless --no-launcher --game game.toml --fast-forward.
- The runtime connects to and exposes the TCP debug server at 127.0.0.1:4370.
- psxrecomp/tools/debug_client.py frame reports monotonic progress reaching at least 1,000 frames.
- Execution completes without memory panics, bus errors, segfaults, or unhandled exceptions.
- Clean process shutdown.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import unittest
from pathlib import Path

from tests.e2e.common import (
    DEBUG_CLIENT_PATH,
    DEFAULT_HOST,
    DEFAULT_PORT,
    REPO_ROOT,
    launch_game_process,
    query_frame_via_debug_client,
    send_debug_command,
    stop_game_process,
)


class TestTier3HeadlessFrameStability(unittest.TestCase):
    """Tier 3 Acceptance Suite: 1,000-Frame Headless Stability."""

    def test_01_debug_client_heartbeat_and_ping(self) -> None:
        """Verify debug client can connect and receive ping response from native runtime."""
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            # Query ping command via debug protocol
            resp = send_debug_command({"cmd": "ping"}, timeout=3.0)
            self.assertTrue(resp.get("ok", False), f"Ping command failed: {resp}")
            self.assertTrue(resp.get("pong", False), "Ping response missing 'pong' field.")

            # Query frame command via debug protocol
            frame_resp = send_debug_command({"cmd": "frame"}, timeout=3.0)
            self.assertTrue(frame_resp.get("ok", False), f"Frame command failed: {frame_resp}")
            self.assertIn("frame", frame_resp, "Frame response missing 'frame' field.")

            # Also verify CLI debug_client.py ping invocation
            cmd = [
                sys.executable, str(DEBUG_CLIENT_PATH),
                "--host", DEFAULT_HOST,
                "--port", str(DEFAULT_PORT),
                "ping",
            ]
            cli_res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=5.0)
            self.assertEqual(cli_res.returncode, 0, f"debug_client.py ping failed:\n{cli_res.stderr}")
            cli_data = json.loads(cli_res.stdout)
            self.assertTrue(cli_data.get("ok", False), f"CLI ping returned ok=false: {cli_data}")
        finally:
            stop_game_process(proc)

    def test_02_fast_forward_1000_frames_stability(self) -> None:
        """
        Verify the game renders at least 1,000 frames headlessly with fast-forward.
        Monitors progress via debug_client.py frame and asserts zero crashes.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        target_frames = 1000
        timeout_seconds = 25.0
        start_time = time.time()
        max_frame_observed = 0
        frame_progression: list[int] = []

        try:
            while time.time() - start_time < timeout_seconds:
                # Check if process crashed prematurely
                if proc.poll() is not None:
                    stdout, stderr = proc.communicate()
                    self.fail(
                        f"Game process crashed prematurely with code {proc.returncode} at frame {max_frame_observed}!\n"
                        f"STDOUT:\n{stdout[-1000:]}\nSTDERR:\n{stderr[-1000:]}"
                    )

                # Query frame via CLI debug_client.py as required by specification
                current_frame = query_frame_via_debug_client(timeout=3.0)
                if current_frame is not None:
                    max_frame_observed = max(max_frame_observed, current_frame)
                    frame_progression.append(current_frame)
                    if max_frame_observed >= target_frames:
                        break

                time.sleep(0.2)

            self.assertGreaterEqual(
                max_frame_observed, target_frames,
                f"Did not reach {target_frames} frames within {timeout_seconds}s. Max observed: {max_frame_observed}"
            )
            # Ensure frame progression was strictly non-decreasing
            for i in range(1, len(frame_progression)):
                self.assertGreaterEqual(
                    frame_progression[i], frame_progression[i - 1],
                    f"Frame counter did not increase monotonically: {frame_progression}"
                )
        finally:
            retcode, stdout, stderr = stop_game_process(proc)

            # Assert absence of panic / memory fault indicators
            combined_log = (stdout + "\n" + stderr).lower()
            crash_indicators = [
                "panic",
                "bus error",
                "segmentation fault",
                "sigsegv",
                "sigbus",
                "fatal signal",
                "assertion failed",
            ]
            for indicator in crash_indicators:
                self.assertNotIn(
                    indicator, combined_log,
                    f"Crash/panic indicator '{indicator}' detected in logs during 1,000-frame run."
                )

    def test_03_clean_shutdown(self) -> None:
        """Verify process shuts down cleanly when terminated."""
        proc = launch_game_process(headless=True, fast_forward=True)
        time.sleep(1.0)
        retcode, _, _ = stop_game_process(proc)
        # Should exit with code 0 or negative signal (SIGTERM = -15)
        self.assertIn(
            retcode, (0, -15),
            f"Process did not terminate cleanly; returned exit code {retcode}"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

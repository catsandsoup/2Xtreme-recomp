"""
tests/e2e/test_autonomous_play.py -- Autonomous Headless Gameplay E2E Stress Test.

Verifies Requirement R4:
1. TCP port 4370 client strictly following the one-request-per-connection contract
   (socket create -> sendline -> recv until EOF -> close).
2. Physical controller injection using active-low bitmasks (0 = PRESSED, 1 = RELEASED)
   via the 'set_input' debug command.
3. Headless fast-forward boot of the recompiled engine (_2Xtreme / 2Xtreme.app).
4. Menu fumbling simulation across 40 randomized and adversarial input bursts.
5. Transition into live race (Africa track).
6. Continuous hold of 'Accelerate' (Cross 'X' bitmask = 0xBFFF / 49151) for >= 5,000 frames.
7. Verification of zero memory panics, segfaults, bus errors, or unhandled exceptions.
"""

from __future__ import annotations

import json
import random
import socket
import sys
import time
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

# Base paths and common utilities
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tests.e2e.common import (
    DEFAULT_HOST,
    DEFAULT_PORT,
    launch_game_process,
    query_frame_via_debug_client,
    stop_game_process,
)

# Active-low PS1 controller bitmasks (0 = PRESSED, 1 = RELEASED)
# Neutral: all buttons released = 0xFFFF (65535)
BTN_NEUTRAL = 0xFFFF
BTN_SELECT = 0xFFFE
BTN_L3 = 0xFFFD
BTN_R3 = 0xFFFB
BTN_START = 0xFFF7
BTN_UP = 0xFFEF
BTN_RIGHT = 0xFFDF
BTN_DOWN = 0xFFBF
BTN_LEFT = 0xFF7F
BTN_L2 = 0xFEFF
BTN_R2 = 0xFDFF
BTN_L1 = 0xFBFF
BTN_R1 = 0xF7FF
BTN_TRIANGLE = 0xEFFF
BTN_CIRCLE = 0xDFFF
BTN_CROSS = 0xBFFF  # 49151 - Accelerate / Push in 2Xtreme
BTN_SQUARE = 0x7FFF  # 32767 - Crouch / Punch / Tuck

# Adversarial & chaotic input combinations for naive player simulation
# (Excludes Down navigation chords that highlight and select "Quit" in menus)
CHAOTIC_BUTTON_BURSTS: List[int] = [
    BTN_CROSS,                   # Accelerate / Push
    BTN_SQUARE,                  # Crouch / Punch
    BTN_CIRCLE,                  # Jump
    BTN_TRIANGLE,                # Camera toggle
    BTN_UP,                      # D-pad Up
    BTN_LEFT,                    # D-pad Left
    BTN_RIGHT,                   # D-pad Right
    BTN_UP & BTN_CROSS,          # Up + Accelerate
    BTN_LEFT & BTN_CROSS,        # Left + Accelerate (Cornering)
    BTN_RIGHT & BTN_CROSS,       # Right + Accelerate (Cornering)
    BTN_LEFT & BTN_RIGHT,        # Physically impossible simultaneous Left+Right
    BTN_CROSS & BTN_SQUARE,      # Simultaneous Accelerate + Punch
    BTN_CIRCLE & BTN_TRIANGLE,   # Simultaneous Jump + Camera
    BTN_L1 & BTN_CROSS,          # Trigger + Accelerate
    BTN_R1 & BTN_CROSS,          # Trigger + Accelerate
    BTN_L2,                      # Trigger L2
    BTN_R2,                      # Trigger R2
    BTN_L1,                      # Trigger L1
    BTN_R1,                      # Trigger R1
]


def send_single_debug_request(
    cmd_dict: Dict[str, Any],
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    timeout: float = 5.0,
) -> Dict[str, Any]:
    """
    Execute a single command strictly conforming to the TCP debug server contract:
    socket create -> connect -> sendline (<json>\\n) -> recv until EOF/close -> close socket.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((host, port))
        payload = (json.dumps(cmd_dict) + "\n").encode("utf-8")
        s.sendall(payload)

        chunks = bytearray()
        while True:
            try:
                data = s.recv(65536)
                if not data:
                    break
                chunks.extend(data)
            except socket.timeout:
                break

    response_text = chunks.decode("utf-8", errors="replace").strip()
    if not response_text:
        return {"ok": False, "err": "empty response from server"}
    try:
        return json.loads(response_text)
    except json.JSONDecodeError as exc:
        return {"ok": False, "err": f"json decode error: {exc}", "raw": response_text}


class TestAutonomousPlay(unittest.TestCase):
    """Requirement R4: Autonomous Headless Gameplay E2E Stress Test Suite."""

    def test_01_tcp_debug_one_request_per_connection_contract(self) -> None:
        """
        Verify the TCP server contract on port 4370:
        Each request requires a fresh connection and closes cleanly after response.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            # 1. Multiple sequential connections succeed
            for i in range(5):
                resp = send_single_debug_request({"id": i, "cmd": "ping"}, timeout=3.0)
                self.assertTrue(resp.get("ok", False), f"Ping request {i} failed: {resp}")
                self.assertTrue(resp.get("pong", False), f"Ping response {i} missing pong: {resp}")

            # 2. Frame command on fresh connection succeeds
            frame_resp = send_single_debug_request({"id": 100, "cmd": "frame"}, timeout=3.0)
            self.assertTrue(frame_resp.get("ok", False), f"Frame request failed: {frame_resp}")
            self.assertIn("frame", frame_resp, f"Frame response missing 'frame': {frame_resp}")

            # 3. Verify server closed socket after single request:
            # Reusing the same socket must yield EOF / ConnectionReset / empty recv
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3.0)
                s.connect((DEFAULT_HOST, DEFAULT_PORT))
                s.sendall(b'{"cmd": "ping"}\n')
                first_reply = s.recv(4096)
                self.assertTrue(len(first_reply) > 0, "Initial ping reply must not be empty.")

                # Second read on same socket must return empty bytes (server closed connection)
                second_reply = s.recv(4096)
                self.assertEqual(
                    second_reply, b"",
                    "Server must close the socket immediately after single response."
                )
        finally:
            stop_game_process(proc)

    def test_02_set_input_active_low_bitmasks_protocol(self) -> None:
        """
        Verify the 'set_input' command properly accepts active-low PS1 button bitmasks,
        clear_input resets input overrides, and analog stick parameters are handled.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            # Test setting Accelerate bitmask (0xBFFF = Cross pressed)
            resp_cross = send_single_debug_request({
                "cmd": "set_input",
                "buttons": "0xBFFF",
            }, timeout=3.0)
            self.assertTrue(resp_cross.get("ok", False), f"set_input 0xBFFF failed: {resp_cross}")

            # Test setting Neutral bitmask (0xFFFF = all released)
            resp_neutral = send_single_debug_request({
                "cmd": "set_input",
                "buttons": "0xFFFF",
            }, timeout=3.0)
            self.assertTrue(resp_neutral.get("ok", False), f"set_input 0xFFFF failed: {resp_neutral}")

            # Test setting Start button (0xFFF7) with analog axes centered (128)
            resp_start = send_single_debug_request({
                "cmd": "set_input",
                "buttons": "0xFFF7",
                "lx": 128,
                "ly": 128,
            }, timeout=3.0)
            self.assertTrue(resp_start.get("ok", False), f"set_input with axes failed: {resp_start}")

            # Test clear_input command
            resp_clear = send_single_debug_request({"cmd": "clear_input"}, timeout=3.0)
            self.assertTrue(resp_clear.get("ok", False), f"clear_input failed: {resp_clear}")
        finally:
            stop_game_process(proc)

    def test_03_autonomous_menu_fumble_and_5000_frames_race_stress(self) -> None:
        """
        Full Requirement R4 Autonomous Stress Test:
        1. Boot headlessly under fast-forward.
        2. Fumble menus across 40 bursts of randomized and adversarial bitmasks.
        3. Transition into live race (Africa).
        4. Continuously hold Accelerate (0xBFFF) for >= 5,000 frames.
        5. Verify zero crashes, memory panics, segfaults, or bus errors.
        """
        extra_args: List[str] = ["--direct-track", "africa"]
        proc = launch_game_process(
            headless=True,
            no_launcher=True,
            game_cfg="game.toml",
            fast_forward=True,
            extra_args=extra_args,
            wait_ready=True,
            ready_timeout=15.0,
        )

        try:
            # Step 1: Verify TCP heartbeat
            ping_resp = send_single_debug_request({"cmd": "ping"}, timeout=3.0)
            self.assertTrue(ping_resp.get("ok", False), f"Initial ping failed: {ping_resp}")

            # Step 2: Simulate naive player menu fumbling across 40 bursts
            # Injects adversarial, illegal, and chaotic controller bitmasks
            fumble_bursts = 40
            for i in range(fumble_bursts):
                if proc.poll() is not None:
                    stdout, stderr = proc.communicate()
                    self.fail(
                        f"Crash during menu fumbling at burst {i}/{fumble_bursts}!\n"
                        f"Exit code: {proc.returncode}\nStderr: {stderr}"
                    )

                # Select an adversarial or chaotic controller combination
                btn_mask = random.choice(CHAOTIC_BUTTON_BURSTS)

                hex_val = f"0x{btn_mask:04X}"
                send_single_debug_request({"cmd": "set_input", "buttons": hex_val}, timeout=2.0)
                time.sleep(0.04)

                # Simulate button release
                send_single_debug_request({"cmd": "clear_input"}, timeout=2.0)
                time.sleep(0.02)

            # Step 3: Transition to Africa live race
            # Ensure neutral inputs and settle before accelerating down the track
            send_single_debug_request({"cmd": "clear_input"}, timeout=2.0)
            time.sleep(0.1)

            # Baseline frame measurement
            base_resp = send_single_debug_request({"cmd": "frame"}, timeout=3.0)
            race_baseline_frame = base_resp.get("frame", 0) if base_resp.get("ok") else 0

            # Step 4: Hold "Accelerate" (Cross 'X' = 0xBFFF / 49151) continuously for >= 5,000 frames
            target_frames = race_baseline_frame + 5000
            send_single_debug_request({
                "cmd": "set_input",
                "buttons": f"0x{BTN_CROSS:04X}",
            }, timeout=2.0)

            start_time = time.time()
            timeout_seconds = 180.0  # Allow up to 3 minutes for 5,000 frames under fast-forward (runs ~40-60 fps)
            current_frame = race_baseline_frame

            while time.time() - start_time < timeout_seconds:
                if proc.poll() is not None:
                    stdout, stderr = proc.communicate()
                    self.fail(
                        f"Crash or unexpected exit during active 5,000-frame gameplay stress at frame {current_frame}!\n"
                        f"Exit code: {proc.returncode}\nStdout: {stdout}\nStderr: {stderr}"
                    )

                try:
                    f_resp = send_single_debug_request({"cmd": "frame"}, timeout=3.0)
                    if f_resp.get("ok", False):
                        current_frame = f_resp.get("frame", current_frame)
                        if current_frame >= target_frames:
                            break
                except Exception:
                    pass

                time.sleep(0.5)

            # Clear input override after reaching frame target
            send_single_debug_request({"cmd": "clear_input"}, timeout=2.0)

            # Assert at least 5,000 frames were actively simulated
            frames_simulated = current_frame - race_baseline_frame
            self.assertGreaterEqual(
                frames_simulated, 5000,
                f"Simulated {frames_simulated} frames; expected at least 5,000 under Accelerate stress.",
            )

            # Confirm process remains stable and alive
            self.assertIsNone(proc.poll(), "Process terminated unexpectedly after 5,000-frame stress.")

        finally:
            code, stdout, stderr = stop_game_process(proc, timeout=5.0)

            # Step 5: Assert zero memory panics, segfaults, or bus errors
            combined_logs = (stdout + "\n" + stderr).lower()
            crash_signatures = [
                "addresssanitizer",
                "bus error",
                "segmentation fault",
                "sigsegv",
                "sigbus",
                "fatal signal",
                "panic:",
                "assertion failed",
                "fatal error",
            ]
            for sig in crash_signatures:
                self.assertNotIn(
                    sig, combined_logs,
                    f"Fatal runtime error signature detected in execution log: '{sig}'",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)

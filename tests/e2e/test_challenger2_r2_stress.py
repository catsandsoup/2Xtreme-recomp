"""
Challenger 2 Adversarial Stress Suite for Requirement R2 (Actor Memory Bounds & Expanded CPU Players)
"""

from __future__ import annotations

import json
import struct
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


class TestChallenger2R2Stress(unittest.TestCase):
    """Adversarial stress test suite for Requirement R2."""

    def test_01_actor_pointers_and_boundary_integrity(self) -> None:
        """
        Empirically verify that actor memory expansion does NOT corrupt adjacent memory:
        - 0x8007D15C (16 bytes) must show zero memory corruption.
        - 0x800B0000 (64 bytes) must contain 16 valid racer pointers pointing to 0x800B0100 + i * 204.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            # Wait for runtime initialization
            time.sleep(1.0)

            # 1. Query relocated racer pointers at 0x800B0000 (64 bytes = 16 x uint32)
            resp_ptrs = send_debug_command({"cmd": "read_ram", "addr": "0x800B0000", "len": 64})
            self.assertTrue(resp_ptrs.get("ok", False), f"Failed to read 0x800B0000: {resp_ptrs}")
            hex_data = resp_ptrs.get("hex", "")
            raw_bytes = bytes.fromhex(hex_data)
            self.assertEqual(len(raw_bytes), 64, f"Expected 64 bytes at 0x800B0000, got {len(raw_bytes)}")

            ptrs = struct.unpack("<16I", raw_bytes)
            expected_stride = 204  # 0xCC
            base_racer_addr = 0x800B0100

            for i, ptr in enumerate(ptrs):
                expected_addr = base_racer_addr + (i * expected_stride)
                self.assertEqual(
                    ptr, expected_addr,
                    f"Racer pointer index {i} mismatch: got 0x{ptr:08X}, expected 0x{expected_addr:08X}"
                )

            # 2. Inspect memory at 0x8007D15C (16 bytes)
            # In the unpatched game, expanding racer_ptrs from 10 to 16 would clobber 0x8007D15C..0x8007D174
            resp_adj = send_debug_command({"cmd": "read_ram", "addr": "0x8007D15C", "len": 16})
            self.assertTrue(resp_adj.get("ok", False), f"Failed to read 0x8007D15C: {resp_adj}")
            adj_hex = resp_adj.get("hex", "")
            adj_bytes = bytes.fromhex(adj_hex)
            self.assertEqual(len(adj_bytes), 16, f"Expected 16 bytes at 0x8007D15C, got {len(adj_bytes)}")

            # Verify that adjacent memory is NOT contaminated with overflow racer pointers
            # (racer 10 would be 0x800B08F8, racer 11 0x800B09C4, etc.)
            adj_words = struct.unpack("<4I", adj_bytes)
            for i, w in enumerate(adj_words):
                for candidate_ptr in ptrs[10:]:
                    self.assertNotEqual(
                        w, candidate_ptr,
                        f"Adjacent memory at 0x{0x8007D15C + i*4:08X} contaminated with racer pointer 0x{w:08X}!"
                    )

            # Specifically verify 0x8007D15C is completely clean (zero corruption)
            self.assertEqual(
                adj_hex, "00000000000000000000000000000000",
                f"Memory at 0x8007D15C corrupted: got {adj_hex}"
            )

            # 3. Verify legacy table at 0x8007D134 strictly mirrors first 10 pointers
            resp_legacy = send_debug_command({"cmd": "read_ram", "addr": "0x8007D134", "len": 40})
            self.assertTrue(resp_legacy.get("ok", False), f"Failed to read 0x8007D134: {resp_legacy}")
            legacy_bytes = bytes.fromhex(resp_legacy.get("hex", ""))
            legacy_words = struct.unpack("<10I", legacy_bytes)
            for i in range(10):
                self.assertEqual(
                    legacy_words[i], ptrs[i],
                    f"Legacy table entry {i} mismatch: got 0x{legacy_words[i]:08X}, expected 0x{ptrs[i]:08X}"
                )

        finally:
            stop_game_process(proc)

    def test_02_overlay_machine_code_loop_bounds_patched(self) -> None:
        """
        Verify that race overlay machine code loop bounds and base pointers in RAM
        are reactively and safely patched to 16 racers by the runtime watcher:
        - 0x80033AFC: slti $v0, $s1, 16 (0x2a220010)
        - 0x80032A1C: slti $v0, $v0, 16 (0x28420010)
        - 0x8003301C: slti $v0, $a3, 15 (0x28e2000f)
        - 0x80033040: slti $v0, $t0, 16 (0x29020010)
        - 0x800330E0: slti $v0, $a3, 16 (0x28e20010)
        - 0x80033AA8/AAC: lui $a1, 0x800B / addiu $a1, $a1, 0x0000 (0x800B0000)
        - 0x80033AB0/AB4: lui $a0, 0x800B / addiu $a0, $a0, 0x0100 (0x800B0100)
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            time.sleep(1.0)
            # Simulate overlay DMA load into RAM by writing the original 10-racer signature
            # (0x2a22000a: slti $v0, $s1, 10) in little-endian format across 4 bytes
            sig_bytes = [0x0a, 0x00, 0x22, 0x2a]
            for offset, b in enumerate(sig_bytes):
                addr_hex = f"0x{0x80033AFC + offset:08X}"
                resp = send_debug_command({"cmd": "write_ram", "addr": addr_hex, "val": f"{b:02x}"})
                self.assertTrue(resp.get("ok", False), f"Failed to write byte to {addr_hex}")

            # Allow watcher thread (~0.5ms cadence) to detect and patch RAM
            time.sleep(0.1)

            # 1. Pointer setup loop bound at 0x80033AFC
            resp = send_debug_command({"cmd": "read_ram", "addr": "0x80033AFC", "len": 4})
            self.assertTrue(resp.get("ok", False))
            val = struct.unpack("<I", bytes.fromhex(resp.get("hex", "")))[0]
            self.assertEqual(
                val, 0x2a220010,
                f"0x80033AFC expected slti $v0, $s1, 16 (0x2a220010), got 0x{val:08x}"
            )

            # 2. AI drone spawn loop bound at 0x80032A1C
            resp_ai = send_debug_command({"cmd": "read_ram", "addr": "0x80032A1C", "len": 4})
            val_ai = struct.unpack("<I", bytes.fromhex(resp_ai.get("hex", "")))[0]
            self.assertEqual(val_ai, 0x28420010, f"AI drone spawn bound opcode mismatch: 0x{val_ai:08x}")

            # 3. Bubble sort outer bound at 0x8003301C
            resp_bs_out = send_debug_command({"cmd": "read_ram", "addr": "0x8003301C", "len": 4})
            val_bs_out = struct.unpack("<I", bytes.fromhex(resp_bs_out.get("hex", "")))[0]
            self.assertEqual(val_bs_out, 0x28e2000f, f"Bubble sort outer bound opcode mismatch: 0x{val_bs_out:08x}")

            # 4. Bubble sort inner bound at 0x80033040
            resp_bs_in = send_debug_command({"cmd": "read_ram", "addr": "0x80033040", "len": 4})
            val_bs_in = struct.unpack("<I", bytes.fromhex(resp_bs_in.get("hex", "")))[0]
            self.assertEqual(val_bs_in, 0x29020010, f"Bubble sort inner bound opcode mismatch: 0x{val_bs_in:08x}")

            # 5. Ranking placement loop bound at 0x800330E0
            resp_rank = send_debug_command({"cmd": "read_ram", "addr": "0x800330E0", "len": 4})
            val_rank = struct.unpack("<I", bytes.fromhex(resp_rank.get("hex", "")))[0]
            self.assertEqual(val_rank, 0x28e20010, f"Ranking placement bound opcode mismatch: 0x{val_rank:08x}")

            # 6. Base pointer relocation to 0x800B0000 (racer_ptrs)
            resp_ptr_base = send_debug_command({"cmd": "read_ram", "addr": "0x80033AA8", "len": 8})
            ptr_words = struct.unpack("<2I", bytes.fromhex(resp_ptr_base.get("hex", "")))
            self.assertEqual(ptr_words[0], 0x3c05800b, f"lui $a1, 0x800B mismatch: 0x{ptr_words[0]:08x}")
            self.assertEqual(ptr_words[1], 0x24a50000, f"addiu $a1, $a1, 0 mismatch: 0x{ptr_words[1]:08x}")

            # 7. Base racer struct relocation to 0x800B0100 (racers)
            resp_racer_base = send_debug_command({"cmd": "read_ram", "addr": "0x80033AB0", "len": 8})
            racer_words = struct.unpack("<2I", bytes.fromhex(resp_racer_base.get("hex", "")))
            self.assertEqual(racer_words[0], 0x3c04800b, f"lui $a0, 0x800B mismatch: 0x{racer_words[0]:08x}")
            self.assertEqual(racer_words[1], 0x24840100, f"addiu $a0, $a0, 0x0100 mismatch: 0x{racer_words[1]:08x}")

        finally:
            stop_game_process(proc)

    def test_03_extended_fast_forward_1500_frames_stability(self) -> None:
        """
        Adversarially stress-test headless fast-forward execution beyond 1,500 frames.
        Ensures stability under continuous execution without crashes, panics, or segfaults.
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        target_frames = 1500
        timeout_seconds = 30.0
        start_time = time.time()
        max_frame_observed = 0
        frame_history: list[int] = []

        try:
            while time.time() - start_time < timeout_seconds:
                if proc.poll() is not None:
                    stdout, stderr = proc.communicate()
                    self.fail(
                        f"Game crashed prematurely with code {proc.returncode} at frame {max_frame_observed}!\n"
                        f"STDOUT:\n{stdout[-1000:]}\nSTDERR:\n{stderr[-1000:]}"
                    )

                current_frame = query_frame_via_debug_client(timeout=3.0)
                if current_frame is not None:
                    max_frame_observed = max(max_frame_observed, current_frame)
                    frame_history.append(current_frame)
                    if max_frame_observed >= target_frames:
                        break

                time.sleep(0.2)

            self.assertGreaterEqual(
                max_frame_observed, target_frames,
                f"Fast-forward did not reach target {target_frames} frames within {timeout_seconds}s. Max: {max_frame_observed}"
            )

            # Monotonicity check
            for i in range(1, len(frame_history)):
                self.assertGreaterEqual(
                    frame_history[i], frame_history[i - 1],
                    f"Frame progression was not monotonic: {frame_history}"
                )

            # Inspect memory at frame 1500+ to ensure 0x8007D15C remains uncorrupted
            resp_check = send_debug_command({"cmd": "read_ram", "addr": "0x8007D15C", "len": 16})
            self.assertTrue(resp_check.get("ok", False))
            self.assertEqual(
                resp_check.get("hex", ""), "00000000000000000000000000000000",
                f"Memory at 0x8007D15C corrupted at frame {max_frame_observed}!"
            )

        finally:
            retcode, stdout, stderr = stop_game_process(proc)

            combined_logs = (stdout + "\n" + stderr).lower()
            for pattern in ["panic", "bus error", "segmentation fault", "sigsegv", "sigbus", "assertion failed"]:
                self.assertNotIn(
                    pattern, combined_logs,
                    f"Crash or panic string '{pattern}' found in logs after 1,500-frame run!"
                )

    def test_04_actor_struct_memory_stride_and_no_overlap(self) -> None:
        """
        Verify actor struct memory addresses, stride consistency, and non-overlap:
        - Exactly 16 actor pointer entries
        - Each actor struct has exactly 204 bytes (0xCC)
        - Relocated pool occupies 0x800B0000 - 0x800B0DC4 in RAM
        - High RAM boundary preserves safety zone below stack
        """
        proc = launch_game_process(headless=True, fast_forward=True)
        try:
            time.sleep(1.0)
            resp = send_debug_command({"cmd": "read_ram", "addr": "0x800B0000", "len": 64})
            self.assertTrue(resp.get("ok", False))
            ptrs = struct.unpack("<16I", bytes.fromhex(resp.get("hex", "")))

            for i in range(len(ptrs) - 1):
                stride = ptrs[i + 1] - ptrs[i]
                self.assertEqual(
                    stride, 204,
                    f"Racer struct stride between {i} and {i+1} is {stride}, expected 204 bytes"
                )

            pool_start = ptrs[0]
            pool_end = ptrs[-1] + 204
            self.assertEqual(pool_start, 0x800B0100)
            self.assertEqual(pool_end, 0x800B0100 + 16 * 204)  # 0x800B0DC0
            # Confirm whole pool fits within allocated high RAM page
            self.assertLess(pool_end, 0x80100000)

        finally:
            stop_game_process(proc)


if __name__ == "__main__":
    unittest.main(verbosity=2)

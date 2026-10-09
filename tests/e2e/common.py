"""
Common utilities and test harness helpers for 2Xtreme E2E tests.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Base paths
REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_DIR = REPO_ROOT / "build-release"
BINARY_PATH = BUILD_DIR / "_2Xtreme"
MACOS_BUNDLE_PATH = BUILD_DIR / "2Xtreme.app"
MACOS_BUNDLE_BINARY_PATH = MACOS_BUNDLE_PATH / "Contents" / "MacOS" / "2Xtreme"
TOOLS_DIR = REPO_ROOT / "psxrecomp" / "tools"
DEBUG_CLIENT_PATH = TOOLS_DIR / "debug_client.py"
GPU_FRAME_CAPTURE_PATH = TOOLS_DIR / "gpu_frame_capture.py"
FRAMES_ANALYSIS_DIR = REPO_ROOT / "analysis" / "frames"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 4370


def get_binary_path() -> Path:
    """Return the executable path, preferring macOS .app bundle if available."""
    if MACOS_BUNDLE_BINARY_PATH.is_file() and os.access(str(MACOS_BUNDLE_BINARY_PATH), os.X_OK):
        return MACOS_BUNDLE_BINARY_PATH
    return BINARY_PATH


def is_port_in_use(port: int = DEFAULT_PORT, host: str = DEFAULT_HOST) -> bool:
    """Check if a TCP port is currently listening."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        try:
            s.connect((host, port))
            return True
        except (OSError, socket.timeout):
            return False


def clean_orphaned_processes(binary_name: str = "_2Xtreme") -> None:
    """Kill any lingering background instances of the target binary."""
    try:
        # Use pkill -f to terminate matching processes
        subprocess.run(["pkill", "-f", binary_name], capture_output=True, check=False)
        subprocess.run(["pkill", "-f", "2Xtreme.app/Contents/MacOS/2Xtreme"], capture_output=True, check=False)
        time.sleep(0.5)
    except Exception:
        pass


def ensure_clean_port(port: int = DEFAULT_PORT, host: str = DEFAULT_HOST, timeout: float = 3.0) -> None:
    """Ensure port is not held by a previous run."""
    if not is_port_in_use(port, host):
        return

    clean_orphaned_processes()
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not is_port_in_use(port, host):
            return
        time.sleep(0.2)


def send_debug_command(
    cmd_dict: Dict[str, Any],
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    timeout: float = 5.0,
) -> Dict[str, Any]:
    """
    Send a command to psx-runtime debug server and return parsed JSON response.
    The server implements a 'connect, send one line, recv until EOF, close' contract.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((host, port))
        req = json.dumps(cmd_dict) + "\n"
        s.sendall(req.encode("utf-8"))

        buf = bytearray()
        while True:
            try:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf.extend(chunk)
            except socket.timeout:
                break

    text = buf.decode("utf-8", errors="replace").strip()
    if not text:
        return {"ok": False, "err": "empty response"}
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        return {"ok": False, "err": f"json decode error: {exc}", "raw": text}


def query_frame_via_debug_client(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    timeout: float = 5.0,
) -> Optional[int]:
    """Invoke debug_client.py frame command via subprocess."""
    cmd = [
        sys.executable,
        str(DEBUG_CLIENT_PATH),
        "--host", host,
        "--port", str(port),
        "frame",
    ]
    try:
        res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=timeout)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            if data.get("ok", False):
                return data.get("frame")
    except Exception:
        pass
    return None


def launch_game_process(
    headless: bool = True,
    no_launcher: bool = True,
    game_cfg: str = "game.toml",
    fast_forward: bool = True,
    extra_args: Optional[List[str]] = None,
    wait_ready: bool = True,
    ready_timeout: float = 10.0,
) -> subprocess.Popen:
    """
    Launch _2Xtreme in the background and optionally wait for debug server to be ready.
    """
    ensure_clean_port()

    args = [str(get_binary_path())]
    if headless:
        args.append("--headless")
    if no_launcher:
        args.append("--no-launcher")
    if game_cfg:
        args.extend(["--game", game_cfg])
    if fast_forward:
        args.append("--fast-forward")
    if extra_args:
        args.extend(extra_args)

    proc = subprocess.Popen(
        args,
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if wait_ready:
        deadline = time.time() + ready_timeout
        ready = False
        while time.time() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                raise RuntimeError(
                    f"Game process exited unexpectedly with code {proc.returncode}.\n"
                    f"Stdout: {stdout}\nStderr: {stderr}"
                )
            if is_port_in_use(DEFAULT_PORT, DEFAULT_HOST):
                ready = True
                break
            time.sleep(0.1)

        if not ready:
            stop_game_process(proc)
            raise TimeoutError(f"Debug server did not open port {DEFAULT_PORT} within {ready_timeout}s")

    return proc


def stop_game_process(proc: subprocess.Popen, timeout: float = 4.0) -> Tuple[int, str, str]:
    """Gracefully stop game process and return (returncode, stdout, stderr)."""
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        return proc.returncode, stdout, stderr

    # First attempt: send debug quit command
    try:
        send_debug_command({"cmd": "quit"}, timeout=1.0)
    except Exception:
        pass

    # Wait briefly for voluntary termination
    try:
        proc.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        # Second attempt: SIGTERM
        proc.terminate()
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Final attempt: SIGKILL
            proc.kill()
            proc.wait()

    stdout, stderr = proc.communicate()
    clean_orphaned_processes()
    return proc.returncode, stdout, stderr


def run_command(cmd: List[str], cwd: Optional[Path] = None, timeout: float = 60.0) -> subprocess.CompletedProcess[str]:
    """Run a CLI command with stdout/stderr captured as text."""
    return subprocess.run(
        cmd,
        cwd=str(cwd or REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=timeout,
    )

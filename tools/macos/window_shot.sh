#!/bin/bash
# Screenshot one app window (no desktop) by process id, for test evidence.
#
#   tools/macos/window_shot.sh <pid> <out.png>
#
# Picks the largest normal (layer 0) window owned by <pid>, even when it is
# off screen (behind a full-screen app), so test runs need not take the display.
set -euo pipefail
PID="$1"; OUT="$2"
WID="$(swift - "$PID" <<'SWIFT'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
var best = (0, 0.0)
for w in list where (w["kCGWindowOwnerPID"] as? Int) == pid && (w["kCGWindowLayer"] as? Int) == 0 {
    let b = w["kCGWindowBounds"] as! [String: Double]
    let area = b["Width"]! * b["Height"]!
    if area > best.1 { best = (w["kCGWindowNumber"] as! Int, area) }
}
print(best.0)
SWIFT
)"
[ "$WID" != 0 ] || { echo "no window for pid $PID" >&2; exit 1; }
screencapture -x -o -l"$WID" "$OUT"

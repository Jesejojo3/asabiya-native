#!/usr/bin/env bash
# Renders a screenshot under Xvfb (Linux CI/dev). Usage:
#   tools/capture.sh OUT.png SNAPSHOT.asw [extra user args...]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$1"; snap="$2"; shift 2
exec xvfb-run -a -s "-screen 0 1920x1080x24" godot --path "$here" -w --resolution "${RES:-1280x720}" \
  -- --snapshot "$snap" --capture "$out" "$@" 2>&1 | grep -v -E "ALSA|audio|alsa|^$|init_output_device|dummy driver"

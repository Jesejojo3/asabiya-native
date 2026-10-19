#!/usr/bin/env bash
# Test-only launcher for the bridge test double. Requires ASABIYA_SNAPSHOT.
exec python3 "$(dirname "$0")/mock_bridge.py" --snapshot "$ASABIYA_SNAPSHOT" "$@"

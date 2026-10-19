#!/usr/bin/env bash
# Linux/CI build of the Windows x64 client (cross-export).
#   client/tools/build-client.sh [GODOT_BIN]
# Needs: Go (as in .go-version, or GOTOOLCHAIN=local with a compatible Go),
# Godot 4.7.2-stable for Linux and its export templates installed in
# ~/.local/share/godot/export_templates/4.7.2.stable.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
godot="${1:-godot}"
build="$repo/build"
out="$build/client"
seed="${SEED:-Asabiya}"
mkdir -p "$build/bin" "$build/worlds" "$out/worlds"

# exporter: native (for generating worlds here) and Windows (shipped)
( cd "$repo" && CGO_ENABLED=0 go build -trimpath -buildvcs=false -o "$build/bin/asabiya-snapshot" ./client/exporter )
( cd "$repo" && GOOS=windows GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=0 go build -trimpath -buildvcs=false -o "$build/bin/asabiya-snapshot.exe" ./client/exporter )
"$build/bin/asabiya-snapshot" --seed "$seed" --out "$build/worlds/$seed.asw"

"$godot" --headless --path "$repo/client/godot" --import >/dev/null 2>&1 || true
"$godot" --headless --path "$repo/client/godot" --export-release "Windows x64" "$out/AsabiyaNative.exe"
test -s "$out/AsabiyaNative.exe"
cp "$build/bin/asabiya-snapshot.exe" "$out/"
cp "$build/worlds/"*.asw "$out/worlds/"
sha256sum "$out/AsabiyaNative.exe" "$out/asabiya-snapshot.exe"

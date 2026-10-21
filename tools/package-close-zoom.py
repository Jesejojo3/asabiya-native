"""Build a self-contained Windows profiling kit; never invent measurements."""
import argparse
import hashlib
import io
import json
import pathlib
import subprocess
import tarfile
import zipfile

BASELINE = "2193a9d92400e7398c73c79105e311aae6397d3b"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--editor-zip", type=pathlib.Path, required=True)
parser.add_argument("--server", type=pathlib.Path, required=True)
parser.add_argument("--out", type=pathlib.Path, required=True)
args = parser.parse_args()
repo = pathlib.Path(__file__).resolve().parent.parent
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
pins = dict(line.split() for line in (repo / "client/tools/godot-pins.txt").read_text().splitlines() if line and not line.startswith("#"))
name = "Godot_v4.7.2-stable_win64.exe.zip"
if hashlib.sha256(args.editor_zip.read_bytes()).hexdigest() != pins[name]:
    raise SystemExit("Pinned Windows editor archive hash mismatch")
archive = subprocess.check_output(["git", "archive", "--format=tar", BASELINE], cwd=repo)
with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
    tree.extractall(out / "source", filter="data")
with zipfile.ZipFile(args.editor_zip) as editor:
    editor.extractall(out / "editor")
(out / "tools").mkdir()
(out / "tools/profile-close-zoom.ps1").write_bytes((repo / "tools/profile-close-zoom.ps1").read_bytes())
(out / "tools/close_zoom_capture.gd").write_bytes((repo / "client/godot/tests/close_zoom_capture.gd").read_bytes())
(out / "asabiya-server.exe").write_bytes(args.server.read_bytes())
(out / "PERFILAR.cmd").write_bytes(b'@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\\profile-close-zoom.ps1"\r\npause\r\n')
(out / "LEEME.txt").write_text(
    "PERFILAR.cmd mide la version base #22, no una optimizacion.\n"
    "Conecta el portatil a corriente y cierra aplicaciones pesadas.\n"
    "Ejecuta PERFILAR.cmd y deja la ventana visible sin usar raton ni teclado.\n"
    "Son 3 repeticiones de 1080p/720p, pausado/activo, 60 s de captura y 20 s de calentamiento.\n"
    "Antes de cada captura se calculan 10000 anos fuera del intervalo medido; puede tardar varios minutos.\n"
    "No necesitas instalar Go, Godot, Python o Node. El kit incluye editor y servidor.\n"
    "Entrega la carpeta results-* completa para el analisis. No reemplaces archivos del kit.\n"
    "720p y las variantes diagnosticas no acreditan 30 FPS a 1080p ni calidad CKIII.\n"
    "Controlador y CPU/GPU se registran automaticamente, sin nombre de equipo ni usuario.\n",
    encoding="utf-8",
)
files = [{"path": p.relative_to(out).as_posix(), "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
         for p in sorted(out.rglob("*")) if p.is_file()]
manifest = {"schema": "asabiya/close-zoom-kit-v1", "sourceRevision": BASELINE,
            "harnessRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
            "serverSHA256": hashlib.sha256(args.server.read_bytes()).hexdigest(),
            "editorArchiveSHA256": pins[name], "editor": "editor/Godot_v4.7.2-stable_win64_console.exe",
            "files": files, "measured": False}
(out / "PROFILE-KIT.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Profiling kit prepared, no FPS measurements: {out}")

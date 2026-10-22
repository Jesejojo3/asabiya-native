"""Build the Phase 2.3 Windows diagnosis kit. Never invents measurements."""
import argparse
import hashlib
import io
import json
import pathlib
import shutil
import subprocess
import tarfile
import zipfile

BASELINE = "2193a9d92400e7398c73c79105e311aae6397d3b"
# Asabiya/1, 400x200 detail 4, 10000 years: identical on the user's Windows
# capture (PR #24 kit, 2026-10-21) and on a Linux Go 1.27.2 headless replay.
EXPECTED = {"10000": "e7df456c262d6bf4f01918de79a8ff1b3eb8f736f347c7d5c3cf12e44d1c27e9"}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--editor-zip", type=pathlib.Path, required=True)
parser.add_argument("--server", type=pathlib.Path, required=True)
parser.add_argument("--exported", type=pathlib.Path, required=True, help="exported AsabiyaNative.exe")
parser.add_argument("--candidate", default="HEAD")
parser.add_argument("--out", type=pathlib.Path, required=True)
args = parser.parse_args()
repo = pathlib.Path(__file__).resolve().parent.parent
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
pins = dict(line.split() for line in (repo / "client/tools/godot-pins.txt").read_text().splitlines() if line and not line.startswith("#"))
name = "Godot_v4.7.2-stable_win64.exe.zip"
if hashlib.sha256(args.editor_zip.read_bytes()).hexdigest() != pins[name]:
    raise SystemExit("Pinned Windows editor archive hash mismatch")
candidate = subprocess.check_output(["git", "rev-parse", args.candidate], cwd=repo, text=True).strip()


def extract(revision: str, target: str) -> None:
    archive = subprocess.check_output(["git", "archive", "--format=tar", revision, "client/godot"], cwd=repo)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        tree.extractall(out / target, filter="data")


extract(BASELINE, "source-base")
extract(candidate, "source-candidate")
with zipfile.ZipFile(args.editor_zip) as editor:
    editor.extractall(out / "editor")
tools = out / "tools"
tools.mkdir()
harness = subprocess.check_output(["git", "show", f"{candidate}:client/godot/diagnostics/render_diagnosis.gd"], cwd=repo)
(tools / "render_diagnosis.gd").write_bytes(harness)
(tools / "render_diagnosis_runner.gd").write_bytes(subprocess.check_output(["git", "show", f"{candidate}:client/godot/tests/render_diagnosis_runner.gd"], cwd=repo))
for script in ["diagnose-render.ps1", "analyze-render-diagnosis.mjs"]:
    (tools / script).write_bytes(subprocess.check_output(["git", "show", f"{candidate}:tools/{script}"], cwd=repo))
shutil.copyfile(args.server, out / "asabiya-server.exe")
exported = out / "exported"
exported.mkdir()
shutil.copyfile(args.exported, exported / "AsabiyaNative.exe")
# Lets the exported build be opened by hand exactly like the product package.
shutil.copyfile(args.server, exported / "asabiya-server.exe")
(exported / "asabiya.json").write_text(json.dumps({"world": {"seed": "Asabiya", "width": 400, "height": 200, "detail": 4, "landFraction": 0.33}, "historySeed": "1"}, indent=2) + "\n", encoding="utf-8")


def command(file: str, campaign: str) -> None:
    (out / file).write_bytes(('@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\\diagnose-render.ps1" -Campaign ' + campaign + '\r\npause\r\n').encode())


command("PERFILAR-COMPLETO.cmd", "full")
command("PERFILAR-RAPIDO.cmd", "quick")
(out / "JUGAR-OPTIMIZADO.cmd").write_bytes(b'@echo off\r\ncd /d "%~dp0exported"\r\nstart "" AsabiyaNative.exe\r\n')
(out / "LEEME.txt").write_text(
    "Asabiya Native - kit de diagnostico grafico (Fase 2.3)\n\n"
    "Contenido: editor oficial Godot 4.7.2, fuentes base (#22, 2193a9d) y candidatas,\n"
    "ejecutable exportado candidato (exported\\AsabiyaNative.exe) y servidor Go.\n"
    "No hace falta instalar nada. No modifica tus ajustes ni partidas.\n\n"
    "1. Conecta el portatil a corriente, cierra programas pesados, plan de energia normal.\n"
    "2. Doble clic en PERFILAR-COMPLETO.cmd (unos 75-100 minutos) o PERFILAR-RAPIDO.cmd (unos 30).\n"
    "3. No toques raton ni teclado ni cambies de ventana mientras mide. Puedes dejarlo solo.\n"
    "4. Al terminar, comprime la carpeta results-* entera y entregala.\n\n"
    "Cada sesion calcula 10000 anos con el avance rapido del motor (1-4 minutos) y comprueba\n"
    "que el estado historico coincide con la huella e7df456c... antes de medir.\n"
    "Si una sesion falla, queda registrada (session-error.txt) y la campana continua.\n"
    "Las variantes de diagnostico (sin sombras, sin SSAO...) solo aislan costes: no son ajustes propuestos.\n"
    "JUGAR-OPTIMIZADO.cmd abre el ejecutable candidato para revisar la imagen a mano.\n",
    encoding="utf-8",
)
files = [{"path": p.relative_to(out).as_posix(), "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
         for p in sorted(out.rglob("*")) if p.is_file()]
manifest = {"schema": "asabiya/render-kit-v1", "baseRevision": BASELINE, "candidateRevision": candidate,
            "harnessSHA256": hashlib.sha256(harness).hexdigest(),
            "serverSHA256": hashlib.sha256(args.server.read_bytes()).hexdigest(),
            "exportedSHA256": hashlib.sha256(args.exported.read_bytes()).hexdigest(),
            "editorArchiveSHA256": pins[name], "editor": "editor/Godot_v4.7.2-stable_win64_console.exe",
            "expectedSHA256": EXPECTED, "files": files, "measured": False}
(out / "RENDER-KIT.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Render diagnosis kit prepared, no FPS measurements: {out}")

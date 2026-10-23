"""Build a self-contained Windows x64 prototype; run after pinned tools setup."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path
from stage import ROOT, stage


def run(command, **kwargs):
    subprocess.run([str(x) for x in command], check=True, cwd=ROOT, **kwargs)


def build(godot, go, template, destination):
    version = subprocess.check_output([go, "version"], text=True)
    if " go1.27.2 " not in version:
        raise RuntimeError("Go 1.27.2 required")
    gdversion = subprocess.check_output([godot, "--version"], text=True).strip()
    if gdversion != "4.7.2.stable.official.ed1daf0bf":
        raise RuntimeError("Pinned official Godot 4.7.2 required")
    project = stage(ROOT / "build/atlas2d/project")
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    preset = (ROOT / "client/godot/export_presets.cfg").read_text(encoding="utf-8")
    preset = preset.replace('custom_template/release=""', 'custom_template/release=' + json.dumps(str(Path(template).resolve()).replace('\\', '/')))
    preset = preset.replace('application/product_name="Asabiya Native"', 'application/product_name="Asabiya Atlas 2D"')
    preset = preset.replace('Asabiya Native - cliente 3D', 'Atlas 2D experimental')
    preset = preset.replace('exclude_filter="tests/*, tools/*"', 'exclude_filter="test_*.gd,probe.gd,licenses.gd"')
    (project / "export_presets.cfg").write_text(preset)
    environment = os.environ.copy()
    environment.update(GOOS="windows", GOARCH="amd64", GOAMD64="v1", CGO_ENABLED="0", GOTOOLCHAIN="local")
    run([go, "build", "-trimpath", "-ldflags=-s -w", "-o", destination / "asabiya-server.exe", "./cmd/asabiya-server"], env=environment)
    # Import must be checked in addition to exit status: Godot can report script errors with exit 0.
    imported = subprocess.run([godot, "--headless", "--path", str(project), "--import"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8")
    (ROOT / "build/atlas2d/build-import.log").write_text(imported.stdout)
    if imported.returncode or "SCRIPT ERROR" in imported.stdout or "Parse Error" in imported.stdout:
        raise RuntimeError("Godot import failed; see build-import.log")
    run([godot, "--headless", "--path", project, "--export-release", "Windows x64", destination / "AsabiyaAtlas2D.exe"])
    for name in ("README.md", "docs/SYSTEMS.md", "docs/BENCHMARK.md"):
        shutil.copyfile(ROOT / "experiments/atlas2d" / name, destination / Path(name).name)
    shutil.copytree(ROOT / "experiments/atlas2d/docs", destination / "docs", dirs_exist_ok=True)
    for name in ("benchmark.ps1", "telemetry.ps1", "summarize.py", "presentation.py"):
        shutil.copyfile(ROOT / "experiments/atlas2d/tools" / name, destination / name)
    presentmon = ROOT / "build/atlas2d/tools/PresentMon.exe"
    if hashlib.sha256(presentmon.read_bytes()).hexdigest() != "690533cf5c2591ef571a3037aa4c205c8e75860ef3f56927bf3a98acf7198485":
        raise RuntimeError("Pinned PresentMon 2.3.0 required")
    shutil.copyfile(presentmon, destination / "PresentMon.exe")
    shutil.copyfile(ROOT / "experiments/atlas2d/tools/PresentMon-LICENSE.txt", destination / "PresentMon-LICENSE.txt")
    (destination / "Medir rendimiento.cmd").write_text('@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0benchmark.ps1"\r\nif errorlevel 1 echo ERROR: captura incompleta. Conserva los logs.\r\npause\r\n')
    (destination / "Medir completo.cmd").write_text('@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0benchmark.ps1" -Full\r\nif errorlevel 1 echo ERROR: captura incompleta. Conserva los logs.\r\npause\r\n')
    (destination / "Abrir historia avanzada.cmd").write_text('@echo off\r\nstart "" "%~dp0AsabiyaAtlas2D.exe" -- --prepare-years=10000\r\n')
    if (ROOT / "LICENSE").exists():
        shutil.copyfile(ROOT / "LICENSE", destination / "LICENSE-Asabiya.txt")
    else:
        (destination / "NOTICE-Asabiya.txt").write_text("Proyecto privado Asabiya Native. Este paquete experimental no concede una licencia adicional sobre el proyecto. Uso por su responsable autorizado.\n")
    goroot = subprocess.check_output([go, "env", "GOROOT"], text=True).strip()
    shutil.copyfile(Path(goroot) / "LICENSE", destination / "LICENSE-Go.txt")
    # Engine license database includes third-party notices, independent of exporter installation.
    license_script = ROOT / "build/atlas2d/licenses.gd"
    license_script.write_text('extends SceneTree\nfunc _initialize():\n\tprint(JSON.stringify({"godot":Engine.get_license_text(),"thirdParty":Engine.get_license_info(),"copyright":Engine.get_copyright_info()}))\n\tquit()\n')
    notices = subprocess.check_output([godot, "--headless", "--path", str(project), "--script", str(license_script)], text=True, encoding="utf-8")
    (destination / "Godot-licenses.json").write_text(notices[notices.index('{'):], encoding="utf-8")
    manifest = json.loads((project / "build-manifest.json").read_text())
    manifest.update(godot=gdversion, go=version.strip(), target="windows/amd64/v1", mode="official release template", files={})
    for file in sorted(destination.rglob("*")):
        if file.is_file() and file.name != "build-manifest.json":
            manifest["files"][file.relative_to(destination).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    (destination / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--go", default="go")
    parser.add_argument("--template", required=True)
    parser.add_argument("--out", default=str(ROOT / "build/atlas2d/windows"))
    args = parser.parse_args()
    build(args.godot, args.go, args.template, args.out)

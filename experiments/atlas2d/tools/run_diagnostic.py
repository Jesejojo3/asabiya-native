"""Linux software integration measurements. Never evidence for target hardware."""
import argparse
import json
import os
import subprocess
import struct
import time
from pathlib import Path
from summarize import summary
from stage import ROOT

def rss(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) * 1024
    except (FileNotFoundError, ProcessLookupError):
        pass
    return 0

if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--godot",required=True)
    parser.add_argument("--server",required=True)
    parser.add_argument("--project",default=str(ROOT/"build/atlas2d/project"))
    parser.add_argument("--out",default=str(ROOT/"build/atlas2d/diagnostic"))
    parser.add_argument("--seconds",type=int,default=10)
    parser.add_argument("--year",type=int,default=10000)
    parser.add_argument("--zoom",type=float,default=4)
    args=parser.parse_args()
    dest=Path(args.out).resolve();dest.mkdir(parents=True,exist_ok=True)
    results=[]
    for width,height in [(1920,1080),(1280,720)]:
        for active in [False,True]:
            name=f"{width}x{height}-zoom{args.zoom:g}-active{active}"
            raw=dest/(name+".jsonl");memory=raw.with_suffix(".memory.jsonl")
            command=[args.godot,"--path",args.project,"--audio-driver","Dummy","--",f"--server={args.server}",f"--bench-out={raw}",f"--seconds={args.seconds}",f"--year={args.year}",f"--zoom={args.zoom}",f"--width={width}",f"--height={height}",f"--screenshot={dest/(name+'.png')}"]
            if active:command.append("--active")
            print("Running",name,flush=True)
            env=os.environ.copy();env.update(LIBGL_ALWAYS_SOFTWARE="1",GALLIUM_DRIVER="llvmpipe")
            with (dest/(name+".log")).open("w") as log,memory.open("w") as mem:
                proc=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env)
                deadline=time.monotonic()+600;go_pid=0
                while proc.poll() is None:
                    if time.monotonic()>deadline:
                        proc.terminate();raise RuntimeError("Capture timed out")
                    if raw.exists():
                        for line in raw.read_text().splitlines():
                            try: row=json.loads(line)
                            except json.JSONDecodeError:continue
                            if row["kind"]=="ready":go_pid=row["go_pid"]
                    gd=rss(proc.pid);go=rss(go_pid)
                    mem.write(json.dumps({"monotonic_s":time.monotonic(),"godot_bytes":gd,"go_bytes":go,"combined_bytes":gd+go})+"\n")
                    time.sleep(.5)
                if proc.returncode:raise RuntimeError(f"Exit {proc.returncode}: {name}")
            if any(error in (dest/(name+".log")).read_text() for error in ("SCRIPT ERROR","SHADER ERROR")):
                raise RuntimeError("Godot runtime errors in "+name)
            size = struct.unpack(">II", (dest/(name+".png")).read_bytes()[16:24])
            if size != (width,height): raise RuntimeError("Screenshot framebuffer mismatch")
            results.append(summary(raw))
            (dest/"summary.json").write_text(json.dumps(results,indent=2)+"\n")
            print({key:results[-1][key] for key in ("file","post_draw","presentation","years_per_second")},flush=True)

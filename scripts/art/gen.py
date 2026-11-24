"""Generate missing raw art with Codex CLI image generation, a few at a time.
Usage: .venv-art/bin/python scripts/art/gen.py [key ...]  (no keys = everything missing)"""
import subprocess, sys, pathlib, concurrent.futures as cf
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from specs import all_specs

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "art" / "raw"
RAW.mkdir(parents=True, exist_ok=True)

def run(key, prompt):
    out = RAW / f"{key}.png"
    instr = (f"Use your image generation tool to create ONE image (landscape 1536x1024), then save (copy) the "
             f"generated PNG to art/raw/{key}.png and reply with just the path. Do not write any code.\n\n{prompt}")
    for attempt in range(2):
        r = subprocess.run(["codex", "exec", "--skip-git-repo-check", "-s", "workspace-write", "-C", str(ROOT), instr],
                           capture_output=True, text=True, timeout=900)
        if out.exists():
            return f"ok   {key}"
    return f"FAIL {key}: {r.stdout[-300:]} {r.stderr[-300:]}"

specs = all_specs()
keys = sys.argv[1:] or [k for k in specs if not (RAW / f"{k}.png").exists()]
print(f"generating {len(keys)}: {' '.join(keys)}", flush=True)
with cf.ThreadPoolExecutor(max_workers=4) as ex:
    for msg in ex.map(lambda k: run(k, specs[k]), keys):
        print(msg, flush=True)

"""Turn raw AI sprite sheets (magenta background) into crisp game-ready pixel sheets.

Usage: .venv-art/bin/python scripts/art/process.py [key ...]   (no keys = every raw file)
Output: Resources/Art/<key>.png + <key>.json
"""
import json, pathlib, sys
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "art" / "raw"
OUT = ROOT / "Resources" / "Art"
OUT.mkdir(parents=True, exist_ok=True)

HERO_ANIMS = {"walk": range(0, 6), "attack": range(6, 12), "idle": range(12, 15), "jump": range(15, 18),
              "hurt": range(18, 20), "down": range(20, 22), "victory": range(22, 24)}
MON_ANIMS = {"move": range(0, 4), "attack": range(4, 8), "hurt": range(8, 10), "dead": range(10, 12)}

TEAM = {"hero_warrior": (86, 170, 255), "hero_archer": (110, 230, 120), "hero_mage": (190, 140, 255)}
OUTLINE_DARK = (28, 20, 34)

# key prefix/name -> (rows, cols, target walk height in art px, anims)
def layout(key):
    if key.startswith("hero_"):
        return 4, 6, 36, HERO_ANIMS
    if key.startswith("mon_"):
        name = key[4:]
        boss = name in {"stapler_king", "sharpener_giant", "mug_octopus", "succulent_king", "mouse_dragon"}
        heavy = name.endswith("golem")
        flyer = name in {"paper_crane", "clip_bat", "teabag_ghost", "dandelion_sprite", "cursor_ghost"}
        h = 50 if boss else 32 if heavy else 20 if flyer else 20
        return 3, 4, h, MON_ANIMS
    if key.startswith("props") or key in ("accessories", "trophies"):
        return 1, 6, None, None
    if key == "pets":
        return 3, 4, 16, {"cat": range(0, 4), "hamster": range(4, 8), "bird": range(8, 12)}
    if key == "camp":
        return 1, 6, None, None
    if key == "icons":
        return 2, 8, None, None
    if key == "items_base":
        return 2, 6, None, None
    if key.startswith("items_unique"):
        return 2, 5, None, None
    return None


def load_rgba(path):
    img = np.asarray(Image.open(path).convert("RGBA")).astype(np.int32)
    rgb = img[..., :3]
    corners = np.concatenate([rgb[:8, :8].reshape(-1, 3), rgb[:8, -8:].reshape(-1, 3),
                              rgb[-8:, :8].reshape(-1, 3), rgb[-8:, -8:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((rgb - bg) ** 2).sum(-1))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    fringe = (r - g > 70) & (b - g > 70) & (np.abs(r - b) < 70)
    fg = (dist > 110) & ~fringe
    out = img.copy()
    out[..., 3] = np.where(fg, 255, 0)
    return out.astype(np.uint8), fg


def segments(profile, min_gap, want):
    """Split a 1D occupancy profile into `want` runs, merging across the smallest gaps."""
    occ = profile > 0
    runs, start = [], None
    for i, v in enumerate(occ):
        if v and start is None:
            start = i
        if not v and start is not None:
            runs.append([start, i]); start = None
    if start is not None:
        runs.append([start, len(occ)])
    # merge runs separated by tiny gaps, then merge closest pairs until count == want
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < min_gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    merged = [r for r in merged if r[1] - r[0] > 6]
    while want and len(merged) > want:
        gaps = [merged[i + 1][0] - merged[i][1] for i in range(len(merged) - 1)]
        i = int(np.argmin(gaps))
        merged[i][1] = merged[i + 1][1]
        del merged[i + 1]
    return merged


def split_frames(fg, rows, cols):
    bands = segments(fg.sum(1), 12, rows)
    if len(bands) != rows:  # fall back to an even split
        h = fg.shape[0] // rows
        bands = [[i * h, (i + 1) * h] for i in range(rows)]
    boxes = []
    for y0, y1 in bands:
        cs = segments(fg[y0:y1].sum(0), 10, cols)
        if len(cs) != cols:
            w = fg.shape[1] // cols
            cs = [[i * w, (i + 1) * w] for i in range(cols)]
        for x0, x1 in cs:
            sub = fg[y0:y1, x0:x1]
            ys, xs = np.nonzero(sub)
            if len(ys) == 0:
                boxes.append(None); continue
            boxes.append((x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1))
    return boxes


def shrink(img, box, f):
    x0, y0, x1, y1 = box
    crop = Image.fromarray(img[y0:y1, x0:x1]).convert("RGBa")  # premultiplied for clean edges
    w, h = max(1, round((x1 - x0) * f)), max(1, round((y1 - y0) * f))
    small = np.asarray(crop.resize((w, h), Image.BOX).convert("RGBA")).copy()
    small[..., 3] = np.where(small[..., 3] >= 110, 255, 0)
    return small


def add_outline(a, color):
    """1px outline outside the opaque shape (4-neighbourhood), keeps the canvas padded by 1."""
    h, w = a.shape[:2]
    p = np.zeros((h + 2, w + 2, 4), np.uint8)
    p[1:-1, 1:-1] = a
    op = p[..., 3] > 0
    nb = np.zeros_like(op)
    nb[1:, :] |= op[:-1, :]; nb[:-1, :] |= op[1:, :]; nb[:, 1:] |= op[:, :-1]; nb[:, :-1] |= op[:, 1:]
    edge = nb & ~op
    p[edge] = (*color, 255)
    return p


def quantize(frames, colors=40):
    """Shared palette across all frames so the sheet reads as one sprite."""
    opaque = np.concatenate([f[f[..., 3] > 0][:, :3] for f in frames if (f[..., 3] > 0).any()])
    pal_img = Image.fromarray(opaque.reshape(1, -1, 3).astype(np.uint8)).quantize(colors, method=Image.MEDIANCUT)
    out = []
    for f in frames:
        rgb = Image.fromarray(f[..., :3]).quantize(palette=pal_img, dither=Image.NONE).convert("RGB")
        q = np.asarray(rgb).copy()
        out.append(np.dstack([q, f[..., 3]]))
    return out


def anchor_x(a):
    """Median column of the lower body — keeps feet planted when weapons swing."""
    op = a[..., 3] > 0
    ys, xs = np.nonzero(op)
    if len(xs) == 0:
        return a.shape[1] / 2
    lower = ys >= ys.min() + (ys.max() - ys.min()) * 0.45
    return float(np.median(xs[lower]))


def torso_x(a):
    """Mean column of the upper-middle body (below the head, above the legs)."""
    op = a[..., 3] > 0
    ys, xs = np.nonzero(op)
    top, h = ys.min(), ys.max() - ys.min()
    band = (ys > top + h * 0.35) & (ys < top + h * 0.65)
    return float(xs[band].mean()) if band.any() else float(xs.mean())


def process_sheet(key):
    rows, cols, target_h, anims = layout(key)
    img, fg = load_rgba(RAW / f"{key}.png")
    boxes = split_frames(fg, rows, cols)
    if target_h:
        ref = [b[3] - b[1] for b in boxes[:cols] if b]
        f = target_h / float(np.median(ref))
    else:  # props/accessories: scale relative to the tallest item
        tallest = max(b[3] - b[1] for b in boxes if b)
        f = (58 if key.startswith("props2_") else 44 if key.startswith("props_") else 18 if key == "trophies"
             else 22 if key.startswith("items") else 30 if key == "camp" else 16 if key == "icons" else 12) / tallest
    frames = [shrink(img, b, f) if b else np.zeros((1, 1, 4), np.uint8) for b in boxes]
    frames = quantize(frames)
    team = TEAM.get(key)
    if key.startswith("hero_"):
        frames = [add_outline(fr, team) for fr in frames]
    elif key.startswith("mon_") or key.startswith("props") or key in ("trophies", "pets", "camp", "icons") or key.startswith("items"):
        frames = [add_outline(fr, OUTLINE_DARK) for fr in frames]

    # common cell: every frame bottom-aligned, anchor column aligned
    ax = [anchor_x(fr) for fr in frames]
    if anims and "walk" in anims:
        # Walk cycles: align on the torso instead of the feet so the body doesn't wobble sideways between frames.
        walk = list(anims["walk"])
        torso = [torso_x(frames[i]) for i in walk]
        base = float(np.median([t - a for t, a in zip(torso, (ax[i] for i in walk))]))
        for i, tx in zip(walk, torso):
            ax[i] = tx - base
    left = max(int(np.ceil(a)) for a in ax) + 1
    right = max(fr.shape[1] - int(np.floor(a)) for fr, a in zip(frames, ax)) + 1
    cell_w = left + right
    cell_h = max(fr.shape[0] for fr in frames) + 1
    sheet = np.zeros((cell_h * rows, cell_w * cols, 4), np.uint8)
    for i, (fr, a) in enumerate(zip(frames, ax)):
        r, c = divmod(i, cols)
        ox = c * cell_w + left - int(round(a))
        oy = r * cell_h + cell_h - fr.shape[0]
        sheet[oy:oy + fr.shape[0], ox:ox + fr.shape[1]] = fr
    Image.fromarray(sheet).save(OUT / f"{key}.png")
    meta = {"cellW": cell_w, "cellH": cell_h, "rows": rows, "cols": cols, "anchorX": left,
            "frameWidths": [int(fr.shape[1]) for fr in frames],
            "frameHeights": [int(fr.shape[0]) for fr in frames],
            "anims": {k: list(v) for k, v in (anims or {}).items()}}
    (OUT / f"{key}.json").write_text(json.dumps(meta))
    return f"{key}: cell {cell_w}x{cell_h}, scale {f:.3f}"


def min_seam(err):
    """Minimum-cost top-to-bottom path through an (H, b) error map (image quilting)."""
    H, b = err.shape
    cost = err.copy()
    for y in range(1, H):
        prev = cost[y - 1]
        left = np.concatenate([[np.inf], prev[:-1]])
        right = np.concatenate([prev[1:], [np.inf]])
        cost[y] += np.minimum(np.minimum(left, prev), right)
    seam = np.zeros(H, int)
    seam[-1] = int(np.argmin(cost[-1]))
    for y in range(H - 2, -1, -1):
        x = seam[y + 1]
        lo, hi = max(0, x - 1), min(b, x + 2)
        seam[y] = lo + int(np.argmin(cost[y, lo:hi]))
    return seam, float(cost[-1].min())


MIN_FRAC = 0.6


def make_loop(a, b=12):
    """Turn a non-repeating band into a seamless horizontal loop.
    Searches any window [x0, x1) (at least 60% of the width) whose start and end look alike, then joins
    them along the least-different vertical path (image quilting) — no ghosting, no half-faded objects.
    Returns (tile, seam_cost_per_row)."""
    H, W = a.shape[:2]
    best = None
    for x0 in range(0, int(W * 0.35)):
        for x1 in range(x0 + int(W * MIN_FRAC), W - b + 1):
            err = ((a[:, x0:x0 + b] - a[:, x1:x1 + b]) ** 2).sum(-1)
            if best is not None and err.min(1).sum() / H > best[0]:
                continue   # cheap lower bound
            seam, c = min_seam(err)
            score = c / H
            if best is None or score < best[0]:
                best = (score, x0, x1, seam)
    cost, x0, x1, seam = best
    tile = a[:, x0:x1].copy()
    for y in range(H):
        k = seam[y]
        tile[y, :k] = a[y, x1:x1 + k]      # left of the seam continues from the window's end
    return tile, cost


def process_backdrop(key):
    """Opaque scene → two parallax bands split at the horizon (far: scenery, ground: walkable floor),
    each made into a seamless loop."""
    img = Image.open(RAW / f"{key}.png").convert("RGB")
    W, H = img.size
    img = img.crop((8, 8, W - 8, H - 8)); W, H = img.size
    top, horizon = int(H * 0.30), int(H * 0.76)
    f = 66.0 / (H - top)                       # whole band = 66 art px (≈100pt)
    out = {}
    for name, (y0, y1) in (("far", (top, horizon)), ("ground", (horizon, H))):
        band = img.crop((0, y0, W, y1))
        band = band.resize((round(W * f), round((y1 - y0) * f)), Image.BOX)
        band = band.quantize(48, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
        tile, cost = make_loop(np.asarray(band).astype(np.float32))
        Image.fromarray(tile.clip(0, 255).astype(np.uint8)).save(OUT / f"{key}_{name}.png")
        out[name] = (tile.shape[1], tile.shape[0], round(cost))
    return f"{key}: {out}"


def process_strip(key, height=12):
    """Thin ground line on magenta → transparent, `height` art px tall, seamless loop (quilted incl. alpha)."""
    img, fg = load_rgba(RAW / f"{key}.png")
    rows = np.nonzero(fg.mean(1) > 0.5)[0]           # rows that are mostly ground
    y0, y1 = rows.min(), rows.max() + 1
    deco = np.nonzero(fg[:y0].mean(1) > 0.01)[0]     # little details sticking up above the band
    if len(deco):
        y0 = max(deco.min(), y0 - (y1 - y0))
    band = img[y0:y1, 8:-8]
    H, W = band.shape[:2]
    f = height / H
    small = Image.fromarray(band).convert("RGBa").resize((round(W * f), height), Image.BOX).convert("RGBA")
    a = np.asarray(small).copy()
    a[..., 3] = np.where(a[..., 3] >= 110, 255, 0)
    rgb = Image.fromarray(a[..., :3]).quantize(32, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    a = np.dstack([np.asarray(rgb), a[..., 3]]).astype(np.float32)
    weighted = a.copy(); weighted[..., :3] *= (a[..., 3:] / 255)
    tile, cost = make_loop(weighted)
    # re-take true colours for the chosen window (make_loop worked on weighted copies)
    out = tile.copy()
    out[..., :3] = np.where(out[..., 3:] > 0, out[..., :3] / np.maximum(out[..., 3:] / 255, 1e-3), 0)
    Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA").save(OUT / f"{key}.png")
    return f"{key}: {tile.shape[1]}x{tile.shape[0]}, seam {round(cost)}"


def main():
    keys = sys.argv[1:] or sorted(p.stem for p in RAW.glob("*.png"))
    for k in keys:
        try:
            print(process_backdrop(k) if k.startswith("bg_") else process_strip(k) if k.startswith("strip_")
                  else process_sheet(k))
        except Exception as e:  # keep going; report at the end
            print(f"ERROR {k}: {e}")


if __name__ == "__main__":
    main()

"""Replicates the app's recognition strategies with a model and compares them.

Each clean-test hand image (tiles ~68px) is placed in the middle of a
1.82x larger canvas, like a 1080p phone photo whose tile row spans ~55% of
the frame. The full-frame pass sees it downscaled to 640 (tiles ~37px);
the split-row pass crops the detected row from the high-res canvas in two
overlapping halves (as TfliteService.recognize does) and merges with NMS.
Usage: python -I sim_pipeline.py <ds_clean> <out.json> name=weights.pt ...
"""
import json
import os
import sys

import numpy as np
import torch
import torchvision
from PIL import Image
from ultralytics import YOLO

DS, OUT = sys.argv[1], sys.argv[2]
MODELS = dict(a.split('=', 1) for a in sys.argv[3:])
FACTOR = 1.82


def load_rows(path):
    rows = []
    for line in open(path):
        p = line.split()
        if len(p) >= 5:
            rows.append((int(p[0]), *map(float, p[1:5])))
    return rows


def predict(model, img):
    r = model.predict(img, imgsz=640, conf=0.10, iou=0.5, agnostic_nms=True,
                      max_det=60, device=0, verbose=False)[0]
    if r.boxes is None or not len(r.boxes):
        return np.zeros((0, 4)), np.zeros(0), np.zeros(0, dtype=int)
    return (r.boxes.xyxy.cpu().numpy(), r.boxes.conf.cpu().numpy(),
            r.boxes.cls.cpu().numpy().astype(int))


def row_region(boxes, scores, w, h):
    keep = scores >= 0.25
    if keep.sum() < 6:
        return None
    b = boxes[keep]
    mw = np.median(b[:, 2] - b[:, 0])
    mh = np.median(b[:, 3] - b[:, 1])
    if mw / w * 640 >= 60:  # tiles already large enough
        return None
    return (max(0, b[:, 0].min() - mw), max(0, b[:, 1].min() - 0.8 * mh),
            min(w, b[:, 2].max() + mw), min(h, b[:, 3].max() + 0.8 * mh))


def tiled(model, canvas, boxes, scores, classes):
    w, h = canvas.size
    region = row_region(boxes, scores, w, h)
    if region is None:
        return boxes, scores, classes
    l, t, r, b = region
    half = (r - l) * 0.56
    all_b, all_s, all_c = [], [], []
    for x0 in (l, r - half):
        crop = canvas.crop((int(x0), int(t), int(x0 + half), int(b)))
        cb, cs, cc = predict(model, crop)
        if len(cb):
            cb = cb + np.array([int(x0), int(t), int(x0), int(t)])
        all_b.append(cb)
        all_s.append(cs)
        all_c.append(cc)
    mb = np.concatenate(all_b) if all_b else np.zeros((0, 4))
    ms = np.concatenate(all_s)
    mc = np.concatenate(all_c)
    if not len(mb):
        return boxes, scores, classes
    keep = torchvision.ops.nms(torch.tensor(mb, dtype=torch.float32),
                               torch.tensor(ms, dtype=torch.float32), 0.4).numpy()
    return mb[keep], ms[keep], mc[keep]


def score(gt, boxes, classes, w, h):
    ok_tiles, used, all_ok = 0, set(), True
    for c, x, y, bw, bh in gt:
        g = np.array([(x - bw / 2) * w, (y - bh / 2) * h, (x + bw / 2) * w, (y + bh / 2) * h])
        best, best_iou = None, 0.5
        for j, pb in enumerate(boxes):
            if j in used:
                continue
            ix = max(0, min(g[2], pb[2]) - max(g[0], pb[0]))
            iy = max(0, min(g[3], pb[3]) - max(g[1], pb[1]))
            inter = ix * iy
            union = (g[2] - g[0]) * (g[3] - g[1]) + (pb[2] - pb[0]) * (pb[3] - pb[1]) - inter
            v = inter / union if union > 0 else 0
            if v >= best_iou:
                best, best_iou = j, v
        ok = best is not None and classes[best] == c
        if best is not None:
            used.add(best)
        ok_tiles += ok
        all_ok &= ok
    return all_ok, ok_tiles


def main():
    test = f'{DS}/test'
    stems = []
    for f in sorted(os.listdir(f'{test}/labels')):
        rows = load_rows(f'{test}/labels/{f}')
        if len(rows) >= 12:
            stems.append((f[:-4], rows))
    images = {f.rsplit('.', 1)[0]: f for f in os.listdir(f'{test}/images')}
    report = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for name, weights in MODELS.items():
        model = YOLO(weights)
        totals = {'full': [0, 0], 'tiled': [0, 0]}
        n_tiles = 0
        for stem, rows in stems:
            src = Image.open(f'{test}/images/{images[stem]}').convert('RGB')
            sw, sh = src.size
            cw, ch = int(sw * FACTOR), int(sh * FACTOR)
            canvas = Image.new('RGB', (cw, ch), (114, 114, 114))
            ox, oy = (cw - sw) // 2, (ch - sh) // 2
            canvas.paste(src, (ox, oy))
            gt = [(c, (x * sw + ox) / cw, (y * sh + oy) / ch, bw * sw / cw, bh * sh / ch)
                  for c, x, y, bw, bh in rows]
            boxes, scores, classes = predict(model, canvas)
            n_tiles += len(gt)
            exact, ok = score(gt, boxes, classes, cw, ch)
            totals['full'][0] += exact
            totals['full'][1] += ok
            tb, ts, tc = tiled(model, canvas, boxes, scores, classes)
            exact, ok = score(gt, tb, tc, cw, ch)
            totals['tiled'][0] += exact
            totals['tiled'][1] += ok
        report[name] = {
            mode: {
                'hand_exact_match': round(v[0] / len(stems), 4),
                'tile_accuracy': round(v[1] / n_tiles, 4),
            }
            for mode, v in totals.items()
        }
        report[name]['hand_images'] = len(stems)
        print(name, json.dumps(report[name]), flush=True)
        json.dump(report, open(OUT, 'w'), indent=2)


if __name__ == '__main__':
    main()

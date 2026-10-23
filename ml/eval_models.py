"""Compare detectors on the leakage-free test split.

For each model and each condition (as-is / "app-like": tiles shrunk to 55%,
mild blur, JPEG q=60, like a 1080p phone photo letterboxed to 640):
  - Ultralytics val: P, R, mAP50, mAP50-95, red-five APs
  - hand exact-match: share of hand images (>=12 GT tiles) where every GT tile
    is matched (IoU>=0.5) by a detection of the right class
  - tile accuracy: share of GT tiles detected with the right class
  - strict exact-match (live-like): detections >= 0.25 only, and the count must
    equal the GT count (no extra detections), over all hand images and over the
    13/14-tile hands only
Usage: python -I eval_models.py <ds_clean> <out.json> name=weights.pt[@imgsz] ...
  (@imgsz = inference size for that model, default 640; e.g. live_n_480=best.pt@480)
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter
from ultralytics import YOLO

DS = sys.argv[1]
OUT = sys.argv[2]
MODELS = dict(arg.split('=', 1) for arg in sys.argv[3:])
NAMES = None
LIVE_CONF = 0.25  # the live navigation's score threshold (LiveInferenceConfig)


def make_hard(src_split, dst_root, scale=0.55):
    if os.path.exists(dst_root):
        return
    os.makedirs(f'{dst_root}/images')
    os.makedirs(f'{dst_root}/labels')
    for f in sorted(os.listdir(f'{src_split}/images')):
        stem = f.rsplit('.', 1)[0]
        im = Image.open(f'{src_split}/images/{f}').convert('RGB')
        w, h = im.size
        sw, sh = int(w * scale), int(h * scale)
        small = im.resize((sw, sh), Image.BILINEAR).filter(ImageFilter.GaussianBlur(0.8))
        canvas = Image.new('RGB', (w, h), (114, 114, 114))
        ox, oy = (w - sw) // 2, (h - sh) // 2
        canvas.paste(small, (ox, oy))
        canvas.save(f'{dst_root}/images/{stem}.jpg', quality=60)
        lines = []
        lab = f'{src_split}/labels/{stem}.txt'
        if os.path.exists(lab):
            for line in open(lab):
                p = line.split()
                if len(p) < 5:
                    continue
                c, x, y, bw, bh = int(p[0]), *map(float, p[1:5])
                x = (x * sw + ox) / w
                y = (y * sh + oy) / h
                lines.append(f'{c} {x:.6f} {y:.6f} {bw * scale:.6f} {bh * scale:.6f}')
        with open(f'{dst_root}/labels/{stem}.txt', 'w') as out:
            out.write('\n'.join(lines) + ('\n' if lines else ''))


def load_gt(split_root):
    gt = {}
    for f in os.listdir(f'{split_root}/labels'):
        rows = []
        for line in open(f'{split_root}/labels/{f}'):
            p = line.split()
            if len(p) >= 5:
                rows.append((int(p[0]), *map(float, p[1:5])))
        gt[f.rsplit('.', 1)[0]] = rows
    return gt


def iou(a, b):
    ax1, ay1, ax2, ay2 = a[0] - a[2] / 2, a[1] - a[3] / 2, a[0] + a[2] / 2, a[1] + a[3] / 2
    bx1, by1, bx2, by2 = b[0] - b[2] / 2, b[1] - b[3] / 2, b[0] + b[2] / 2, b[1] + b[3] / 2
    iw = max(0.0, min(ax2, bx2) - max(ax1, bx1))
    ih = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter = iw * ih
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def match_tiles(gt_rows, preds):
    """Greedy IoU>=0.5 matching of GT tiles to detections; returns per-GT correctness."""
    used = set()
    oks = []
    for c, x, y, w, h in gt_rows:
        best = None
        best_iou = 0.5
        for j, (pc, px, py, pw, ph, ps) in enumerate(preds):
            if j in used:
                continue
            v = iou((x, y, w, h), (px, py, pw, ph))
            if v >= best_iou:
                best, best_iou = j, v
        ok = best is not None and preds[best][0] == c
        if best is not None:
            used.add(best)
        oks.append(ok)
    return oks


def hand_metrics(model, split_root, imgsz=640):
    gt = load_gt(split_root)
    stems = [s for s, rows in gt.items() if len(rows) >= 12]
    images = {f.rsplit('.', 1)[0]: f for f in os.listdir(f'{split_root}/images')}
    exact = 0
    strict = 0
    exact_1314 = 0
    strict_1314 = 0
    n_1314 = 0
    tiles_ok = 0
    tiles_total = 0
    red_ok = 0
    red_total = 0
    per = []
    batch = 32
    for i in range(0, len(stems), batch):
        chunk = stems[i:i + batch]
        results = model.predict(
            [f'{split_root}/images/{images[s]}' for s in chunk],
            imgsz=imgsz, conf=0.10, iou=0.5, agnostic_nms=True, max_det=60,
            device=0, verbose=False,
        )
        for stem, r in zip(chunk, results):
            preds = []
            if r.boxes is not None and len(r.boxes):
                xywhn = r.boxes.xywhn.cpu().numpy()
                cls = r.boxes.cls.cpu().numpy().astype(int)
                conf = r.boxes.conf.cpu().numpy()
                preds = [(c, *xy, s) for c, xy, s in zip(cls, xywhn, conf)]
            oks = match_tiles(gt[stem], preds)
            for (c, *_), ok in zip(gt[stem], oks):
                tiles_total += 1
                tiles_ok += ok
                if NAMES[c].startswith('0') and NAMES[c] != '0b':
                    red_total += 1
                    red_ok += ok
            all_ok = all(oks)
            live_preds = [p for p in preds if p[5] >= LIVE_CONF]
            live_ok = all(match_tiles(gt[stem], live_preds)) and len(live_preds) == len(gt[stem])
            per.append((stem, len(gt[stem]), all_ok, live_ok))
            exact += all_ok
            strict += live_ok
            if len(gt[stem]) in (13, 14):
                n_1314 += 1
                exact_1314 += all_ok
                strict_1314 += live_ok
    n = max(1, len(stems))
    m = max(1, n_1314)
    # Frames from the oblique videos (extract_frames.py names them vid*) as their own line.
    vid = [p for p in per if p[0].startswith('vid')]
    oblique = {}
    if vid:
        oblique = {
            'oblique_hand_images': len(vid),
            'oblique_hand_exact_match': sum(p[2] for p in vid) / len(vid),
            'oblique_hand_exact_strict_c25': sum(p[3] for p in vid) / len(vid),
        }
    return {**oblique,
        'hand_images': len(stems),
        'hand_exact_match': exact / n,
        'hand_exact_strict_c25': strict / n,
        'hand13_14_images': n_1314,
        'hand13_14_exact_match': exact_1314 / m,
        'hand13_14_exact_strict_c25': strict_1314 / m,
        'tile_accuracy': tiles_ok / max(1, tiles_total),
        'red_five_accuracy': red_ok / max(1, red_total),
    }


def val_metrics(model, data_yaml, project, imgsz=640):
    r = model.val(data=data_yaml, split='test', imgsz=imgsz, batch=32, device=0,
                  project=project, name='val', exist_ok=True, plots=False, verbose=False)
    per = {}
    for i, c in enumerate(r.box.ap_class_index):
        p, rr, ap50, ap = r.box.class_result(i)
        per[r.names[int(c)]] = round(float(ap), 4)
    return {
        'precision': round(float(r.box.mp), 4),
        'recall': round(float(r.box.mr), 4),
        'mAP50': round(float(r.box.map50), 4),
        'mAP50_95': round(float(r.box.map), 4),
        'red_mAP50_95': {k: per.get(k) for k in ('0m', '0p', '0s')},
        'worst5': sorted(per.items(), key=lambda kv: kv[1])[:5],
    }


def main():
    global NAMES
    hard_root = os.path.join(os.path.dirname(OUT), 'ds_hard')
    make_hard(f'{DS}/test', f'{hard_root}/test')
    names_line = [l for l in open(f'{DS}/data_baseline.yaml') if l.startswith('names:')][0]
    with open(f'{hard_root}/data.yaml', 'w') as f:
        f.write(f'path: {hard_root}\ntrain: test/images\nval: test/images\ntest: test/images\nnc: 38\n{names_line}')
    conditions = {
        'clean_test': (f'{DS}/data_baseline.yaml', f'{DS}/test'),
        'app_like_test': (f'{hard_root}/data.yaml', f'{hard_root}/test'),
    }
    report = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for name, spec in MODELS.items():
        weights, _, size = spec.partition('@')
        imgsz = int(size) if size else 640
        model = YOLO(weights)
        NAMES = model.names
        report[name] = {'weights': weights, 'imgsz': imgsz}
        for cond, (yaml_path, split_root) in conditions.items():
            entry = val_metrics(model, yaml_path, os.path.join(os.path.dirname(OUT), f'val_{name}_{cond}'), imgsz)
            entry.update(hand_metrics(model, split_root, imgsz))
            report[name][cond] = entry
            print(name, cond, json.dumps(entry, ensure_ascii=False), flush=True)
        json.dump(report, open(OUT, 'w'), indent=2, ensure_ascii=False)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""tflite（アプリに入れる形）の手牌の完全一致率を、アプリのデコーダと同じ手順で測る。

app/lib/ml/live_yolo_decoder.dart と同じ: 入力 = 灰色 114 の余白で S×S にレターボックスした
RGB/255（float32）、出力 [1, 4+C, N] の各アンカーで最良クラスを採り、しきい値未満を捨て、
上位 300 件にクラスを区別しない NMS（IoU 0.5、最大 60 件）。座標が 0〜1 なら S 倍する。
(縮小は cv2.INTER_LINEAR = Ultralytics の学習時・アプリと同じ双線形 1 回)

指標は eval_models.py と同じ定義:
  - strict: しきい値以上の検出だけで、全 GT 牌が IoU>=0.5 かつ同じクラスで一致し、検出数 = GT 数
  - 手牌 = GT が 12 枚以上の画像、13/14 = ちょうど 13 か 14 枚の画像

使い方:
  python -I -B eval_tflite.py <ds_clean> <out.json> [--split test] [--conf 0.25] [--limit N] \
      name=model.tflite ...          # 入力サイズはモデルの入力形状から読む
  name=model.tflite の代わりに name=model.pt@480 とすると Ultralytics の推論で同じ指標を出す
  (tflite との量子化・変換差の比較用)。
"""
import argparse
import json
import os
import sys
import time

import cv2
import numpy as np


def iou_xywh(a, b):
    ax1, ay1, ax2, ay2 = a[0] - a[2] / 2, a[1] - a[3] / 2, a[0] + a[2] / 2, a[1] + a[3] / 2
    bx1, by1, bx2, by2 = b[0] - b[2] / 2, b[1] - b[3] / 2, b[0] + b[2] / 2, b[1] + b[3] / 2
    iw = max(0.0, min(ax2, bx2) - max(ax1, bx1))
    ih = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter = iw * ih
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def match_tiles(gt_rows, preds):
    used = set()
    oks = []
    for c, x, y, w, h in gt_rows:
        best, best_iou = None, 0.5
        for j, (pc, px, py, pw, ph, ps) in enumerate(preds):
            if j in used:
                continue
            v = iou_xywh((x, y, w, h), (px, py, pw, ph))
            if v >= best_iou:
                best, best_iou = j, v
        ok = best is not None and preds[best][0] == c
        if best is not None:
            used.add(best)
        oks.append(ok)
    return oks


def nms(boxes, scores, iou_thr=0.5, max_keep=60):
    """boxes: (n,4) x1,y1,x2,y2。クラスを区別しない。"""
    order = np.argsort(-scores)
    keep = []
    for i in order:
        ok = True
        for j in keep:
            ix1, iy1 = max(boxes[i][0], boxes[j][0]), max(boxes[i][1], boxes[j][1])
            ix2, iy2 = min(boxes[i][2], boxes[j][2]), min(boxes[i][3], boxes[j][3])
            inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
            ua = (boxes[i][2] - boxes[i][0]) * (boxes[i][3] - boxes[i][1])
            ub = (boxes[j][2] - boxes[j][0]) * (boxes[j][3] - boxes[j][1])
            union = ua + ub - inter
            if union > 0 and inter / union > iou_thr:
                ok = False
                break
        if ok:
            keep.append(i)
            if len(keep) >= max_keep:
                break
    return keep


def decode(out, size, conf, max_candidates=300):
    """out: [1, 4+C, N] か [1, N, 4+C]。戻り値: (boxes xyxy[入力画素], scores, labels)。"""
    o = out[0]
    if o.shape[0] > o.shape[1]:
        o = o.T  # -> [4+C, N]
    coords = o[:4]
    cls = o[4:]
    scale = size if coords[2][::97].max() <= 1.5 else 1.0
    best = cls.max(axis=0)
    label = cls.argmax(axis=0)
    sel = np.where(best >= conf)[0]
    sel = sel[np.argsort(-best[sel])][:max_candidates]
    cx, cy, w, h = (coords[:, sel] * scale)
    boxes = np.stack([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], axis=1)
    scores = best[sel]
    keep = nms(boxes, scores)
    return boxes[keep], scores[keep], label[sel][keep]


def letterbox(img_bgr, size):
    h, w = img_bgr.shape[:2]
    scale = min(size / w, size / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    resized = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR) if (nw, nh) != (w, h) else img_bgr
    canvas = np.full((size, size, 3), 114, np.uint8)
    ox, oy = (size - nw) // 2, (size - nh) // 2
    canvas[oy:oy + nh, ox:ox + nw] = resized
    rgb = canvas[:, :, ::-1].astype(np.float32) / 255.0
    return rgb[None], scale, ox, oy


def load_gt(split_root, stem):
    rows = []
    for line in open(f'{split_root}/labels/{stem}.txt'):
        p = line.split()
        if len(p) >= 5:
            rows.append((int(p[0]), *map(float, p[1:5])))
    return rows


class TfliteModel:
    def __init__(self, path, threads):
        try:
            from ai_edge_litert.interpreter import Interpreter
        except ImportError:
            import tensorflow as tf
            Interpreter = tf.lite.Interpreter
        self.it = Interpreter(model_path=path, num_threads=threads)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]
        self.out = self.it.get_output_details()[0]
        self.size = int(self.inp['shape'][1])
        assert self.inp['dtype'] == np.float32 and self.out['dtype'] == np.float32, 'float 入出力だけ対応'

    def predict(self, img_bgr, conf):
        x, scale, ox, oy = letterbox(img_bgr, self.size)
        self.it.set_tensor(self.inp['index'], x)
        self.it.invoke()
        out = self.it.get_tensor(self.out['index'])
        boxes, scores, labels = decode(out, self.size, conf)
        h, w = img_bgr.shape[:2]
        preds = []
        for (x1, y1, x2, y2), s, c in zip(boxes, scores, labels):
            # 入力画素 -> 元画像の 0〜1
            x1, x2 = (x1 - ox) / scale / w, (x2 - ox) / scale / w
            y1, y2 = (y1 - oy) / scale / h, (y2 - oy) / scale / h
            x1, y1, x2, y2 = (min(max(v, 0.0), 1.0) for v in (x1, y1, x2, y2))
            if x2 > x1 and y2 > y1:
                preds.append((int(c), (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1, float(s)))
        return preds


class PtModel:
    def __init__(self, path, imgsz):
        from ultralytics import YOLO
        self.m = YOLO(path)
        self.imgsz = imgsz

    def predict(self, img_bgr, conf):
        r = self.m.predict(img_bgr, imgsz=self.imgsz, conf=conf, iou=0.5, agnostic_nms=True,
                           max_det=60, device=0, verbose=False)[0]
        preds = []
        if r.boxes is not None and len(r.boxes):
            for c, xy, s in zip(r.boxes.cls.cpu().numpy().astype(int), r.boxes.xywhn.cpu().numpy(),
                                r.boxes.conf.cpu().numpy()):
                preds.append((int(c), *map(float, xy), float(s)))
        return preds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ds')
    ap.add_argument('out')
    ap.add_argument('--split', default='test')
    ap.add_argument('--conf', type=float, default=0.25)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--threads', type=int, default=8)
    ap.add_argument('models', nargs='+', help='name=path.tflite | name=path.pt[@imgsz]')
    args = ap.parse_args()

    root = f'{args.ds}/{args.split}'
    images = {f.rsplit('.', 1)[0]: f for f in sorted(os.listdir(f'{root}/images'))}
    stems = [s for s in images if os.path.exists(f'{root}/labels/{s}.txt')]
    gts = {s: load_gt(root, s) for s in stems}
    hands = [s for s in stems if len(gts[s]) >= 12]
    if args.limit:
        hands = hands[:args.limit]
    report = json.load(open(args.out)) if os.path.exists(args.out) else {}

    for spec in args.models:
        name, path = spec.split('=', 1)
        if path.split('@')[0].endswith('.pt'):
            p, _, size = path.partition('@')
            model = PtModel(p, int(size) if size else 640)
        else:
            model = TfliteModel(path, args.threads)
        n = len(hands)
        strict = loose = n1314 = strict1314 = loose1314 = tiles_ok = tiles_total = extra = 0
        obl_n = obl_strict = obl_loose = 0  # vid* = 斜め動画のフレーム（extract_frames.py）
        t0 = time.perf_counter()
        for s in hands:
            img = cv2.imread(f'{root}/images/{images[s]}')
            preds = model.predict(img, args.conf)
            gt = gts[s]
            oks = match_tiles(gt, preds)
            all_ok = all(oks)
            strict_ok = all_ok and len(preds) == len(gt)
            tiles_ok += sum(oks)
            tiles_total += len(gt)
            extra += max(0, len(preds) - len(gt))
            strict += strict_ok
            loose += all_ok
            if s.startswith('vid'):
                obl_n += 1
                obl_strict += strict_ok
                obl_loose += all_ok
            if len(gt) in (13, 14):
                n1314 += 1
                strict1314 += strict_ok
                loose1314 += all_ok
        entry = {
            'model': path, 'conf': args.conf, 'hand_images': n,
            'hand_exact_strict': round(strict / max(1, n), 4),
            'hand_exact_loose': round(loose / max(1, n), 4),
            'hand13_14_images': n1314,
            'hand13_14_exact_strict': round(strict1314 / max(1, n1314), 4),
            'hand13_14_exact_loose': round(loose1314 / max(1, n1314), 4),
            'tile_accuracy': round(tiles_ok / max(1, tiles_total), 4),
            'extra_detections_per_image': round(extra / max(1, n), 3),
            'seconds_per_image': round((time.perf_counter() - t0) / max(1, n), 4),
        }
        if obl_n:
            entry['oblique_hand_images'] = obl_n
            entry['oblique_hand_exact_strict'] = round(obl_strict / obl_n, 4)
            entry['oblique_hand_exact_loose'] = round(obl_loose / obl_n, 4)
        report[name] = entry
        print(name, json.dumps(entry, ensure_ascii=False), flush=True)
        json.dump(report, open(args.out, 'w'), indent=2, ensure_ascii=False)


if __name__ == '__main__':
    sys.exit(main())

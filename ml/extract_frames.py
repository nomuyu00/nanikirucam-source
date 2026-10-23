#!/usr/bin/env python3
"""動画（斜め 30〜45° から撮った手牌）から学習用のフレームを切り出す。

  - 一定間隔で標本 → ぼやけたフレーム（ラプラシアン分散がクリップの中央値より大きく低い）と
    直前の採用フレームとほぼ同じフレームを捨てる → 1 本あたり --max-per-clip 枚に間引く
  - 既定で正立フレームの「中央の正方形」に切り出す（アプリのライブの推論範囲と同じ。
    app/lib/ml/live_preprocess.dart の centeredSquareRoi）。--crop none で全体
  - ファイル名は vid<動画名の英数字>_f<フレーム番号>.jpg。make_clean_split.py はこの名前で
    「動画 1 本 = 1 グループ」にまとめ、同じ動画のフレームが train/valid/test にまたがらない
  - --prelabel 重み.pt を付けると、そのモデルの検出を YOLO 形式の下書きラベルとして書く
    （人が直す前提。ラベルを直していないフレームは学習に使わないこと）

出力:
  <out>/train/images/vidXXXX_f00012.jpg
  <out>/train/labels/vidXXXX_f00012.txt     （--prelabel のときだけ）
  <out>/frames.csv                           （画像, 動画, フレーム番号, 秒, ぼやけ度, 下書きの検出数）

使い方（WSL。環境は train_live.sh と同じ Python）:
  python -I -B extract_frames.py clips/ --out ~/work/nanikiru-ml/ds_oblique \
      --fps 3 --max-per-clip 60 --prelabel ~/work/nanikiru-ml/runs/live_n/weights/best.pt

静止したスタンドで撮った動画は、ほとんどのフレームが重複として捨てられる。スマホか手牌を
少し動かしながら撮るか、--min-diff 0 で重複の判定を切る。
"""
import argparse
import csv
import os
import re
import sys

import cv2
import numpy as np

VIDEO_EXT = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'}


def list_videos(paths):
    out = []
    for p in paths:
        if os.path.isdir(p):
            for name in sorted(os.listdir(p)):
                if os.path.splitext(name)[1].lower() in VIDEO_EXT:
                    out.append(os.path.join(p, name))
        elif os.path.isfile(p):
            out.append(p)
        else:
            sys.exit(f'見つからない: {p}')
    return out


def clip_id(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return 'vid' + (re.sub(r'[^A-Za-z0-9]', '', stem) or 'x')


def rotate(img, deg):
    return {
        0: img,
        90: cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE),
        180: cv2.rotate(img, cv2.ROTATE_180),
        270: cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE),
    }[deg]


def center_square(img):
    h, w = img.shape[:2]
    s = min(h, w)
    top, left = (h - s) // 2, (w - s) // 2
    return img[top:top + s, left:left + s]


def sharpness(img):
    small = img
    h, w = img.shape[:2]
    if max(h, w) > 640:
        k = 640 / max(h, w)
        small = cv2.resize(img, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def thumb(img):
    return cv2.resize(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), (32, 32), interpolation=cv2.INTER_AREA).astype(np.float32)


def read_candidates(path, fps, rot, crop, max_side):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        print(f'開けない: {path}', file=sys.stderr)
        return []
    try:
        cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)  # スマホ動画の回転メタデータを反映
    except Exception:
        pass
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(src_fps / fps))
    cands = []
    idx = -1
    while True:
        ok = cap.grab()
        if not ok:
            break
        idx += 1
        if idx % step:
            continue
        ok, frame = cap.retrieve()
        if not ok:
            continue
        frame = rotate(frame, rot)
        if crop == 'center':
            frame = center_square(frame)
        h, w = frame.shape[:2]
        if max(h, w) > max_side:
            k = max_side / max(h, w)
            frame = cv2.resize(frame, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)
        cands.append((idx, idx / src_fps, frame, sharpness(frame)))
    cap.release()
    return cands


def select(cands, min_sharp_ratio, min_diff, max_per_clip):
    if not cands:
        return []
    med = float(np.median([c[3] for c in cands]))
    kept, last = [], None
    for c in cands:
        if c[3] < med * min_sharp_ratio:
            continue
        t = thumb(c[2])
        if last is not None and float(np.abs(t - last).mean()) < min_diff:
            continue
        kept.append(c)
        last = t
    if max_per_clip and len(kept) > max_per_clip:
        pick = np.linspace(0, len(kept) - 1, max_per_clip).round().astype(int)
        kept = [kept[i] for i in sorted(set(pick.tolist()))]
    return kept


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('videos', nargs='+', help='動画ファイル、または動画の入ったフォルダ')
    ap.add_argument('--out', required=True)
    ap.add_argument('--fps', type=float, default=3.0, help='標本の間隔（毎秒の枚数）')
    ap.add_argument('--max-per-clip', type=int, default=60)
    ap.add_argument('--min-sharp-ratio', type=float, default=0.6,
                    help='クリップの中央値のこの割合に満たないぼやけたフレームを捨てる（0 で無効）')
    ap.add_argument('--min-diff', type=float, default=2.0,
                    help='直前の採用フレームとの平均画素差（32x32 の灰色）がこれ未満なら重複として捨てる（0 で無効）')
    ap.add_argument('--crop', choices=['center', 'none'], default='center')
    ap.add_argument('--rotate', type=int, choices=[0, 90, 180, 270], default=0,
                    help='自動で正立にならない動画だけ、時計回りに回す角度')
    ap.add_argument('--max-side', type=int, default=1280)
    ap.add_argument('--prelabel', default='', help='下書きラベルを作る重み（.pt）')
    ap.add_argument('--conf', type=float, default=0.30)
    ap.add_argument('--imgsz', type=int, default=640)
    ap.add_argument('--jpeg-quality', type=int, default=95)
    args = ap.parse_args()

    videos = list_videos(args.videos)
    if not videos:
        sys.exit('動画がない')
    img_dir = os.path.join(args.out, 'train', 'images')
    lab_dir = os.path.join(args.out, 'train', 'labels')
    os.makedirs(img_dir, exist_ok=True)
    if args.prelabel:
        os.makedirs(lab_dir, exist_ok=True)
        from ultralytics import YOLO
        model = YOLO(args.prelabel)

    rows = []
    seen_ids = {}
    for path in videos:
        cid = clip_id(path)
        if cid in seen_ids and seen_ids[cid] != path:
            sys.exit(f'動画名が英数字だけにすると同じになる: {path} と {seen_ids[cid]}（名前を変えてください）')
        seen_ids[cid] = path
        cands = read_candidates(path, args.fps, args.rotate, args.crop, args.max_side)
        kept = select(cands, args.min_sharp_ratio, args.min_diff, args.max_per_clip)
        print(f'{os.path.basename(path)}: 標本 {len(cands)} -> 採用 {len(kept)}', flush=True)
        for idx, sec, frame, sharp in kept:
            name = f'{cid}_f{idx:05d}'
            cv2.imwrite(os.path.join(img_dir, name + '.jpg'), frame,
                        [cv2.IMWRITE_JPEG_QUALITY, args.jpeg_quality])
            n_det = ''
            if args.prelabel:
                r = model.predict(frame, imgsz=args.imgsz, conf=args.conf, iou=0.5,
                                  agnostic_nms=True, max_det=60, verbose=False)[0]
                lines = []
                if r.boxes is not None and len(r.boxes):
                    for c, xy in zip(r.boxes.cls.cpu().numpy().astype(int), r.boxes.xywhn.cpu().numpy()):
                        lines.append(f'{c} {xy[0]:.6f} {xy[1]:.6f} {xy[2]:.6f} {xy[3]:.6f}')
                with open(os.path.join(lab_dir, name + '.txt'), 'w') as f:
                    f.write('\n'.join(lines) + ('\n' if lines else ''))
                n_det = len(lines)
            rows.append([name + '.jpg', os.path.basename(path), idx, f'{sec:.2f}', f'{sharp:.1f}', n_det])

    with open(os.path.join(args.out, 'frames.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['image', 'video', 'frame', 'seconds', 'sharpness', 'prelabel_count'])
        w.writerows(rows)
    print(f'{len(rows)} 枚を {img_dir} に書いた。', flush=True)
    if args.prelabel:
        print('下書きラベルは必ず人が直してから make_clean_split.py に渡す（ml/README_training.md 参照）。')
    else:
        print('ラベルがないフレームは make_clean_split.py が読み飛ばす。ラベル付け（Roboflow / CVAT 等）が必要。')


if __name__ == '__main__':
    main()

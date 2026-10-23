#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
from ultralytics import YOLO


# baseline: settings of the model shipped up to v1.1.11 (runs/detect3).
# improved: no mirroring (kanji/pips must not be learned mirrored), weaker
# saturation jitter (keeps red fives distinguishable from normal fives), small
# rotations/shear for hand-held shots, no mixup/copy_paste (copy_paste was a
# no-op with box labels and mixup blends neighbouring tiles), longer schedule.
RECIPES = {
    'baseline': dict(
        close_mosaic=10, degrees=0.0, hsv_h=0.015, hsv_s=0.7, hsv_v=0.4,
        translate=0.1, scale=0.7, shear=0.0, perspective=0.0, fliplr=0.5,
        mosaic=1.0, mixup=0.1, copy_paste=0.15,
    ),
    # red_focus: shipped settings with only the two changes aimed at red
    # fives (lower saturation jitter; use with the oversampled data).
    'red_focus': dict(
        close_mosaic=10, degrees=0.0, hsv_h=0.015, hsv_s=0.35, hsv_v=0.4,
        translate=0.1, scale=0.7, shear=0.0, perspective=0.0, fliplr=0.5,
        mosaic=1.0, mixup=0.1, copy_paste=0.0,
    ),
    'improved': dict(
        close_mosaic=15, degrees=5.0, hsv_h=0.01, hsv_s=0.35, hsv_v=0.4,
        translate=0.1, scale=0.7, shear=2.0, perspective=0.0003, fliplr=0.0,
        mosaic=1.0, mixup=0.0, copy_paste=0.0,
    ),
}


def find_data_yaml(root: Path) -> Path:
    # Look for a data.yaml in root or one-level subfolders (roboflow export convention)
    candidates = list(root.rglob('data.yaml'))
    for p in candidates:
        try:
            txt = p.read_text(encoding='utf-8', errors='ignore')
            if 'train:' in txt and 'val:' in txt and 'names:' in txt:
                return p
        except Exception:
            pass
    raise FileNotFoundError(f"data.yaml not found under: {root}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True, help='Dataset directory containing data.yaml')
    ap.add_argument('--model', default='yolo11s', help='yolo11n/s/m/l/x or path to .pt')
    ap.add_argument('--weights', default='', help='Optional custom weights .pt to resume/finetune')
    ap.add_argument('--epochs', type=int, default=300)
    ap.add_argument('--batch', type=int, default=32)
    ap.add_argument('--imgsz', type=int, default=640)
    ap.add_argument('--device', default='0')
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--cache', action='store_true', help='Cache images in RAM to speed up dataloader')
    ap.add_argument('--recipe', choices=sorted(RECIPES), default='improved',
                    help='Augmentation recipe (baseline = shipped v1.1 model settings)')
    ap.add_argument('--name', default='detect', help='Run name under --project')
    ap.add_argument('--project', default='runs')
    args = ap.parse_args()

    data_path = Path(args.data).resolve()
    data_yaml = data_path if data_path.is_file() else find_data_yaml(data_path)

    # Pick model
    model_ckpt = args.weights or f"{args.model}.pt"
    model = YOLO(model_ckpt)

    results = model.train(
        data=str(data_yaml),
        imgsz=args.imgsz,
        epochs=args.epochs,
        batch=args.batch,
        device=args.device,
        pretrained=True,
        optimizer='auto',   # Let Ultralytics pick (AdamW/SGD)
        cos_lr=True,
        amp=True,
        patience=max(50, args.epochs // 3),
        cache='ram' if args.cache else False,
        workers=args.workers,
        multi_scale=False,
        project=args.project,
        name=args.name,
        **RECIPES[args.recipe],
    )
    print(results)


if __name__ == '__main__':
    sys.exit(main())

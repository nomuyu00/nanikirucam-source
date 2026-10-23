#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
from ultralytics import YOLO
import tensorflow as tf  # type: ignore


def find_data_yaml(root: Path) -> Path:
    candidates = list(root.rglob('data.yaml'))
    for p in candidates:
        try:
            txt = p.read_text(encoding='utf-8', errors='ignore')
            if 'train:' in txt and 'val:' in txt and 'names:' in txt:
                return p
        except Exception:
            pass
    raise FileNotFoundError(f"data.yaml not found under: {root}")


def latest_best(root: Path) -> Path:
    """Find the most recent best.pt under runs/*/weights.

    Supports both layouts:
    - runs/detect/weights/best.pt (fixed name)
    - runs/detect*/weights/best.pt (incremented names)
    - runs/detect/*/weights/best.pt (Ultralytics default train*/weights)
    """
    # Collect candidates across common patterns
    patterns = [
        '**/weights/best.pt',                # any nested weights folder
    ]
    candidates = []
    for pat in patterns:
        candidates.extend(root.glob(pat))

    # Fallback to historical hardcoded path if nothing found
    if not candidates:
        candidates.extend(Path('runs').glob('detect*/weights/best.pt'))
        direct = Path('runs/detect') / 'weights' / 'best.pt'
        if direct.exists():
            candidates.append(direct)

    # Pick the newest by mtime
    candidates = [p for p in candidates if p.is_file()]
    if not candidates:
        raise FileNotFoundError('No best.pt found under runs/*/weights')
    candidates.sort(key=lambda p: p.stat().st_mtime)
    return candidates[-1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True, help='Dataset directory containing data.yaml')
    ap.add_argument('--weights', default='', help='Path to best.pt (optional)')
    ap.add_argument('--imgsz', type=int, default=640)
    ap.add_argument('--out', default='', help='Output directory (default: <this script>/out)')
    ap.add_argument('--prefix', default='tflite', help='Output file prefix: <prefix>_fp32.tflite / <prefix>_int8.tflite')
    ap.add_argument('--skip-fp32', action='store_true', help='Only build the dynamic-range int8 model')
    args = ap.parse_args()

    data_path = Path(args.data).resolve()
    data_yaml = data_path if data_path.is_file() else find_data_yaml(data_path)
    print(f"Dataset: {data_yaml}")

    # Auto-detect latest best.pt unless explicitly provided
    w = Path(args.weights) if args.weights else latest_best(Path('runs'))
    print(f"Using weights: {w}")

    model = YOLO(str(w))

    # Save artifacts under the script's own 'out' directory
    out_dir = Path(args.out).resolve() if args.out else Path(__file__).resolve().parent / 'out'
    out_dir.mkdir(parents=True, exist_ok=True)

    # Export TF SavedModel via Keras path (offline-friendly)
    saved = model.export(format='saved_model', imgsz=args.imgsz, keras=True)
    sm_dir = Path(saved)

    # Build TFLite FP32
    if not args.skip_fp32:
        converter = tf.lite.TFLiteConverter.from_saved_model(str(sm_dir))
        tflite_fp32 = converter.convert()
        fp32_out = out_dir / f'{args.prefix}_fp32.tflite'
        fp32_out.write_bytes(tflite_fp32)
        print(f"Saved: {fp32_out}")

    # Dynamic-range quantization: int8 weights, float32 input/output.
    # The app feeds float32 RGB/255 and decodes float32 outputs, so a fully
    # int8 model (int8 I/O) would need a different input path. Full INT8
    # previously failed silently and fell back to this anyway.
    converter = tf.lite.TFLiteConverter.from_saved_model(str(sm_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_int8 = converter.convert()
    int8_out = out_dir / f'{args.prefix}_int8.tflite'
    int8_out.write_bytes(tflite_int8)
    print(f"Saved (dynamic range, float I/O): {int8_out}")


if __name__ == '__main__':
    sys.exit(main())

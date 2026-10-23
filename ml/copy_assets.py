#!/usr/bin/env python3
"""Copy exported TFLite models and the label list into the Flutter assets."""
import argparse
import shutil
from pathlib import Path

import yaml


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True, help='data.yaml or a folder containing it')
    ap.add_argument('--tflite-int8', required=True)
    ap.add_argument('--tflite-fp32', required=True)
    ap.add_argument('--labels-out', required=True)
    ap.add_argument('--model-out', required=True)
    ap.add_argument('--model-fp32-out', required=True)
    args = ap.parse_args()

    data = Path(args.data)
    if data.is_dir():
        data = next(p for p in data.rglob('data.yaml'))
    names = yaml.safe_load(data.read_text(encoding='utf-8'))['names']
    if isinstance(names, dict):
        names = [names[i] for i in sorted(names)]
    # The app maps output class indices to this list, so the order must match.
    Path(args.labels_out).write_text('\n'.join(names) + '\n', encoding='utf-8')
    shutil.copyfile(args.tflite_int8, args.model_out)
    shutil.copyfile(args.tflite_fp32, args.model_fp32_out)
    print(f'Copied {len(names)} labels and models into the app assets')


if __name__ == '__main__':
    main()

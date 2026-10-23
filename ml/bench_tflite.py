#!/usr/bin/env python3
"""tflite の入出力形状・サイズと、PC の CPU（XNNPACK）での 1 推論の時間を測る。

実機（スマホ）の fps ではない。モデル同士の相対比較と、アプリのデコーダが読める形か
（入力 [1,S,S,3] float32、出力 [1,4+クラス数,アンカー数]）の確認用。

使い方:
  python -I -B bench_tflite.py [--threads 4] [--runs 30] model_a.tflite model_b.tflite ...
"""
import argparse
import os
import statistics
import time

import numpy as np

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:  # 古い環境
    import tensorflow as tf

    Interpreter = tf.lite.Interpreter


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--threads', type=int, default=4)
    ap.add_argument('--runs', type=int, default=30)
    ap.add_argument('models', nargs='+')
    args = ap.parse_args()

    for path in args.models:
        it = Interpreter(model_path=path, num_threads=args.threads)
        it.allocate_tensors()
        inp = it.get_input_details()[0]
        outs = it.get_output_details()
        shape = inp['shape'].tolist()
        x = np.random.default_rng(0).random(shape, dtype=np.float32)
        if inp['dtype'] != np.float32:
            x = (x * 255).astype(inp['dtype'])
        times = []
        for k in range(args.runs + 3):
            it.set_tensor(inp['index'], x)
            t0 = time.perf_counter()
            it.invoke()
            if k >= 3:  # 最初の 3 回は捨てる
                times.append((time.perf_counter() - t0) * 1000)
        print(
            f"{os.path.basename(path)}: {os.path.getsize(path) / 1e6:.1f} MB  "
            f"in {shape} {inp['dtype'].__name__}  "
            f"out {[(o['shape'].tolist(), o['dtype'].__name__) for o in outs]}  "
            f"threads={args.threads}  median {statistics.median(times):.1f} ms  "
            f"min {min(times):.1f} ms  (n={len(times)})",
            flush=True,
        )


if __name__ == '__main__':
    main()

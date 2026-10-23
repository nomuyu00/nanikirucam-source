#!/usr/bin/env bash
# ライブ用の軽量モデル（YOLO11n / YOLO11s）を、クリーン分割の baseline レシピで学習する。
#
# 使い方（WSL。あがりかむの環境は読むだけで、pip install などはしない）:
#   bash ml/train_live.sh n 100          # YOLO11n を 100 エポック
#   bash ml/train_live.sh s 100 480      # YOLO11s を入力 480 で
#
# 環境変数:
#   WORK  作業ディレクトリ（既定 ~/work/nanikiru-ml。/mnt/d 越しの I/O を避けるため WSL のホーム）
#   PY    Python（既定: あがりかむの .mamba/envs/yolo11。torch 2.5 + ultralytics 8.3 + onnx2tf）
#   BATCH / WORKERS  バッチ・ワーカー数（既定 64 / 12）
#   DATA  学習に使う data yaml（既定 $WORK/ds_clean/data_baseline.yaml）。斜めデータを足した
#         分割なら DATA=$WORK/ds_clean2/data_baseline.yaml
#   TAG   実行名の接尾辞（既定なし。runs/live_n_<TAG>）
#   INIT  初期重み（既定は yolo11{n,s}.pt。前の best.pt から追い学習するときだけ指定）
#
# 前提: $WORK/ds_clean がある（`python -I -B ml/make_clean_split.py <master.v7i> $WORK/ds_clean`）、
#       $WORK/yolo11{n,s}.pt がある（ml/pretrained/ からコピー）。
set -euo pipefail

SIZE=${1:?"n か s"}
EPOCHS=${2:-100}
IMGSZ=${3:-640}
WORK=${WORK:-$HOME/work/nanikiru-ml}
PY=${PY:-/home/nomuyu/workspace/iOS/agari_cam/Scripts/.mamba/envs/yolo11/bin/python}
BATCH=${BATCH:-64}
WORKERS=${WORKERS:-12}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

DATA=${DATA:-$WORK/ds_clean/data_baseline.yaml}
NAME="live_${SIZE}"
if [[ "$IMGSZ" != "640" ]]; then NAME="${NAME}_${IMGSZ}"; fi
if [[ -n "${TAG:-}" ]]; then NAME="${NAME}_${TAG}"; fi
INIT_ARGS=()
if [[ -n "${INIT:-}" ]]; then INIT_ARGS=(--weights "$INIT"); fi

cd "$WORK"
# 設定は作業ディレクトリに閉じる。足りない部品の自動 pip install は止める（共有環境を壊さない）。
export YOLO_CONFIG_DIR="$WORK/.ultralytics"
export YOLO_AUTOINSTALL=False

"$PY" -I -B "$HERE/train_yolo11.py" \
  --data "$DATA" \
  --model "yolo11${SIZE}" \
  ${INIT_ARGS[@]+"${INIT_ARGS[@]}"} \
  --recipe baseline \
  --epochs "$EPOCHS" \
  --batch "$BATCH" \
  --imgsz "$IMGSZ" \
  --workers "$WORKERS" \
  --cache \
  --project "$WORK/runs" \
  --name "$NAME"

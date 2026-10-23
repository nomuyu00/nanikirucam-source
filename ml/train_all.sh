#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

function usage() {
  cat <<USAGE
Usage: $0 --dataset <path> [--dora-dataset <path>] [--size yolo11s] [--epochs 300] [--batch 32] [--device 0] [--profile 10h] [--clean-run]

Examples:
  $0 --dataset ../../master.v7i.yolov11 --profile 10h --device 0
  $0 --dataset /home/user/ds --dora-dataset /home/user/dora_ds --clean-run
USAGE
}

DATASET=""
DORA_DATASET=""
SIZE="yolo11s"
EPOCHS=300
BATCH=32
DEVICE=0
PROFILE=""
CLEAN_RUN=0
USER_EPOCHS=0
USER_SIZE=0
WORKERS=""
USE_CACHE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dataset) DATASET="$2"; shift 2;;
    --dora-dataset) DORA_DATASET="$2"; shift 2;;
    --size) SIZE="$2"; USER_SIZE=1; shift 2;;
    --epochs) EPOCHS="$2"; USER_EPOCHS=1; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --device) DEVICE="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --clean-run) CLEAN_RUN=1; shift 1;;
    --workers) WORKERS="$2"; shift 2;;
    --cache) USE_CACHE=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$DATASET" ]]; then
  echo "--dataset is required" >&2
  usage
  exit 1
fi

# Convert Windows WSL UNC path to Linux path if needed
if [[ "$DATASET" == \\wsl.localhost* ]]; then
  # Example: \\wsl.localhost\Ubuntu-20.04\home\user\path -> /home/user/path
  DATASET="/$(echo "$DATASET" | sed 's#^\\\\wsl.localhost\\[^\\]*\\##' | tr '\\' '/')"
fi
if [[ -n "$DORA_DATASET" && "$DORA_DATASET" == \\wsl.localhost* ]]; then
  DORA_DATASET="/$(echo "$DORA_DATASET" | sed 's#^\\\\wsl.localhost\\[^\\]*\\##' | tr '\\' '/')"
fi

echo "[RUN] Dataset:        $DATASET"
if [[ -n "$DORA_DATASET" ]]; then echo "[RUN] Dora dataset:    $DORA_DATASET"; fi
echo "[RUN] Model size:     $SIZE"
echo "[RUN] Epochs/Batch:   $EPOCHS / $BATCH"
echo "[RUN] Device:         $DEVICE"
if [[ -n "$PROFILE" ]]; then echo "[RUN] Profile:         $PROFILE"; fi

bash "$HERE/bootstrap.sh"

source "$HERE/.venv/bin/activate"

YOLO_EXTRA_ARGS=""
if [[ -n "$WORKERS" ]]; then
  YOLO_EXTRA_ARGS+=" --workers $WORKERS"
fi
if [[ $USE_CACHE -eq 1 ]]; then
  YOLO_EXTRA_ARGS+=" --cache"
fi
if [[ "$PROFILE" == "10h" ]]; then
  # Aim ~10h on 4090: yolo11s, ~40 epochs, cache images, more workers (only if user didn't pin them)
  if [[ $USER_SIZE -eq 0 ]]; then SIZE="yolo11s"; fi
  if [[ $USER_EPOCHS -eq 0 ]]; then EPOCHS=40; fi
  BATCH=${BATCH:-64}
  if [[ -z "$WORKERS" ]]; then YOLO_EXTRA_ARGS+=" --workers 12"; fi
  if [[ $USE_CACHE -eq 0 ]]; then YOLO_EXTRA_ARGS+=" --cache"; fi
fi
export YOLO_EXTRA_ARGS

if [[ $CLEAN_RUN -eq 1 ]]; then
  echo "[CLEAN] Removing previous outputs (runs/detect, out, copied assets)"
  rm -rf "$HERE/out" || true
  rm -rf "$HERE/../assets/models/mahjong_yolo_"* "$HERE/../assets/labels/tiles_labels.txt" || true
  rm -rf "$HERE/../assets/models/dora_indicator_yolo_"* "$HERE/../assets/labels/dora_labels.txt" || true
  rm -rf "$HERE/../../runs/detect" || rm -rf runs/detect || true
fi

make -C "$HERE" all \
  DATASET_DIR="$DATASET" \
  MODEL_SIZE="$SIZE" \
  EPOCHS="$EPOCHS" \
  BATCH="$BATCH" \
  DEVICE="$DEVICE" \
  $( [[ -n "$DORA_DATASET" ]] && echo DORA_DATASET_DIR="$DORA_DATASET" )

echo "[DONE] Artifacts copied into agari_cam/assets. Build the app to use them."

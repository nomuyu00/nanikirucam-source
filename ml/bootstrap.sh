#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VENV="$HERE/.venv"

create_with_venv() {
  echo "[BOOTSTRAP] Creating Python venv at $VENV"
  python3 -m venv "$VENV" || return 1
  return 0
}

create_with_virtualenv() {
  echo "[BOOTSTRAP] Creating venv via virtualenv at $VENV"
  if ! command -v virtualenv >/dev/null 2>&1; then
    echo "[BOOTSTRAP] virtualenv not found; installing to user site..."
    if command -v python3 >/dev/null 2>&1; then
      python3 -m pip install --user virtualenv || pip3 install --user virtualenv || true
    fi
  fi
  if command -v virtualenv >/dev/null 2>&1; then
    virtualenv "$VENV" || return 1
    return 0
  fi
  return 1
}

ensure_env() {
  if [[ -d "$VENV" && -f "$VENV/bin/activate" ]]; then
    return 0
  fi
  create_with_venv || create_with_virtualenv || {
    echo "[BOOTSTRAP][FATAL] Could not create a Python virtual environment.\n" \
         "Please ensure python3 and pip are installed (on Ubuntu: sudo apt install -y python3 python3-pip python3-venv)." >&2
    exit 1
  }
}

ensure_env

if [[ ! -f "$VENV/bin/activate" ]]; then
  echo "[BOOTSTRAP][FATAL] venv activation script missing at $VENV/bin/activate" >&2
  exit 1
fi

source "$VENV/bin/activate"
python -m pip install --upgrade pip || true

echo "[BOOTSTRAP] Installing PyTorch CUDA 12.1 wheels (GPU if available)"
pip install --index-url https://download.pytorch.org/whl/cu121 torch torchvision torchaudio || {
  echo "[BOOTSTRAP] CUDA wheel failed, falling back to CPU wheels" >&2
  pip install torch torchvision torchaudio
}

echo "[BOOTSTRAP] Installing Ultralytics"
pip install "ultralytics>=8.3.0" || true

echo "[BOOTSTRAP] Installing exporters and tools"
pip install onnx onnxruntime pyyaml || true

echo "[BOOTSTRAP] Installing TensorFlow (for TFLite export)"
if ! pip install "tensorflow==2.15.*"; then
  echo "[BOOTSTRAP] TensorFlow 2.15 not available for this Python. Falling back to 2.13.*"
  pip install "tensorflow==2.13.*" || true
fi

# coremltools is optional for iOS CoreML export; best-effort.
pip install "coremltools>=7.0" || true

python - <<'PY'
try:
    import torch
    print('[BOOTSTRAP] Torch version:', torch.__version__)
    print('[BOOTSTRAP] CUDA available:', torch.cuda.is_available())
    if torch.cuda.is_available():
        print('[BOOTSTRAP] CUDA device:', torch.cuda.get_device_name(0))
    import ultralytics
    print('[BOOTSTRAP] Ultralytics version:', ultralytics.__version__)
except Exception as e:
    print('[BOOTSTRAP] Torch check failed:', e)
PY

echo "[BOOTSTRAP] Environment ready."

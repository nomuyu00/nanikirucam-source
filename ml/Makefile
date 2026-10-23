SHELL := /bin/bash

# User-tunable
DATASET_DIR ?= ../../dataset  # path to folder containing data.yaml
DORA_DATASET_DIR ?=           # optional: separate dataset for dora indicator submodel
MODEL_SIZE  ?= yolo11s        # yolo11n/yolo11s/yolo11m/yolo11l/yolo11x
EPOCHS      ?= 300
BATCH       ?= 32
IMGSZ      ?= 640
DEVICE     ?= 0              # CUDA device index
WEIGHTS    ?=                 # optional: path to custom weights .pt

# Derived
# Prefer micromamba env Python, then local venv, then python3, then python
PY := $(shell \
    if [ -x .mamba/envs/yolo11/bin/python ]; then echo .mamba/envs/yolo11/bin/python; \
    elif [ -x .venv/bin/python ]; then echo .venv/bin/python; \
    elif command -v python3 >/dev/null 2>&1; then echo python3; \
    else echo python; fi)
RUNS := runs/detect

# Keep Ultralytics settings inside the repo (workspace-safe)
# Ultralytics reads YOLO_CONFIG_DIR for its settings path
export YOLO_CONFIG_DIR := $(CURDIR)/.ultralytics

.PHONY: train export copy assets all clean

all: train export copy $(if $(DORA_DATASET_DIR),train_dora export_dora copy_dora,)

train:
	@echo "[YOLO] Training $(MODEL_SIZE) on $(DATASET_DIR) ..."
	$(PY) train_yolo11.py \
		--data "$(DATASET_DIR)" \
		--model "$(MODEL_SIZE)" \
		--epochs $(EPOCHS) \
		--batch $(BATCH) \
		--imgsz $(IMGSZ) \
		--device $(DEVICE) $(if $(WEIGHTS),--weights "$(WEIGHTS)",) $$(echo $$YOLO_EXTRA_ARGS)

export:
	@echo "[YOLO] Exporting TFLite (int8 + fp32) ..."
	$(PY) export_yolo11.py \
		--data "$(DATASET_DIR)" \
		--imgsz $(IMGSZ) \
		$(if $(WEIGHTS),--weights "$(WEIGHTS)",)

copy: assets
	@echo "[YOLO] Copying artifacts into Flutter assets ..."
	$(PY) copy_assets.py \
		--data "$(DATASET_DIR)" \
		--tflite-int8 "out/tflite_int8.tflite" \
		--tflite-fp32 "out/tflite_fp32.tflite" \
		--labels-out "../assets/labels/tiles_labels.txt" \
		--model-out "../assets/models/mahjong_yolo_int8.tflite" \
		--model-fp32-out "../assets/models/mahjong_yolo_fp32.tflite"

train_dora:
	@echo "[YOLO] Training DORA submodel on $(DORA_DATASET_DIR) ..."
	$(PY) train_yolo11.py \
		--data "$(DORA_DATASET_DIR)" \
		--model "$(MODEL_SIZE)" \
		--epochs $(EPOCHS) \
		--batch $(BATCH) \
		--imgsz $(IMGSZ) \
		--device $(DEVICE)

export_dora:
	@echo "[YOLO] Exporting DORA submodel TFLite ..."
	$(PY) export_yolo11.py \
		--data "$(DORA_DATASET_DIR)" \
		--imgsz $(IMGSZ)
	@# Move into dora-specific names
	mv -f out/tflite_int8.tflite out/dora_tflite_int8.tflite
	mv -f out/tflite_fp32.tflite out/dora_tflite_fp32.tflite

copy_dora: assets
	@echo "[YOLO] Copying DORA submodel artifacts ..."
	$(PY) copy_assets.py \
		--data "$(DORA_DATASET_DIR)" \
		--tflite-int8 "out/dora_tflite_int8.tflite" \
		--tflite-fp32 "out/dora_tflite_fp32.tflite" \
		--labels-out "../assets/labels/dora_labels.txt" \
		--model-out "../assets/models/dora_indicator_yolo_int8.tflite" \
		--model-fp32-out "../assets/models/dora_indicator_yolo_fp32.tflite"

assets:
	mkdir -p ../assets/models ../assets/labels out $(YOLO_CONFIG_DIR)

clean:
	rm -rf out $(RUNS)/train* __pycache__

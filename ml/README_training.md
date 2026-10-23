YOLOv11 Mahjong Tile Detector — Training & Export (TFLite)

Overview
- Trains Ultralytics YOLOv11 on your Roboflow dataset (already downloaded at repo root) with accuracy-focused settings.
- Exports both int8 (quantized) and float32 TFLite models for mobile CPU inference.
- Generates labels file and copies artifacts into the Flutter app’s assets path expected by the app.

Prerequisites (4090 workstation)
- OS: Linux/Windows (WSL ok) with CUDA 12.x for NVIDIA RTX 4090.
- Conda (recommended) or Python 3.10–3.12 venv.

Conda setup (recommended)
1) Create env with CUDA-enabled PyTorch and Ultralytics:
   conda create -n yolo11 python=3.10 -y
   conda activate yolo11
   conda install -c nvidia -c pytorch pytorch torchvision torchaudio pytorch-cuda=12.1 -y
   pip install ultralytics>=8.3.0 onnx onnxruntime tensorflow==2.15.*

Pip-only (ensure correct PyTorch wheel)
   python -m venv .venv && source .venv/bin/activate  # (Windows: .venv\Scripts\activate)
   pip install --upgrade pip
   pip install --index-url https://download.pytorch.org/whl/cu121 torch torchvision torchaudio
   pip install ultralytics>=8.3.0 onnx onnxruntime tensorflow==2.15.*

Dataset
- Place/confirm your Roboflow-exported YOLO dataset at repo root. The folder should include a `data.yaml` pointing to train/val/test and `names` list.
- If not at root, pass DATASET_DIR to scripts or adjust Makefile variables.

One‑shot command (train → export → copy to app)
   cd agari_cam/Scripts
   make all DATASET_DIR=../../your_dataset_folder MODEL_SIZE=yolo11s EPOCHS=300 BATCH=32

Artifacts
- TFLite (int8): agari_cam/assets/models/mahjong_yolo_int8.tflite
- TFLite (fp32): agari_cam/assets/models/mahjong_yolo_fp32.tflite
- Labels: agari_cam/assets/labels/tiles_labels.txt

Tips for highest accuracy
- Prefer `MODEL_SIZE=yolo11s` or `yolo11m` for mobile real-time. `yolo11n` is fastest but less accurate, `yolo11l/x` are more accurate but heavy for phones.
- Increase `EPOCHS` (e.g., 400–600) with `patience=100`. Use larger `BATCH` if VRAM allows.
- Keep `imgsz=640` to match Flutter app pipeline.
- Ensure `names` include red fives (aka) if you want the app to badge red tiles.

Reproducible runs
- All outputs go under `runs/detect/train*`. Scripts auto-pick the latest `best.pt` for export unless `WEIGHTS=...` is provided.


Leakage-free evaluation (2026-10)
- The Roboflow export (master.v7i) puts crops/augmentations of the same photo
  into train, valid and test (88% of multi-tile valid/test images match a
  train image). Its reported mAP (~0.99) is therefore optimistic.
- Build a split where every copy of one source photo stays in one split, plus
  extra copies of images with red fives / tile backs for the improved recipe:
    .mamba/envs/yolo11/bin/python -I make_clean_split.py ../../../master.v7i.yolov11 /path/to/ds_clean
- Train both recipes on the same split (`--recipe baseline` reproduces the
  model shipped up to v1.1.11; `improved` disables mirroring, lowers
  saturation jitter, adds small rotations/shear, drops mixup/copy_paste and
  trains longer):
    python train_yolo11.py --data /path/to/ds_clean/data_baseline.yaml --model yolo11m --recipe baseline --epochs 50 --cache --name clean_baseline
    python train_yolo11.py --data /path/to/ds_clean/data_improved.yaml --model yolo11m --recipe improved --epochs 80 --cache --name clean_improved
- Compare on the held-out test split, as-is and "app-like" (tiles shrunk to
  55%, blur, JPEG q=60), with mAP and hand exact-match:
    python -I eval_models.py /path/to/ds_clean /path/to/report.json name=runs/<run>/weights/best.pt ...
- Compare the app's full-frame vs split-row recognition on a high-res canvas:
    python -I sim_pipeline.py /path/to/ds_clean /path/to/sim.json name=runs/<run>/weights/best.pt
- Export the chosen weights (fp32 + dynamic-range int8, both float I/O) and
  copy them into the app:
    python export_yolo11.py --data /path/to/ds_clean/data_baseline.yaml --weights runs/<run>/weights/best.pt
    python copy_assets.py --data /path/to/ds_clean/data_baseline.yaml --tflite-int8 out/tflite_int8.tflite --tflite-fp32 out/tflite_fp32.tflite --labels-out ../assets/labels/tiles_labels.txt --model-out ../assets/models/mahjong_yolo_int8.tflite --model-fp32-out ../assets/models/mahjong_yolo_fp32.tflite


ライブ用モデル（YOLO11n / YOLO11s、2026-10-22）
==============================================

ライブナビ（1 フレーム 1 推論、目標 5 fps 以上）用の軽量モデル。写真用（YOLO11m、`detect3`）とは別に、
クリーン分割（元写真単位。上の「Leakage-free evaluation」）の train だけで学習し、同じ test で評価した。

### 作ったもの

| アプリのアセット | 中身 | サイズ | 入力 → 出力 |
| --- | --- | --- | --- |
| `app/assets/models/mahjong_yolo_live_s_int8.tflite`（**既定**） | YOLO11s、入力 640 | 9.8 MB | `[1,640,640,3]` → `[1,42,8400]` |
| `app/assets/models/mahjong_yolo_live_n_int8.tflite` | YOLO11n、入力 640 | 2.9 MB | 同上 |
| `app/assets/models/mahjong_yolo_live_n480_int8.tflite` | YOLO11n、入力 480 | 2.8 MB | `[1,480,480,3]` → `[1,42,4725]` |

- いずれも「動的レンジ量子化の int8 重み + float32 の入出力」。写真用 `mahjong_yolo_int8.tflite` と同じ方式で、
  同じデコーダ（`app/lib/ml/live_yolo_decoder.dart`）が読める（出力は `[1, 4+38, アンカー数]`、座標 0〜1、
  クラスは `assets/labels/tiles_labels.txt` の順）。
- 学習済み重み: `ml/weights/live_n/`、`live_s/`、`live_n_480/`（`best.pt`、`args.yaml`、`results.csv`）。gitignore 済み。
- アプリの選び方: 既定は **s から始め、端末が遅ければセッション中に n → n 480 へ自動で落ちる**（下の「自動切り替え」）。
  Remote Config `live_model_variant` = `live_s_int8` / `live_n_int8` / `live_n480_int8` / `int8`（従来の写真用）を
  入れると、そのモデルに固定して自動切り替えをしない。空や未知の名前は無視（既定のまま、自動切り替えあり）。
  ライブ用が読み込めないとき（アセットなし・破損）は写真用 int8 に自動で落ちる（`app/lib/ml/live_model_loader.dart`）。
  入力サイズ（640 / 480）はモデルの入力形状から読む。

### 学習設定

- 分割: `make_clean_split.py`（`master.v7i`、725 グループ）→ train 9,384 / valid 1,551 / test 2,200 枚
  （test の手牌画像 = GT 12 枚以上: 1,141 枚、うち 13 か 14 枚の画像 801 枚）。
- `train_yolo11.py --recipe baseline`（あがりかむの出荷モデル `detect3` と同じ増強。`improved` 系は完全一致で引き分けだったため不採用）、
  初期重み `yolo11n.pt` / `yolo11s.pt`、AdamW 自動、`cos_lr`、`amp`、batch 64、`cache=ram`、**100 エポック**
  （`detect3` は yolo11m を 50 エポック）、`patience=50`（打ち切りなし）。
- 所要時間（RTX 4090、他の作業と並走）: n 640 = 65 分、s 640 = 80 分、n 480 = 37 分。
- 実行は `ml/train_live.sh`（下の手順）。環境はあがりかむの `.mamba/envs/yolo11`（Python 3.10、torch 2.5.1、
  ultralytics 8.3.191、TF 2.19.1、onnx2tf 1.28.2）を読むだけで使い、`YOLO_AUTOINSTALL=False` で自動 pip を止めている。

### 結果（クリーン分割の test）

「13/14 枚の完全一致」は、手牌画像のうち GT がちょうど 13 か 14 枚の 801 枚で、全牌が IoU>=0.5・同じクラスで一致した割合。
「ゆるい」= 確度 0.10 以上の検出で全 GT 牌が一致（余計な検出は許す）。「ライブ」= 確度 0.25 以上の検出だけで、全牌が一致し
**検出数も GT と同じ**（ライブの確度しきい値 0.25 と同じ。tflite 版はアプリのデコーダと同じ手順の Python 版 `eval_tflite.py` で測った）。
「アプリ相当」= 牌を 55% に縮め、ぼかし、JPEG q=60 にした条件（小さい牌・手持ちに近い。`eval_models.py` の `app_like_test`）。

| モデル | mAP50 | mAP50-95 | 13/14 ゆるい | 13/14 ライブ（PT） | 13/14 ライブ（tflite int8） | アプリ相当 13/14 ライブ（PT） | PC の CPU 1 推論（4 スレッド, int8） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| YOLO11n 640（自動切り替えの 2 段目） | 0.9939 | 0.8719 | 97.5% | 94.8% | 94.6% | 19.5% | 11.3 ms |
| YOLO11n 480（3 段目） | 0.9940 | 0.8691 | 94.6% | 93.6% | 93.4% | 15.2% | 6.1 ms |
| YOLO11s 640（**既定**・1 段目） | 0.9947 | 0.8854 | 98.9% | 98.5% | 98.6% | 36.8% | 24.9 ms |
| YOLO11m 640（`clean_baseline`、50 エポック、比較用） | 0.9947 | 0.8873 | 98.3% | 97.3% | 96.6% | 38.7% | 68.9 ms |
| YOLO11m 640（`detect3`、現行の写真用。**リークあり**） | 0.9950 | 0.9642 | 99.9% | 99.4% | 99.6%（アセットの int8） | 68.7% | 約 69 ms |

- `detect3` は元の train に test の元写真の水増し写しを含むので、この test では水増しされる（mAP50-95 が 0.89 → 0.96、
  アプリ相当で 38.7% → 68.7%）。公平な比較は `clean_baseline`。
- fp32 の tflite と int8 の差はほぼ無い（n: 94.8% / 94.6%、s: 98.5% / 98.6%）。tflite への変換で精度は落ちていない
  （n は PT と tflite fp32 がどちらも 94.76%）。
- クリーン条件の mAP50 は 3 つともほぼ同じ。差は **mAP50-95（枠の精度）と、小さい牌・ぼやけた条件**に出る。
  n は「アプリ相当」で 19.5% まで落ちる（s は 36.8%）。ライブの 640 入力は牌が約 32px（720p の縦向きで中央の正方形を 640 に縮めた場合）なので
  「アプリ相当」に近い。時間方向の多数決で補う前提だが、n の単フレームは小さい牌に弱い。
- 手牌画像の中の赤 5 は n / s とも全て正しいクラスで検出できた（`red_five_accuracy` 100%）。赤 5 の mAP50-95 は 0.81〜0.90。
- 計測スクリプト: `eval_models.py`（PT、mAP と完全一致）、`eval_tflite.py`（tflite。アプリのデコーダと同じ手順）、
  `bench_tflite.py`（PC の CPU の ms。**実機の fps ではない**）。

### 机上の fps の見積もり

写真用 m（int8）は PC で約 69 ms、設計書の見積もりで実機 2〜4 fps（250〜500 ms）。同じ比率を当てると、実機の 1 推論は
s 640 が m の約 36%（90〜180 ms、5.5〜11 fps）、n 640 が約 16%（40〜80 ms、12〜25 fps）、n 480 が約 9%（22〜45 ms）。
前処理（YUV → RGB・縮小、`preprocessMicros`）が別に 10〜30 ms かかる。**実測は実機で**（下の手順）。

### 手順（WSL の Ubuntu-20.04）

```bash
W=~/work/nanikiru-ml; mkdir -p $W; cd $W
ML=/mnt/d/ProgramFiles/IdeaProjects/nanikirucam/ml
cp $ML/pretrained/yolo11{n,s}.pt .                                  # 初期重み（学習のカレントに置く）
cp $ML/calibration_image_sample_data_20x128x128x3_float32.npy .     # 書き出しが要る
mkdir -p export reports
PY=/home/nomuyu/workspace/iOS/agari_cam/Scripts/.mamba/envs/yolo11/bin/python   # あがりかむの環境（読むだけ）

# 1) クリーン分割（約 30 秒）
$PY -I -B $ML/make_clean_split.py /home/nomuyu/workspace/iOS/master.v7i.yolov11 $W/ds_clean

# 2) 学習（100 エポック）。GPU は 1 本ずつ（s は GPU メモリ約 17GB、RAM も大きく使う: cache=ram）
bash $ML/train_live.sh n 100          # runs/live_n
bash $ML/train_live.sh s 100          # runs/live_s
bash $ML/train_live.sh n 100 480      # runs/live_n_480

# 3) 評価（PT）。名前=重み[@入力サイズ]。結果は reports/*.json
export YOLO_CONFIG_DIR=$W/.ultralytics YOLO_AUTOINSTALL=False
$PY -I -B $ML/eval_models.py $W/ds_clean $W/reports/eval_pt.json \
    live_n=runs/live_n/weights/best.pt live_s=runs/live_s/weights/best.pt \
    live_n_480=runs/live_n_480/weights/best.pt@480 clean_baseline_m=$ML/weights/clean_baseline/best.pt

# 4) tflite 書き出し（動的レンジ int8 + fp32。--skip-fp32 で int8 だけ）→ tflite 側の評価と PC の ms
cd $W/export
$PY -I -B $ML/export_yolo11.py --data $W/ds_clean/data_baseline.yaml --weights $W/runs/live_n/weights/best.pt \
    --out $W/export --prefix live_n_640            # live_n_640_fp32.tflite / live_n_640_int8.tflite
$PY -I -B $ML/export_yolo11.py --data $W/ds_clean/data_baseline.yaml --weights $W/runs/live_n_480/weights/best.pt \
    --imgsz 480 --out $W/export --prefix live_n_480
$PY -I -B $ML/eval_tflite.py $W/ds_clean $W/reports/tflite_eval.json live_n_640_int8=$W/export/live_n_640_int8.tflite
$PY -I -B $ML/bench_tflite.py --threads 4 $W/export/live_n_640_int8.tflite $W/export/live_s_640_int8.tflite

# 5) アプリに入れる（名前に注意）と、重みを D: に残す
cp $W/export/live_n_640_int8.tflite $ML/../app/assets/models/mahjong_yolo_live_n_int8.tflite
cp $W/export/live_s_640_int8.tflite $ML/../app/assets/models/mahjong_yolo_live_s_int8.tflite
cp $W/export/live_n_480_int8.tflite $ML/../app/assets/models/mahjong_yolo_live_n480_int8.tflite
for r in live_n live_s live_n_480; do mkdir -p $ML/weights/$r; cp $W/runs/$r/{weights/best.pt,args.yaml,results.csv} $ML/weights/$r/; done
```

- ラベル（`app/assets/labels/tiles_labels.txt`）は変えていない。データのクラス順が変わったときだけ `copy_assets.py` で作り直す。
- 書き出しのカレントには `calibration_image_sample_data_20x128x128x3_float32.npy` が要る（無いとネットから取りに行く）。
- ultralytics の保存先は `YOLO_CONFIG_DIR` で作業ディレクトリに閉じる。あがりかむのディレクトリには何も書かない。
- 組み込みの確認は、アプリのテスト（`app/test/ml/model_assets_test.dart` がアセットの存在と tflite のヘッダを調べる）。

### 自動切り替え（遅い端末で s → n → n 480）

ライブを始めたあと、「前処理 + 推論」の時間（`LiveDetections.preprocessMicros + inferenceMicros`）を測る。

1. 最初の **10 フレームを捨て**（読み込み直後は遅い）、続く **20 フレームの中央値**を出す（平均ではない）。
2. 中央値が **180 ms を超えたら**、そのセッション中に 1 段速いモデルへ切り替える（s → n 640 → n 480）。
   切り替えたらまた 10 + 20 フレームで測り直し、まだ 180 ms を超えていればもう 1 段。**戻さない**。n 480 より先はない。
   180 ms 以下なら、そのモデルで固定（以後は測り直さない）。
3. 切り替えの間（新しいモデルを開く間）は検出を止め、追跡（TileTracker）をやり直す。案内は出ず、
   新しいモデルで同じ手がもう一度安定してから出る（案内の回数や採用率は数え直さない）。
4. 落ちた段は端末に保存（SharedPreferences `live_model_tier_v1` = `{tier, app}`）し、次回はその段から始める。
   **アプリのバージョンが変わったとき**と、**Remote Config の `live_model_variant` が明示されたとき**は保存を捨て、s から測り直す。
5. Remote Config で variant が明示されていれば、自動切り替えも保存した段も使わない（運用で固定できる）。
   読み込み失敗で写真用 int8 に落ちているときも切り替えない。
6. 新しいモデルを開けなかったときは、今のモデルのまま続け、もう切り替えない。

**閾値を変える場所**: `app/lib/live/live_model_tier.dart` の `LiveModelTiering`
（`defaultSlowThresholdMs = 180`、`defaultWarmupFrames = 10`、`defaultSampleFrames = 20`、段は `ModelConfig.liveTiers`）。
計測イベントは追加していない（debug 表示のみ）。保存を消すには、アプリのデータを消すか、アプリを更新する。

### 実機の fps の測り方（ユーザー向け）

1. `flutter run --profile`（または `--debug`）で実機に入れ、Live を開く。左上に
   `推論ms+前処理ms 目標fps モデル名 med 中央値ms` が出る（例 `62ms+14ms 6fps mahjong_yolo_live_s_int8 med 83ms`）。
   `med` は上の自動切り替えと同じ中央値（最初の 10 フレームを除く、集めた分。切り替え直後は `-`）。
   切り替え中は `(switching)`、写真用に落ちていれば `mahjong_yolo_int8 (fallback)`。
2. 手牌を 30〜45° の斜めから写して 30 秒ほど。`med` を読み、`1000 / med` が出せる fps の上限。
   180 ms を超える端末では、数秒後にモデル名が `…_n_int8`（さらに `…_n480_int8`）に変わる。
3. モデルを固定して比べたいときは Remote Config の `live_model_variant`（`live_s_int8` / `live_n_int8` / `live_n480_int8`）。
   Remote Config なしで試すなら、`app/lib/ml/model_config.dart` の `defaultLiveModel` を書き換える
   （自動切り替えは残る。止めるなら `live_providers.dart` の `liveModelTieringProvider` が null を返すようにする）。
4. 判断の目安: s の `med` が 200 ms 以下（5 fps 以上）なら s のままでよい（13/14 完全一致 98.5% 対 n の 94.8%、
   小さい牌の条件で約 2 倍）。多くの端末で 180 ms を超えて n に落ちるなら、閾値か既定を見直す。
   発熱で遅くなる点（`thermalState`）も見る（自動切り替えは最初の区間だけで決めるので、後からの発熱では落ちない）。

### 斜め 30〜45° のデータを足して学習し直す

仕様で v1.0 のライブに必須の 2,000 枚。動画から抽出し、下書きラベルを直して、元写真と別に分割する。

1. **撮る**: スタンドに置いて 30〜45° の斜めから、手牌 13〜14 枚を写した動画（mp4 / mov）。牌 3 種・卓 5 種・照明を変える。
   スタンドか手牌を少し動かしながら 10〜20 秒（静止したままだと重複として捨てられる）。1 本 = 1 グループとして分割される。
   動画のファイル名は英数字で区別できるものに（`IMG_0123.MOV` など。記号を除いた名前が同じになる 2 本はエラーにする）。
2. **フレーム抽出 + 下書きラベル**（`extract_frames.py`）:
   ```bash
   $PY -I -B $ML/extract_frames.py ~/clips --out $W/ds_oblique --fps 3 --max-per-clip 60 \
       --prelabel $ML/weights/live_s/best.pt          # 下書きは s の検出（確度 0.30 以上）
   ```
   `ds_oblique/train/images/vid<動画名>_f<番号>.jpg` と、`.../labels/*.txt`（YOLO 形式の下書き）ができる。
   既定で正立フレームの**中央の正方形**に切り出す（アプリのライブの推論範囲と同じ。`--crop none` で全体）。ぼやけたフレームと
   直前とほぼ同じフレームは捨てる。`frames.csv` に動画・秒・ぼやけ度・下書きの検出数が残る。
   動画が横向きのまま出てくるときは `--rotate 90` など。2,000 枚なら 40〜50 本 × 40〜50 枚が目安。
3. **ラベルを直す**: Roboflow / CVAT / LabelImg などで `ds_oblique/train/{images,labels}` を開き、枠とクラスを直す
   （クラスの順は `data.yaml` の names = `0b,0m,0p,0s,1m,…,9s`）。**直していないフレームは学習に使わない**。
   Roboflow で書き出し直すとファイル名に `_jpg.rf.<ハッシュ>` が付くが、`make_clean_split.py` は `vid…_f…` で動画単位にまとめる。
4. **分割**（既存データの分割は変わらない。斜めは別に train/valid/test に分ける）:
   ```bash
   $PY -I -B $ML/make_clean_split.py /home/nomuyu/workspace/iOS/master.v7i.yolov11,$W/ds_oblique $W/ds_clean2
   ```
   ラベルのないフレームは読み飛ばし（件数を表示）、動画 1 本のフレームは同じ split にまとまる。
5. **学習し直す**:
   ```bash
   DATA=$W/ds_clean2/data_baseline.yaml TAG=obl bash $ML/train_live.sh n 100       # runs/live_n_obl
   DATA=$W/ds_clean2/data_baseline.yaml TAG=obl bash $ML/train_live.sh s 100
   ```
   （前の best.pt から追い学習するなら `INIT=…/best.pt` と少ないエポック。まず初期重みからのやり直しを推奨。）
6. **評価**: `eval_models.py $W/ds_clean2 …`（`app_like_test` を作り直すため、前の `reports/ds_hard` を消す）。
   斜めの test フレーム（`vid*`）は `oblique_hand_exact_strict_c25` として別に出る。`eval_tflite.py` も同じ。
   従来の test（真上・正面）が落ちていないことも同じ表で見る。
7. **書き出し → アセット差し替え → アプリのテスト**: 上の手順 4・5。ファイル名はそのまま上書き。
   `cd app && flutter analyze && flutter test`（アセットの存在確認を含む）。

設計書の「ライブは 1 秒の多数決後に 14 枚完全一致で測る」評価は、連続フレームの動画が集まってから
`eval_tflite.py` に足す（今は単フレームの完全一致まで）。

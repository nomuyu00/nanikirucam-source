# 第三者のコード・学習データ

なにきるカムのアプリとエンジンは、ユーザーが承認した方針によりAGPL-3.0で公開する。全文は`LICENSE`。対応ソースは https://github.com/nomuyu00/nanikirucam-source 。この文書は個別の第三者の著作権表示・条件を保持し、第三者の画像やSDKを一括して再許諾するものではない。モデルの生成元とデータの出典はREADMEを参照。

## あがりかむの流用コード

取得元: AgariCam application code。流用元のLICENSEを保持する。配布アプリでも設定 > ライセンス・出典から参照可能。

```text
MIT License

Copyright (c) 2025 AgariCam Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 学習データ

- **master v7 (2023-09-20 9:29pm)**、提供者 **majmaster**。
- 配布元: https://universe.roboflow.com/majmaster/master-oez61/dataset/7
- ライセンス: **CC BY 4.0**、https://creativecommons.org/licenses/by/4.0/
- リサイズ・拡張・独自の学習／評価分割を行い、牌認識モデルの学習に使用。元のデータセット画像はアプリに同梱しない。提供者による本アプリの推奨を意味しない。

## Flutter・プラグイン

ビルドが生成する各パッケージのライセンスは、配布アプリの設定 > ライセンス・出典から表示する。

## Ultralytics YOLO11認識モデル

- 学習・書き出しに使用したUltralyticsの配布条件: **GNU Affero General Public License v3.0 (AGPL-3.0)**。モデルの条件をMITへ置き換えない。
- 原文を`app/assets/licenses/ultralytics-AGPL-3.0.txt`に保持し、アプリの設定 > ライセンス・出典から表示する。アプリ・モデルの対応ソースも上記の公開用リポジトリで提供する。元の非公開リポジトリの履歴や運用情報は公開しない。
- プロジェクトと公開条件: https://github.com/ultralytics/ultralytics 、https://www.ultralytics.com/license 。対応ソースはこのリポジトリで提供する。

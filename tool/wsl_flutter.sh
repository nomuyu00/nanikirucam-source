#!/usr/bin/env bash
# D: の作業ツリーを WSL（Ubuntu ディストロ）のホームにミラーして Flutter/Dart を実行する。
# /mnt/d 越しの analyze やビルドは遅いため。**編集は必ず D: 側で行い、ミラーは使い捨て**。
#
# 使い方（Windows の Git Bash から）:
#   wsl.exe -d Ubuntu -e bash /mnt/d/ProgramFiles/IdeaProjects/nanikirucam/tool/wsl_flutter.sh <ミラー名> <app|core> '<コマンド>'
# 例:
#   ... wsl_flutter.sh quiz app 'flutter analyze && flutter test test/quiz'
#   ... wsl_flutter.sh engine core 'dart test test/engine'
# ミラー名は作業者ごとに変える（同じミラーを同時に使うと壊れる）。ミラーは ~/work/<ミラー名>/ に置かれる。
set -euo pipefail

name="${1:?ミラー名}"
target="${2:?app か core}"
cmd="${3:?コマンド}"

src=/mnt/d/ProgramFiles/IdeaProjects/nanikirucam
dst="$HOME/work/$name"
export PATH="$HOME/flutter-sdk/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/android-sdk"
export JAVA_HOME="$HOME/jdk17"
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"

mkdir -p "$dst/app" "$dst/packages/mahjong_core"
common=(--exclude build/ --exclude .dart_tool/ --exclude .gradle/ --exclude node_modules/ --exclude 'ios/Pods/' --exclude '*.iml')
rsync -a --delete "${common[@]}" "$src/packages/mahjong_core/" "$dst/packages/mahjong_core/"
rsync -a --delete "${common[@]}" --exclude functions/ --exclude hosting/ "$src/app/" "$dst/app/"

case "$target" in
  app) cd "$dst/app" ;;
  core) cd "$dst/packages/mahjong_core" ;;
  *) echo "target は app か core" >&2; exit 2 ;;
esac

if [ ! -f .dart_tool/package_config.json ] || [ pubspec.yaml -nt .dart_tool/package_config.json ]; then
  if [ "$target" = app ]; then flutter pub get >/dev/null; else dart pub get >/dev/null; fi
fi
bash -c "$cmd"

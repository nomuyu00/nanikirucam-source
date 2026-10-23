/// 上がりやすさ（設計書 4.6.3）。
///
/// 事前に作った表（`win_ease_table.g.dart`、`tool/sim_win_ease.dart` が生成）を引く。
/// 表は 1 人打ち（他家なし）で「シャンテン最小 → 受け入れ最大」の単純戦略を
/// シミュレーションした和了率で、他家の動きは含まない（仕様 7.5）。
/// 手の形（一般形・七対子・国士）ごとに別の表を持つ。七対子型は受け入れが少なく
/// 待ちが狭いので、同じシャンテン・受け入れでも一般形より和了率がかなり低い。
library;

import 'package:mahjong_core/src/engine/shanten.dart' show ShantenType;
import 'package:mahjong_core/src/engine/win_ease_table.g.dart';

/// 無料版で出す 3 段階（高: 0.5 以上、低: 0.2 未満）。
enum WinEaseLevel { high, medium, low }

/// 巡目を渡されなかったときに使う巡目。
const int _defaultTurn = 6;

/// 流局までのツモ回数（18 巡目まで）。打牌後の巡目がこれ以上なら残りツモは無い。
const int _lastDrawTurn = 18;

/// 表のシャンテン区分の最大（3 以上は同じ区分）。
const int _maxShantenBin = 3;

/// 13 枚（打牌後）の手が、この巡目から流局までにツモ和了できる割合 0..1。
///
/// [shanten] は打牌後のシャンテン数（-1 は和了済みとして 1.0）、[ukeireTotal] は
/// 受け入れの合計枚数、[turn] は打牌した巡目（1〜17 が表の範囲。null は 6 巡目、
/// 0 以下は 1 巡目、18 以上は残りツモが無いので 0.0）。
/// [type] は打牌後の手が最小のシャンテン数を出した形（`shanten(...)` が返す
/// [ShantenResult.type]。同値なら一般形が優先される）。既定は一般形。
/// シャンテン 3 以上は 3 の行、受け入れが表の外ならいちばん近い端の区分を使う。
/// 他家は考慮しない（仕様 7.5）。
double winEase({
  required int shanten,
  required int ukeireTotal,
  int? turn,
  ShantenType type = ShantenType.standard,
}) {
  if (shanten < 0) return 1.0;
  final t = turn ?? _defaultTurn;
  if (t >= _lastDrawTurn) return 0.0;
  final column = (t < 1 ? 1 : t) - 1;
  final row = shanten > _maxShantenBin ? _maxShantenBin : shanten;
  final table = switch (type) {
    ShantenType.standard => kWinEaseTableStandard,
    ShantenType.sevenPairs => kWinEaseTableSevenPairs,
    ShantenType.kokushi => kWinEaseTableKokushi,
  };
  return table[row][_ukeireBin(ukeireTotal)][column];
}

WinEaseLevel winEaseLevel(double value) {
  if (value >= 0.5) return WinEaseLevel.high;
  if (value < 0.2) return WinEaseLevel.low;
  return WinEaseLevel.medium;
}

/// [ukeireTotal] が入る区分の添字（下限が [ukeireTotal] 以下で最大のもの。負は 0）。
int _ukeireBin(int ukeireTotal) {
  var low = 0;
  var high = kWinEaseUkeireLowerBounds.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (kWinEaseUkeireLowerBounds[mid] <= ukeireTotal) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

import 'package:equatable/equatable.dart';

/// 想定打点のレンジ（設計書 4.2、仕様 4.4）。
///
/// 前提: 現在の親子、本場・供託なし、裏ドラ・一発なし。
/// - テンパイ・一向聴（[isEstimate] = false）: 経路（和了形）ごとにロンとツモ（ツモは
///   3 人から受け取る合計）を 1 回ずつ数え、経路の重みの半分ずつで集計する。役が無くて
///   和了できない結果は 0 点として含める（門前のダマのロン、副露の役なし）。
///   [min] は最小、[median] は重み付き中央値（累積が半分に達する最小の値）、[max] は最大。
/// - 二向聴以上（[isEstimate] = true）: 規則で見つけた役の翻数とドラ枚数から 30 符の
///   ロンで出した目安。
class PointRange extends Equatable {
  final int min;
  final int median;
  final int max;
  final bool isEstimate;

  const PointRange({
    required this.min,
    required this.median,
    required this.max,
    this.isEstimate = false,
  });

  /// 経路が無い（待ちが全部見えている等）か、まだ計算していない。
  static const PointRange zero = PointRange(min: 0, median: 0, max: 0);

  /// (点数, 重み) の組から作る。重み 0 の組は無視する。組が無ければ [zero]。
  factory PointRange.fromWeighted(List<(int, int)> outcomes) {
    final list = [
      for (final o in outcomes)
        if (o.$2 > 0) o,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (list.isEmpty) return zero;
    var total = 0;
    for (final o in list) {
      total += o.$2;
    }
    var acc = 0;
    var median = list.last.$1;
    for (final o in list) {
      acc += o.$2;
      if (2 * acc >= total) {
        median = o.$1;
        break;
      }
    }
    return PointRange(min: list.first.$1, median: median, max: list.last.$1);
  }

  @override
  List<Object?> get props => [min, median, max, isEstimate];

  @override
  String toString() =>
      'PointRange($min〜$max, 中央$median${isEstimate ? ', 目安' : ''})';
}

/// 基本点から、ロンで受け取る点数（4 人打ち、本場なし）。
int ronPayment(int basePoints, {required bool dealer}) =>
    _ceil100(basePoints * (dealer ? 6 : 4));

/// 基本点から、ツモで受け取る合計点数（4 人打ち、本場なし）。
/// 親は子 3 人から 2 倍ずつ、子は子 2 人から 1 倍・親から 2 倍。
int tsumoPayment(int basePoints, {required bool dealer}) => dealer
    ? 3 * _ceil100(basePoints * 2)
    : 2 * _ceil100(basePoints) + _ceil100(basePoints * 2);

int _ceil100(int value) => (value + 99) ~/ 100 * 100;

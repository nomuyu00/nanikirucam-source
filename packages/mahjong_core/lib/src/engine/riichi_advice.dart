import 'package:equatable/equatable.dart';

/// [RiichiAdvice] の根拠（仕様 4.5 の場合分け）。
enum RiichiReason {
  /// 門前の役なしテンパイ。ロンで和了するにはリーチが要る（リーチ一択）。
  noYaku,

  /// 役あり。「リーチ込み × 上がりやすさ」が「ダマ × 上がりやすさ × 1.1」以上。
  riichiValue,

  /// 役あり。ダマの方が上（様子見）。リーチで打点がほとんど上がらない手
  /// （倍満のダマ、数え役満・役満など）。
  damaValue,

  /// 待ちが残っていない（空テン）。リーチしても和了できない。
  noWaitsLeft,
}

/// Pro のリーチ判断（設計書 4.6.5、仕様 4.5）。
///
/// 「リーチ込みの想定打点 × 上がりやすさ」と「ダマの想定打点 × 上がりやすさ × 1.1
/// （出和了りしやすさの補正）」を比べる簡易版。
///
/// 想定打点は待ちごとのロンとツモ（ツモは 3 人から受け取る合計）を、待ちの残り枚数を
/// 重みにして平均したもの（[PointRange] の中央値ではなく平均。役のない待ちのダマの
/// ロンは 0 点として入るので、中央値だと待ちの一部が役なしのとき値が飛ぶため）。
/// 現在の親子、本場・供託なし、裏ドラ・一発なし、リーチ棒の 1,000 点は数えない。
/// 上がりやすさはリーチとダマで同じ値（他家は考えない、仕様 7.5）。
class RiichiAdvice extends Equatable {
  /// リーチを推奨するか（false は様子見＝ダマ）。
  final bool recommendRiichi;

  /// 推奨の根拠。
  final RiichiReason reason;

  /// リーチ込みの想定打点 × 上がりやすさ。
  final double riichiValue;

  /// ダマの想定打点 × 上がりやすさ × 1.1。
  final double damaValue;

  /// リーチ込みの想定打点（待ちの残り枚数で重み付けしたロン・ツモの平均）。
  final double riichiPoints;

  /// ダマの想定打点（同上。役が無くて和了できない結果は 0 点）。
  final double damaPoints;

  /// 上がりやすさ 0..1（`winEase` の表）。
  final double winEase;

  const RiichiAdvice({
    required this.recommendRiichi,
    required this.reason,
    required this.riichiValue,
    required this.damaValue,
    required this.riichiPoints,
    required this.damaPoints,
    required this.winEase,
  });

  @override
  List<Object?> get props => [
    recommendRiichi,
    reason,
    riichiValue,
    damaValue,
    riichiPoints,
    damaPoints,
    winEase,
  ];

  @override
  String toString() =>
      'RiichiAdvice(${recommendRiichi ? 'リーチ' : 'ダマ'} ${reason.name} '
      'リーチ${riichiPoints.toStringAsFixed(0)} ダマ${damaPoints.toStringAsFixed(0)} '
      '上がりやすさ${winEase.toStringAsFixed(3)})';
}

/// ダマのロンに 1.1 を掛ける補正（設計書 4.6.5）。
const double kDamaBonus = 1.1;

/// テンパイの待ち 1 つ分（[adviseRiichi] の入力）。点数は現在の親子で受け取る点数、
/// ダマで役が無ければ 0。
typedef RiichiWait = ({
  int remaining,
  int ronPoints,
  int tsumoPoints,
  int ronRiichiPoints,
  int tsumoRiichiPoints,
  bool ronHasYaku,
});

/// 門前テンパイの待ちからリーチ判断を作る。[winEase] は 13 枚の上がりやすさ。
RiichiAdvice adviseRiichi(List<RiichiWait> waits, {required double winEase}) {
  var weight = 0;
  var riichiSum = 0;
  var damaSum = 0;
  var hasYaku = false;
  for (final w in waits) {
    if (w.remaining <= 0) continue;
    weight += 2 * w.remaining;
    riichiSum += w.remaining * (w.ronRiichiPoints + w.tsumoRiichiPoints);
    damaSum += w.remaining * (w.ronPoints + w.tsumoPoints);
    if (w.ronHasYaku) hasYaku = true;
  }
  if (weight == 0) {
    return RiichiAdvice(
      recommendRiichi: false,
      reason: RiichiReason.noWaitsLeft,
      riichiValue: 0,
      damaValue: 0,
      riichiPoints: 0,
      damaPoints: 0,
      winEase: winEase,
    );
  }
  final riichiPoints = riichiSum / weight;
  final damaPoints = damaSum / weight;
  final riichiValue = riichiPoints * winEase;
  final damaValue = damaPoints * winEase * kDamaBonus;
  final RiichiReason reason;
  if (!hasYaku) {
    reason = RiichiReason.noYaku;
  } else if (riichiPoints >= damaPoints * kDamaBonus) {
    // winEase を掛ける前の値で比べる（winEase が 0 でも打点の比較は残す）。
    reason = RiichiReason.riichiValue;
  } else {
    reason = RiichiReason.damaValue;
  }
  return RiichiAdvice(
    recommendRiichi: reason != RiichiReason.damaValue,
    reason: reason,
    riichiValue: riichiValue,
    damaValue: damaValue,
    riichiPoints: riichiPoints,
    damaPoints: damaPoints,
    winEase: winEase,
  );
}

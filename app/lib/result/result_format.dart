import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/result_logic.dart';

/// 点数を 3 桁区切りにする（2000 → 2,000）。
String formatPoints(num value) {
  final n = value.round();
  final digits = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

/// 0..1 を百分率にする（0.623 → 62%）。
String formatPercent(double value) => '${(value * 100).round()}%';

/// 想定打点の表示（Pro: 「2,000〜7,700（中央 3,900）」、目安なら先頭に「目安」）。
/// 経路が無い（0 点しかない）ときは「—」。
String formatRange(PointRange range, ResultStrings s) {
  if (range.max <= 0) return s.noPoints;
  final body = range.min == range.max
      ? formatPoints(range.max)
      : '${formatPoints(range.min)}〜${formatPoints(range.max)}'
            '（${s.rangeMedian(formatPoints(range.median))}）';
  return range.isEstimate ? '${s.estimate} $body' : body;
}

/// 無料の想定打点の目安（「普通（約 3,900）」）。門前ならリーチ込みの中央値を代表値に
/// する（ダマでは役が無く 0 点になる手でも目安が出るように）。
String formatPointsLevel(
  DiscardCandidate c,
  ResultStrings s, {
  required bool dealer,
}) {
  final value = c.rankingMedian;
  if (value <= 0) return s.noPoints;
  final level = pointsLevelOf(value, dealer: dealer);
  final suffix = c.riichiPoints != null ? '・${s.riichiIncluded}' : '';
  return '${s.pointsLevel(level)}（${s.about(formatPoints(value))}$suffix）';
}

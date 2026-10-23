import 'package:mahjong_core/mahjong_core.dart';

import 'engine_test_utils.dart';

/// テスト用の [HandState]。[hand] の '0' は赤5（[HandState.redIds] に入る）。
/// [dora] はドラそのもの（表示牌ではない）、[dealer] なら東家。
HandState stateOf(
  String hand, {
  String melds = '',
  String dora = '',
  String visible = '',
  bool dealer = false,
  Wind? seat,
  Wind round = Wind.east,
  int? turn,
}) {
  final reds = <int>{};
  final digits = <String>[];
  for (final ch in hand.split('')) {
    if ('mpsz'.contains(ch)) {
      for (final d in digits) {
        if (d == '0') reds.add(tileIdFromLabel('0$ch'));
      }
      digits.clear();
    } else if (ch != ' ') {
      digits.add(ch);
    }
  }
  return HandState(
    counts: countsFromNotation(hand),
    openMelds: meldsFromSpec(melds),
    visible: countsFromNotation(visible),
    doraIds: dora.isEmpty ? const [] : idsFromNotation(dora),
    redIds: reds,
    seatWind: seat ?? (dealer ? Wind.east : Wind.south),
    roundWind: round,
    dealer: dealer,
    turn: turn,
  );
}

/// 'pinfu:certain sanshoku:possible[4m] dora:certain x2' の形。
String yakuString(List<YakuProspect> yaku) => yaku
    .map((p) {
      final tiles = p.enablingTiles.isEmpty
          ? ''
          : '[${p.enablingTiles.map(labelOfId).join(',')}]';
      final count = p.count == null ? '' : ' x${p.count}';
      return '${p.yaku.name}:${p.confidence.name}$tiles$count';
    })
    .join(' ');

/// '最小/中央/最大'。null は '-'。
String rangeString(PointRange? r) =>
    r == null ? '-' : '${r.min}/${r.median}/${r.max}';

import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/tile_utils.dart';

/// '123m456p789s11z' 形式（'0' は赤5）を牌 id の列にする。
List<int> idsFromNotation(String notation) {
  final ids = <int>[];
  final digits = <String>[];
  for (final ch in notation.split('')) {
    if (ch == ' ') continue;
    if ('mpsz'.contains(ch)) {
      for (final d in digits) {
        final id = tileIdFromLabel('$d$ch');
        if (id < 0) throw ArgumentError('不正な牌: $d$ch');
        ids.add(id);
      }
      digits.clear();
    } else {
      digits.add(ch);
    }
  }
  if (digits.isNotEmpty) throw ArgumentError('色の無い数字: $notation');
  return ids;
}

List<int> countsFromNotation(String notation) {
  final counts = List<int>.filled(kTileKinds, 0);
  for (final id in idsFromNotation(notation)) {
    counts[id]++;
  }
  return counts;
}

/// 'chi:1m'（1m から始まる順子）/ 'pon:5z' / 'kan:1p'（明槓）/ 'ankan:9s'。
Meld meldFromSpec(String spec) {
  final parts = spec.split(':');
  final id = tileIdFromLabel(parts[1]);
  if (parts.length != 2 || id < 0) throw ArgumentError('不正な副露: $spec');
  switch (parts[0]) {
    case 'chi':
      return Meld(
        type: MeldType.shuntsu,
        tiles: [tileFromId(id), tileFromId(id + 1), tileFromId(id + 2)],
        open: true,
      );
    case 'pon':
      return Meld(
        type: MeldType.koutsu,
        tiles: List.filled(3, tileFromId(id)),
        open: true,
      );
    case 'kan':
      return Meld(
        type: MeldType.kantsu,
        tiles: List.filled(4, tileFromId(id)),
        open: true,
      );
    case 'ankan':
      return Meld(
        type: MeldType.kantsu,
        tiles: List.filled(4, tileFromId(id)),
        open: false,
      );
  }
  throw ArgumentError('不正な副露: $spec');
}

List<Meld> meldsFromSpec(String specs) => specs.isEmpty || specs == '-'
    ? const []
    : specs.split(',').map(meldFromSpec).toList();

HandState handFromNotation(
  String notation, {
  String melds = '',
  String visible = '',
}) {
  return HandState(
    counts: countsFromNotation(notation),
    openMelds: meldsFromSpec(melds),
    visible: countsFromNotation(visible),
  );
}

/// counts を '123m456p789s11z' 形式にする（表示用）。
String notationOfCounts(List<int> counts) {
  final buffer = StringBuffer();
  const suits = 'mpsz';
  for (var s = 0; s < 4; s++) {
    final len = s == 3 ? 7 : 9;
    final part = StringBuffer();
    for (var i = 0; i < len; i++) {
      part.write('${i + 1}' * counts[s * 9 + i]);
    }
    if (part.isNotEmpty) buffer.write('$part${suits[s]}');
  }
  return buffer.toString();
}

String labelOfId(int id) => '${id % 9 + 1}${'mpsz'[id ~/ 9]}';

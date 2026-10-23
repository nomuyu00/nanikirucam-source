import 'package:mahjong_core/src/models.dart';

int tileIdFromLabel(String label) {
  if (label.length < 2) return -1;
  final numChar = label[0];
  final suitChar = label[1];
  if (suitChar == 'z') {
    final value = int.tryParse(numChar);
    if (value == null || value < 1 || value > 7) return -1;
    return 27 + (value - 1);
  }
  final isRed = numChar == '0';
  final value = isRed ? 5 : int.tryParse(numChar);
  if (value == null || value < 1 || value > 9) return -1;
  int offset;
  switch (suitChar) {
    case 'm':
      offset = 0;
      break;
    case 'p':
      offset = 9;
      break;
    case 's':
      offset = 18;
      break;
    default:
      return -1;
  }
  return offset + (value - 1);
}

Tile tileFromLabel(String label) {
  if (label.length < 2) {
    return const Tile(Suit.m, 1);
  }
  final numChar = label[0];
  final suitChar = label[1];
  final isRed = numChar == '0';
  final value = isRed ? 5 : int.tryParse(numChar) ?? 1;
  switch (suitChar) {
    case 'm':
      return Tile(Suit.m, value, red: isRed);
    case 'p':
      return Tile(Suit.p, value, red: isRed);
    case 's':
      return Tile(Suit.s, value, red: isRed);
    case 'z':
      final honorValue = int.tryParse(numChar) ?? 1;
      return Tile(Suit.z, honorValue);
    default:
      return Tile(Suit.m, value, red: isRed);
  }
}

Tile tileFromId(int id) {
  if (id < 0 || id >= 34) {
    return const Tile(Suit.m, 1);
  }
  if (id < 9) {
    return Tile(Suit.m, (id % 9) + 1);
  }
  if (id < 18) {
    return Tile(Suit.p, (id % 9) + 1);
  }
  if (id < 27) {
    return Tile(Suit.s, (id % 9) + 1);
  }
  return Tile(Suit.z, (id - 27) + 1);
}

bool isTerminalOrHonorTileId(int id) {
  if (id < 0 || id >= 34) return false;
  if (id >= 27) return true;
  final num = (id % 9) + 1;
  return num == 1 || num == 9;
}

bool isHonorTileId(int id) => id >= 27 && id < 34;

/// 赤5を通常の5として扱ったラベル（'0p' → '5p'）。
String normalizeTileLabel(String label) =>
    label.startsWith('0') && label.length >= 2 ? '5${label[1]}' : label;

/// ドラ表示牌からドラを求める（9→1、北→東、中→白）。
/// 三麻では萬子が1と9だけなので 1m→9m、9m→1m。
String doraFromIndicator(String indicator, {bool threePlayer = false}) {
  final label = normalizeTileLabel(indicator);
  if (label.length < 2) return label;
  final value = int.tryParse(label[0]) ?? 0;
  final suit = label[1];
  if (suit == 'z') {
    if (value >= 1 && value <= 4) return '${value % 4 + 1}z';
    if (value >= 5 && value <= 7) return '${(value - 5 + 1) % 3 + 5}z';
    return label;
  }
  if (threePlayer && suit == 'm') {
    return value == 9 ? '1m' : '9m';
  }
  return '${value % 9 + 1}$suit';
}

/// 表示牌の並びから、手牌に含まれるドラの枚数を数える。
int countDora(
  Iterable<String> handTiles,
  Iterable<String> indicators, {
  bool threePlayer = false,
}) {
  final hand = handTiles.map(normalizeTileLabel).toList(growable: false);
  var count = 0;
  for (final indicator in indicators) {
    final dora = doraFromIndicator(indicator, threePlayer: threePlayer);
    count += hand.where((tile) => tile == dora).length;
  }
  return count;
}

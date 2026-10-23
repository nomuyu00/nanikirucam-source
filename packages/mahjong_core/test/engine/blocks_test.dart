// ブロック分解（設計書 4.7）。'役割:牌' の並び（先頭の牌 id 順、副露・暗槓は最後に * 付き）。
import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

String blockString(Block b) {
  final counts = List<int>.filled(kTileKinds, 0);
  for (final id in b.tileIds) {
    counts[id]++;
  }
  return '${b.role.name}:${notationOfCounts(counts)}${b.declared ? '*' : ''}';
}

List<String> blocksOf(String hand, {String melds = ''}) =>
    decomposeBlocks(stateOf(hand, melds: melds)).map(blockString).toList();

/// 分解から「8 − 2m − t − h（m + t ≤ 4）」を出す（一般形のときの確認用）。
int formulaShanten(List<Block> blocks) {
  var m = 0;
  var t = 0;
  var h = 0;
  for (final b in blocks) {
    switch (b.role) {
      case BlockRole.meld:
        m++;
      case BlockRole.head:
        h++;
      case BlockRole.ryanmen:
      case BlockRole.kanchan:
      case BlockRole.penchan:
      case BlockRole.pair:
        t++;
      case BlockRole.isolated:
        break;
    }
  }
  final room = 4 - m < 0 ? 0 : 4 - m;
  return 8 - 2 * m - (t < room ? t : room) - h;
}

void main() {
  group('代表形', () {
    final cases =
        <({String hand, String melds, List<String> blocks, String why})>[
          (
            hand: '467m 123p 789s 99s 34p 1z',
            melds: '',
            blocks: [
              'isolated:4m',
              'ryanmen:67m',
              'meld:123p',
              'ryanmen:34p',
              'meld:789s',
              'head:99s',
              'isolated:1z',
            ],
            why: '467m は 46 嵌張より 67 両面を優先し、4m が孤立',
          ),
          (
            hand: '2345m 678p 345s 99p 1z',
            melds: '',
            blocks: [
              'isolated:2m',
              'meld:345m',
              'meld:678p',
              'head:99p',
              'meld:345s',
              'isolated:1z',
            ],
            why: '2345m は面子を優先（23+45 の両面 2 つより 345+2）。孤立は端寄りの 2m',
          ),
          (
            hand: '3456m 678p 345s 99p 1z',
            melds: '',
            blocks: [
              'meld:345m',
              'isolated:6m',
              'meld:678p',
              'head:99p',
              'meld:345s',
              'isolated:1z',
            ],
            why: '3456m は 345+6 と 456+3 が同点。先に見つかる 345+6',
          ),
          (
            hand: '1123m 456p 789s 34s 5z',
            melds: '',
            blocks: [
              'meld:123m',
              'isolated:1m',
              'meld:456p',
              'ryanmen:34s',
              'meld:789s',
              'isolated:5z',
            ],
            why: '1123m は面子を優先（11 雀頭 + 23 両面より 123 + 1）',
          ),
          (
            hand: '5556m 456p 789s 34s 2z',
            melds: '',
            blocks: [
              'meld:555m',
              'isolated:6m',
              'meld:456p',
              'ryanmen:34s',
              'meld:789s',
              'isolated:2z',
            ],
            why: '5556m は刻子 + 孤立（面子を優先）',
          ),
          (
            hand: '23456m 99m 46p 13s 777z',
            melds: '',
            blocks: [
              'meld:234m',
              'ryanmen:56m',
              'head:99m',
              'kanchan:46p',
              'kanchan:13s',
              'meld:777z',
            ],
            why: '23456m は 234 + 56（両面）。字牌の刻子も面子',
          ),
          (
            hand: '12m 456m 678p 23s 67s 99m',
            melds: '',
            blocks: [
              'penchan:12m',
              'meld:456m',
              'head:99m',
              'meld:678p',
              'ryanmen:23s',
              'ryanmen:67s',
            ],
            why: '12m は辺張',
          ),
          (
            hand: '234m 67m 23p 89p 567s 55s',
            melds: '',
            blocks: [
              'meld:234m',
              'ryanmen:67m',
              'ryanmen:23p',
              'penchan:89p',
              'meld:567s',
              'head:55s',
            ],
            why: '89p は辺張、555s とせず 567s + 55s',
          ),
          (
            hand: '2357p 22m 456m 34s 678s',
            melds: '',
            blocks: [
              'head:22m',
              'meld:456m',
              'ryanmen:23p',
              'kanchan:57p',
              'ryanmen:34s',
              'meld:678s',
            ],
            why: '2357p は 23 両面 + 57 嵌張（35 嵌張 + 2・7 孤立より両面）',
          ),
          (
            hand: '24m 46m 99s 345p 678p 1z',
            melds: '',
            blocks: [
              'kanchan:24m',
              'kanchan:46m',
              'meld:345p',
              'meld:678p',
              'head:99s',
              'isolated:1z',
            ],
            why: '2446m は嵌張 2 つ（44 対子 + 孤立 2 つより嵌張を優先）',
          ),
          (
            hand: '22m 55z 345p 678p 11s 9s 4z',
            melds: '',
            blocks: [
              'pair:22m',
              'meld:345p',
              'meld:678p',
              'pair:11s',
              'isolated:9s',
              'isolated:4z',
              'head:55z',
            ],
            why: '対子が 3 つなら雀頭は字牌の 55z（字牌 → 1・9 → 2・8 の順）',
          ),
          (
            hand: '1111m 234p 567s 99s 1z 2z',
            melds: '',
            blocks: [
              'meld:111m',
              'isolated:1m',
              'meld:234p',
              'meld:567s',
              'head:99s',
              'isolated:1z',
              'isolated:2z',
            ],
            why: '同じ牌 4 枚は刻子 + 孤立（対子 2 つにはしない）',
          ),
          (
            hand: '123m 789p 123s 33z 6m 4p 9s',
            melds: '',
            blocks: [
              'meld:123m',
              'isolated:6m',
              'isolated:4p',
              'meld:789p',
              'meld:123s',
              'isolated:9s',
              'head:33z',
            ],
            why: 'くっつきの形: 3 面子 + 雀頭 + 浮き牌 3 つ',
          ),
          (
            hand: '123m 456p 789s 234s 55z',
            melds: '',
            blocks: [
              'meld:123m',
              'meld:456p',
              'meld:234s',
              'meld:789s',
              'head:55z',
            ],
            why: '和了形の 14 枚は 4 面子 + 雀頭',
          ),
          (
            hand: '1112345678999m 5m',
            melds: '',
            blocks: [
              'meld:111m',
              'meld:234m',
              'head:55m',
              'meld:678m',
              'meld:999m',
            ],
            why: '九蓮宝燈形の和了も 1 通りに分ける',
          ),
          (
            hand: '11m 44p 77s 99s 33z 2m 6p 8s 5z',
            melds: '',
            blocks: [
              'pair:11m',
              'isolated:2m',
              'pair:44p',
              'isolated:6p',
              'pair:77s',
              'isolated:8s',
              'pair:99s',
              'pair:33z',
              'isolated:5z',
            ],
            why: '七対子が最小（一向聴）なら対子と孤立。雀頭は無い',
          ),
          (
            hand: '19m 19p 19s 1234567z 1m',
            melds: '',
            blocks: [
              'head:11m',
              'isolated:9m',
              'isolated:1p',
              'isolated:9p',
              'isolated:1s',
              'isolated:9s',
              'isolated:1z',
              'isolated:2z',
              'isolated:3z',
              'isolated:4z',
              'isolated:5z',
              'isolated:6z',
              'isolated:7z',
            ],
            why: '国士が最小なら么九牌の対子 1 つが雀頭、残りは孤立',
          ),
          (
            hand: '1m 4m 7m 2p 5p 8p 3s 6s 9s 1z 2z 3z 4z 5z',
            melds: '',
            blocks: [
              'isolated:1m',
              'isolated:4m',
              'isolated:7m',
              'isolated:2p',
              'isolated:5p',
              'isolated:8p',
              'isolated:3s',
              'isolated:6s',
              'isolated:9s',
              'isolated:1z',
              'isolated:2z',
              'isolated:3z',
              'isolated:4z',
              'isolated:5z',
            ],
            why: '搭子も対子も無い手は全部孤立（七対子と国士が同値で七対子）',
          ),
          (
            hand: '23m 45p 78p 57s 99s 4z',
            melds: 'pon:7z',
            blocks: [
              'ryanmen:23m',
              'ryanmen:45p',
              'ryanmen:78p',
              'kanchan:57s',
              'head:99s',
              'isolated:4z',
              'meld:777z*',
            ],
            why: 'ポンは最後に宣言済みの面子として並べる',
          ),
          (
            hand: '34m 67s 99p 13p',
            melds: 'chi:2s,ankan:1z',
            blocks: [
              'ryanmen:34m',
              'kanchan:13p',
              'head:99p',
              'ryanmen:67s',
              'meld:234s*',
              'meld:1111z*',
            ],
            why: 'チーと暗槓は副露の順に最後。暗槓は 4 枚',
          ),
        ];
    for (final c in cases) {
      test('${c.hand}${c.melds.isEmpty ? '' : ' [${c.melds}]'}: ${c.why}', () {
        expect(blocksOf(c.hand, melds: c.melds), c.blocks);
      });
    }
  });

  test('13 枚の手も分解する', () {
    expect(blocksOf('2345m 678p 345s 99p 1z'), hasLength(6));
    expect(blocksOf('24m 456p 789p 234s 99s'), [
      'kanchan:24m',
      'meld:456p',
      'meld:789p',
      'meld:234s',
      'head:99s',
    ]);
  });

  test('13・14 枚でない手は ArgumentError', () {
    expect(
      () => decomposeBlocks(stateOf('123m 456p 789s 11z')),
      throwsArgumentError,
    );
  });

  test('性質: 牌は過不足なく入り、一般形は分解の式がシャンテン数と一致する', () {
    final random = Random(7);
    var checked = 0;
    for (var n = 0; n < 3000; n++) {
      final size = n.isEven ? 14 : 13;
      final counts = List<int>.filled(kTileKinds, 0);
      // 半分は 1 色寄り（分け方が多い）
      final suitOnly = n % 4 < 2;
      var left = size;
      while (left > 0) {
        final t = suitOnly
            ? random.nextInt(9) + 9 * random.nextInt(2)
            : random.nextInt(kTileKinds);
        if (counts[t] == 4) continue;
        counts[t]++;
        left--;
      }
      final hand = HandState(counts: counts);
      final blocks = decomposeBlocks(hand);
      final back = List<int>.filled(kTileKinds, 0);
      for (final b in blocks) {
        for (final id in b.tileIds) {
          back[id]++;
        }
      }
      expect(back, counts, reason: notationOfCounts(counts));
      expect(
        blocks.where((b) => b.role == BlockRole.head).length,
        lessThanOrEqualTo(1),
      );
      final sh = shanten(hand);
      // 同じ牌 4 枚の手は「5 枚目が要る形」をテンパイと数えないので式と違うことがある
      if (sh.type == ShantenType.standard && !counts.contains(4)) {
        expect(
          formulaShanten(blocks),
          standardShanten(counts, 0),
          reason: notationOfCounts(counts),
        );
        checked++;
      }
    }
    expect(checked, greaterThan(1500));
  });
}

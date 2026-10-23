import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

HandInput hand14({
  int? tsumoIndex,
  List<String> doraIndicators = const [],
  Wind seatWind = Wind.south,
  Wind roundWind = Wind.east,
  bool? dealer,
  int? turn,
}) {
  return HandInput(
    tiles: const [
      '1m', '2m', '3m', '4m', '0m', '6m', // 123m 4(5r)6m
      '2p', '3p', '4p',
      '7s', '8s', '9s',
      '1z', '1z', // 東の対子
    ],
    tsumoIndex: tsumoIndex,
    doraIndicators: doraIndicators,
    seatWind: seatWind,
    roundWind: roundWind,
    dealer: dealer,
    turn: turn,
  );
}

void main() {
  group('JSON', () {
    test('すべての項目が往復で保たれる（文字列化を挟んでも）', () {
      final original = HandInput(
        tiles: const [
          '1m',
          '2m',
          '3m',
          '0p',
          '6p',
          '7p',
          '8p',
          '3s',
          '4s',
          '5s',
          '2z',
        ],
        tsumoIndex: 10,
        melds: [
          MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
        ],
        doraIndicators: const ['4z', '9m'],
        seatWind: Wind.west,
        roundWind: Wind.south,
        dealer: false,
        turn: 7,
        visibleTiles: const ['2z', '9s'],
      );

      final text = jsonEncode(original.toJson());
      final restored = HandInput.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );

      expect(restored, original);
      expect(restored.toJson(), original.toJson());
    });

    test('槓・暗槓・親も往復で保たれる', () {
      final original = HandInput(
        tiles: const [
          '1m',
          '2m',
          '3m',
          '4m',
          '5m',
          '6m',
          '7m',
          '8m',
          '9m',
          '1p',
        ],
        melds: [
          MeldInput(
            kind: MeldKind.ankan,
            tiles: const ['9s', '9s', '9s', '9s'],
          ),
        ],
        seatWind: Wind.east,
      );
      expect(original.dealer, isTrue);
      final restored = HandInput.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      expect(restored, original);
      expect(restored.melds.single.kind, MeldKind.ankan);
      expect(restored.dealer, isTrue);
    });

    test('省略された任意項目は既定値になる', () {
      final restored = HandInput.fromJson({
        'tiles': ['1m', '2m', '3m'],
      });
      expect(restored.tsumoIndex, isNull);
      expect(restored.melds, isEmpty);
      expect(restored.doraIndicators, isEmpty);
      expect(restored.seatWind, Wind.south);
      expect(restored.roundWind, Wind.east);
      expect(restored.dealer, isFalse);
      expect(restored.turn, isNull);
      expect(restored.visibleTiles, isEmpty);
    });

    test('未知の風の名前は既定値に戻す', () {
      final restored = HandInput.fromJson({
        'tiles': <String>[],
        'seatWind': 'sideways',
        'roundWind': 3,
      });
      expect(restored.seatWind, Wind.south);
      expect(restored.roundWind, Wind.east);
    });

    test('型が違う・必須項目がないときは FormatException', () {
      expect(() => HandInput.fromJson({}), throwsFormatException);
      expect(() => HandInput.fromJson({'tiles': 'abc'}), throwsFormatException);
      expect(
        () => HandInput.fromJson({
          'tiles': ['1m'],
          'tsumoIndex': '0',
        }),
        throwsFormatException,
      );
      expect(
        () => HandInput.fromJson({
          'tiles': ['1m'],
          'melds': [
            {'kind': 'pon', 'tiles': 5},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => HandInput.fromJson({
          'tiles': ['1m'],
          'melds': [
            {
              'kind': 'nope',
              'tiles': ['1m'],
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('toHandState', () {
    test('手牌・赤5・ツモ牌を牌ごとの枚数に直す', () {
      final state = hand14(tsumoIndex: 13).toHandState();

      expect(state.tileCount, 14);
      expect(state.counts[0], 1); // 1m
      expect(state.counts[4], 1); // 5m（赤5も5として数える）
      expect(state.counts[27], 2); // 東
      expect(state.redIds, {4});
      expect(state.meldCount, 0);
    });

    test('ドラ表示牌はドラに直し、表示牌自身は見えている牌に入る', () {
      final state = hand14(
        doraIndicators: const ['4z', '9p', '0s'],
      ).toHandState();

      // 北(4z)→東、9p→1p、赤5s→6s。
      expect(state.doraIds, [27, 9, 23]);
      expect(state.visible[tileIdFromLabel('4z')], 1);
      expect(state.visible[tileIdFromLabel('9p')], 1);
      expect(state.visible[tileIdFromLabel('5s')], 1);
      expect(state.visible.fold<int>(0, (a, b) => a + b), 3);
    });

    test('見えている牌は残り枚数から引かれる', () {
      final input = HandInput(
        tiles: hand14().tiles,
        doraIndicators: const ['1z'],
        visibleTiles: const ['1z'],
      );
      final state = input.toHandState();
      // 東: 手牌に 2 枚 + 表示牌 1 枚 + 河 1 枚 = 4 枚で残り 0。
      expect(state.remaining(27), 0);
      expect(state.remaining(0), 3); // 1m は手に 1 枚
    });

    test('風・親・巡目を引き継ぐ', () {
      final state = hand14(
        seatWind: Wind.east,
        roundWind: Wind.south,
        turn: 9,
      ).toHandState();
      expect(state.seatWind, Wind.east);
      expect(state.roundWind, Wind.south);
      expect(state.dealer, isTrue);
      expect(state.turn, 9);
    });

    test('副露は mahjong_core の Meld になり、枚数は 3 枚として数える', () {
      final input = HandInput(
        tiles: const [
          '1m',
          '2m',
          '3m',
          '4m',
          '5m',
          '6m',
          '7m',
          '8m',
          '9m',
          '1p',
        ],
        melds: [
          MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
        ],
      );
      final state = input.toHandState();
      expect(state.tileCount, 13);
      expect(state.openMelds.single.type, MeldType.koutsu);
      expect(state.openMelds.single.open, isTrue);
      expect(state.meldTileCount(31), 3);

      final kan = HandInput(
        tiles: input.tiles,
        melds: [
          MeldInput(
            kind: MeldKind.ankan,
            tiles: const ['5z', '5z', '5z', '5z'],
          ),
        ],
      ).toHandState();
      expect(kan.tileCount, 13, reason: '槓は 3 枚と数える');
      expect(kan.openMelds.single.type, MeldType.kantsu);
      expect(kan.openMelds.single.open, isFalse);
      expect(kan.meldTileCount(31), 4);

      final chi = HandInput(
        tiles: input.tiles,
        melds: [
          MeldInput(kind: MeldKind.chi, tiles: const ['3s', '4s', '0s']),
        ],
      ).toHandState();
      expect(chi.openMelds.single.type, MeldType.shuntsu);
      expect(chi.redIds, contains(22), reason: '副露内の赤5も赤ドラ');
    });

    test('エンジンにそのまま渡せる', () {
      final state = hand14().toHandState();
      expect(shanten(state).shanten, -1, reason: '123m 456m 234p 789s 東東 は和了形');
      final thirteen = HandInput(tiles: hand14().tiles.take(13)).toHandState();
      expect(shanten(thirteen).shanten, 0);
      expect(ukeire(thirteen).total, greaterThan(0));
    });

    test('検証に通らない入力は HandInputException', () {
      expect(
        () => HandInput(tiles: const ['1m']).toHandState(),
        throwsA(isA<HandInputException>()),
      );
    });
  });

  group('validate', () {
    List<HandInputIssueKind> kinds(HandInput input) => [
      for (final issue in input.validate()) issue.kind,
    ];

    test('正常な 13・14 枚は指摘なし', () {
      expect(hand14().validate(), isEmpty);
      expect(hand14().isAnalyzable, isTrue);
      expect(HandInput(tiles: hand14().tiles.take(13)).isAnalyzable, isTrue);
    });

    test('枚数の過不足', () {
      expect(kinds(HandInput(tiles: hand14().tiles.take(12))), [
        HandInputIssueKind.tooFewTiles,
      ]);
      expect(kinds(HandInput(tiles: [...hand14().tiles, '7z'])), [
        HandInputIssueKind.tooManyTiles,
      ]);
      expect(kinds(HandInput.empty), [HandInputIssueKind.tooFewTiles]);
    });

    test('副露込みの枚数で数える（槓は 3 枚）', () {
      final input = HandInput(
        tiles: const [
          '1m',
          '2m',
          '3m',
          '4m',
          '5m',
          '6m',
          '7m',
          '8m',
          '9m',
          '1p',
        ],
        melds: [
          MeldInput(
            kind: MeldKind.minkan,
            tiles: const ['5z', '5z', '5z', '5z'],
          ),
        ],
      );
      expect(input.tileCount, 13);
      expect(input.validate(), isEmpty);
      // 副露を足して 16 枚に。
      expect(
        kinds(
          input.copyWith(
            melds: [
              ...input.melds,
              MeldInput(kind: MeldKind.pon, tiles: const ['6z', '6z', '6z']),
            ],
          ),
        ),
        [HandInputIssueKind.tooManyTiles],
      );
    });

    test('同じ牌は 4 枚まで（赤5も5として数える）', () {
      final input = HandInput(
        tiles: const [
          '5m',
          '5m',
          '5m',
          '5m',
          '0m',
          '1p',
          '2p',
          '3p',
          '4p',
          '5p',
          '6p',
          '7p',
          '8p',
        ],
      );
      final issues = input.validate();
      expect(issues.single.kind, HandInputIssueKind.tooManyOfOneTile);
      expect(issues.single.detail, '5m');
    });

    test('手牌と副露の合計でも 4 枚まで', () {
      final input = HandInput(
        tiles: const [
          '5z',
          '1m',
          '2m',
          '3m',
          '4m',
          '5m',
          '6m',
          '7m',
          '8m',
          '9m',
        ],
        melds: [
          MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
        ],
      );
      expect(input.validate(), isEmpty);
      expect(
        kinds(input.copyWith(tiles: [...input.tiles.take(9), '5z'])),
        contains(HandInputIssueKind.tooManyOfOneTile),
        reason: '5z が手牌 2 枚 + 副露 3 枚 = 5 枚',
      );
    });

    test('牌として読めないラベル', () {
      final input = HandInput(tiles: [...hand14().tiles.take(13), '8z']);
      final issues = input.validate();
      expect(issues.single.kind, HandInputIssueKind.invalidLabel);
      expect(issues.single.detail, '8z');
    });

    test('副露が成り立たない・ツモ牌の位置が範囲外・巡目が範囲外・表示牌が多すぎる', () {
      final badMeld = HandInput(
        tiles: hand14().tiles.take(10),
        melds: [
          MeldInput(kind: MeldKind.chi, tiles: const ['1m', '2m', '4m']),
        ],
      );
      expect(kinds(badMeld), [HandInputIssueKind.invalidMeld]);
      expect(kinds(hand14(tsumoIndex: 14)), [
        HandInputIssueKind.tsumoOutOfRange,
      ]);
      expect(kinds(hand14(turn: 0)), [HandInputIssueKind.invalidTurn]);
      expect(kinds(hand14(turn: 19)), [HandInputIssueKind.invalidTurn]);
      expect(hand14(turn: 18).validate(), isEmpty);
      expect(
        kinds(
          hand14(doraIndicators: const ['1m', '2m', '3m', '4m', '5m', '6m']),
        ),
        [HandInputIssueKind.tooManyDoraIndicators],
      );
    });
  });

  group('MeldInput', () {
    test('種類ごとの成立条件', () {
      bool valid(MeldKind kind, List<String> tiles) =>
          MeldInput(kind: kind, tiles: tiles).isValid;
      expect(valid(MeldKind.chi, ['3s', '4s', '5s']), isTrue);
      expect(valid(MeldKind.chi, ['5s', '3s', '4s']), isTrue);
      expect(valid(MeldKind.chi, ['3s', '4s', '0s']), isTrue);
      expect(valid(MeldKind.chi, ['8s', '9s', '1m']), isFalse);
      expect(valid(MeldKind.chi, ['1z', '2z', '3z']), isFalse);
      expect(valid(MeldKind.pon, ['5z', '5z', '5z']), isTrue);
      expect(valid(MeldKind.pon, ['5z', '5z', '6z']), isFalse);
      expect(valid(MeldKind.minkan, ['5p', '5p', '5p', '0p']), isTrue);
      expect(valid(MeldKind.ankan, ['5p', '5p', '5p']), isFalse);
    });

    test('牌の並びから種類を推定する', () {
      expect(MeldInput.guessKind(['5z', '5z', '5z']), MeldKind.pon);
      expect(MeldInput.guessKind(['4p', '3p', '5p']), MeldKind.chi);
      expect(MeldInput.guessKind(['1m', '1m', '1m', '1m']), MeldKind.minkan);
      expect(MeldInput.guessKind(['1m', '2m', '4m']), isNull);
      expect(MeldInput.guessKind(['1m', '1m']), isNull);
    });
  });

  group('変更', () {
    test('自風を変えると親・子がそろう', () {
      final east = hand14().withSeatWind(Wind.east);
      expect(east.dealer, isTrue);
      final west = east.withSeatWind(Wind.west);
      expect(west.dealer, isFalse);
      expect(west.seatWind, Wind.west);
    });

    test('親にすると東家、子にして東家なら南家になる', () {
      final dealer = hand14().withDealer(true);
      expect(dealer.seatWind, Wind.east);
      expect(dealer.dealer, isTrue);
      final child = dealer.withDealer(false);
      expect(child.seatWind, Wind.south);
      expect(child.dealer, isFalse);
      final west = hand14(seatWind: Wind.west).withDealer(false);
      expect(west.seatWind, Wind.west);
    });

    test('copyWith は null を渡すとツモ牌と巡目を消せる', () {
      final input = hand14(tsumoIndex: 13, turn: 5);
      expect(input.copyWith(doraIndicators: const ['1m']).tsumoIndex, 13);
      expect(input.copyWith(doraIndicators: const ['1m']).turn, 5);
      expect(input.copyWith(tsumoIndex: null).tsumoIndex, isNull);
      expect(input.copyWith(turn: null).turn, isNull);
    });

    test('normalized は理牌してツモ牌を末尾に置く', () {
      final input = HandInput(
        tiles: const [
          '9s',
          '1m',
          '5p',
          '2z',
          '7m',
          '3s',
          '1p',
          '8s',
          '4m',
          '6p',
          '7z',
          '2m',
          '9p',
          '5s',
        ],
        tsumoIndex: 4, // 7m
      );
      final normalized = input.normalized();
      expect(normalized.tiles.last, '7m');
      expect(normalized.tsumoIndex, 13);
      expect(normalized.tiles.take(13).toList(), [
        '1m',
        '2m',
        '4m',
        '1p',
        '5p',
        '6p',
        '9p',
        '3s',
        '5s',
        '8s',
        '9s',
        '2z',
        '7z',
      ]);
      expect(normalized.tsumoTile, '7m');
    });

    test('ツモ牌がなければ全体を並べる', () {
      final normalized = HandInput(
        tiles: const ['3p', '1m', '0m', '5m'],
      ).normalized();
      expect(normalized.tiles, ['1m', '0m', '5m', '3p']);
      expect(normalized.tsumoIndex, isNull);
    });
  });
}

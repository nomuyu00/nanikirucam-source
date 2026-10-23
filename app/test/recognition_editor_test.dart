import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_editor.dart';

RecognitionEditor editorOf(
  List<String> labels, {
  int? tsumoIndex,
  List<double?>? confidences,
  List<List<String>>? alternatives,
  List<MeldCandidate> melds = const [],
  HandInput? base,
}) {
  return RecognitionEditor.fromArgs(
    RecognitionArgs(
      draft: RecognitionDraft(
        labels: labels,
        tsumoIndex: tsumoIndex,
        confidences: confidences,
        alternatives: alternatives,
        melds: melds,
      ),
      base: base,
    ),
  );
}

const hand13 = [
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
  '2p',
  '3p',
  '4p', //
];

void main() {
  group('手牌の編集', () {
    test('開いた時点で理牌され、ツモ牌は末尾に移る', () {
      final editor = editorOf(
        ['9s', '1m', '5p', '7m'],
        tsumoIndex: 1, // 1m がツモ牌
      );
      expect(editor.state.labels, ['7m', '5p', '9s', '1m']);
      expect(editor.state.tsumoIndex, 3);
      expect(editor.canUndo, isFalse);
    });

    test('牌を直すと確度は手入力扱いになり、並びと強調位置が更新される', () {
      final editor = editorOf(
        ['1m', '2m', '9p'],
        confidences: [0.9, 0.9, 0.3],
        alternatives: [
          const [],
          const [],
          const ['8p'],
        ],
      );
      expect(editor.state.slots[2].isLowConfidence, isTrue);

      editor.replaceTile(2, '1m');

      expect(editor.state.labels, ['1m', '1m', '2m']);
      expect(editor.state.slots.every((s) => !s.isLowConfidence), isTrue);
      // 元からあった 1m（確度 0.9）が先、直した牌は手入力扱い（確度 null）で次に来る。
      expect(editor.state.slots[0].confidence, 0.9);
      expect(editor.lastEditedIndex, 1);
      expect(editor.state.slots[1].confidence, isNull);
      expect(editor.state.slots[1].alternatives, isEmpty);
    });

    test('牌を消すとツモ牌の添字がずれない', () {
      final editor = editorOf(['1m', '2m', '3m', '4m'], tsumoIndex: 3);
      editor.removeTile(0);
      expect(editor.state.labels, ['2m', '3m', '4m']);
      expect(editor.state.tsumoIndex, 2);

      editor.removeTile(2); // ツモ牌を消す
      expect(editor.state.labels, ['2m', '3m']);
      expect(editor.state.tsumoIndex, isNull);
    });

    test('牌を足すと理牌順に入り、ツモ牌は末尾のまま', () {
      final editor = editorOf(['1m', '5m', '9m'], tsumoIndex: 1);
      expect(editor.state.labels, ['1m', '9m', '5m']);
      editor.addTile('3m');
      expect(editor.state.labels, ['1m', '3m', '9m', '5m']);
      expect(editor.state.tsumoIndex, 3);
      expect(editor.lastEditedIndex, 1);
    });

    test('ツモ牌の指定と解除', () {
      final editor = editorOf(['1m', '2m', '3m']);
      editor.toggleTsumo(0);
      expect(editor.state.labels, ['2m', '3m', '1m']);
      expect(editor.state.tsumoIndex, 2);
      editor.toggleTsumo(2);
      expect(editor.state.tsumoIndex, isNull);
      expect(editor.state.labels, ['1m', '2m', '3m']);
    });

    test('範囲外の添字は無視する', () {
      final editor = editorOf(['1m']);
      editor
        ..replaceTile(5, '2m')
        ..removeTile(-1)
        ..toggleTsumo(3);
      expect(editor.state.labels, ['1m']);
      expect(editor.canUndo, isFalse);
    });

    test('元に戻す', () {
      final editor = editorOf(['1m', '2m']);
      editor
        ..addTile('3m')
        ..removeTile(0);
      expect(editor.state.labels, ['2m', '3m']);
      editor.undo();
      expect(editor.state.labels, ['1m', '2m', '3m']);
      editor.undo();
      expect(editor.state.labels, ['1m', '2m']);
      expect(editor.canUndo, isFalse);
      editor.undo(); // 何も起きない
      expect(editor.state.labels, ['1m', '2m']);
    });

    test('通知は変更があったときだけ', () {
      final editor = editorOf(['1m', '2m']);
      var notified = 0;
      editor.addListener(() => notified++);
      editor.setSeatWind(Wind.south); // すでに南家
      expect(notified, 0);
      editor.setSeatWind(Wind.west);
      expect(notified, 1);
    });

    test('同じ牌の枚数は手牌と副露の合計で数える', () {
      final editor = editorOf(
        ['5z', '0m', '5m'],
        base: HandInput(
          tiles: const [],
          melds: [
            MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
          ],
        ),
      );
      expect(editor.state.countOf('5z'), 4);
      expect(editor.state.countOf('5m'), 2, reason: '赤5も5として数える');
      expect(editor.state.countOf('9p'), 0);
    });
  });

  group('副露', () {
    const labels = [
      '1m',
      '2m',
      '3m',
      '6m',
      '7m',
      '8m',
      '2p',
      '3p',
      '4p',
      '5p',
      '5z',
      '5z',
      '5z',
    ];
    const candidate = MeldCandidate(indices: [10, 11, 12], kind: MeldKind.pon);

    test('候補を採用すると牌が手牌から副露に移る', () {
      final editor = editorOf(labels, melds: const [candidate]);
      expect(editor.state.applicableSuggestions, [0]);

      editor.applySuggestedMeld(0);

      expect(editor.state.labels, labels.take(10).toList());
      expect(editor.state.melds.single.kind, MeldKind.pon);
      expect(editor.state.melds.single.tiles, ['5z', '5z', '5z']);
      expect(editor.state.suggestedMelds, isEmpty);
      expect(editor.input.tileCount, 13);
      expect(editor.input.validate(), isEmpty);
    });

    test('候補の牌が手牌からなくなったら採用できない', () {
      final editor = editorOf(labels, melds: const [candidate]);
      editor.removeTile(editor.state.labels.indexOf('5z'));
      expect(editor.state.applicableSuggestions, isEmpty);
      editor.applySuggestedMeld(0);
      expect(editor.state.melds, isEmpty);
    });

    test('候補を捨てる', () {
      final editor = editorOf(labels, melds: const [candidate]);
      editor.dismissSuggestedMeld(0);
      expect(editor.state.suggestedMelds, isEmpty);
      expect(editor.state.labels, labels);
    });

    test('手で足した副露は、手牌にある分だけ手牌から外れる', () {
      final editor = editorOf(labels);
      editor.addMeld(
        MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
      );
      expect(editor.state.labels, labels.take(10).toList());
      expect(editor.input.tileCount, 13);

      // 手牌にない牌の副露は、そのまま足される（手入力）。
      final manual = editorOf(const ['1m', '2m', '3m']);
      manual.addMeld(
        MeldInput(kind: MeldKind.chi, tiles: const ['4p', '5p', '6p']),
      );
      expect(manual.state.labels, ['1m', '2m', '3m']);
      expect(manual.input.tileCount, 6);
    });

    test('副露をやめると牌が手牌に戻る', () {
      final editor = editorOf(labels, melds: const [candidate]);
      editor.applySuggestedMeld(0);
      editor.removeMeld(0);
      expect(editor.state.melds, isEmpty);
      expect(editor.state.labels.where((l) => l == '5z'), hasLength(3));
      expect(editor.input.tileCount, 13);
    });

    test('槓は明槓と暗槓を切り替えられる', () {
      final editor = editorOf(const ['1m']);
      editor.addMeld(
        MeldInput(kind: MeldKind.minkan, tiles: const ['9p', '9p', '9p', '9p']),
      );
      editor.setMeldKind(0, MeldKind.ankan);
      expect(editor.state.melds.single.kind, MeldKind.ankan);
      expect(editor.input.isOpen, isFalse);
    });

    test('副露に使った牌のうち赤5は赤のまま移る', () {
      final editor = editorOf(const ['3s', '4s', '0s', '1m']);
      editor.addMeld(
        MeldInput(kind: MeldKind.chi, tiles: const ['3s', '4s', '0s']),
      );
      expect(editor.state.labels, ['1m']);
      expect(editor.state.melds.single.tiles, ['3s', '4s', '0s']);
    });
  });

  group('局の条件', () {
    test('自風と親は連動する', () {
      final editor = editorOf(const ['1m']);
      editor.setSeatWind(Wind.east);
      expect(editor.state.dealer, isTrue);
      editor.setSeatWind(Wind.north);
      expect(editor.state.dealer, isFalse);
      editor.setDealer(true);
      expect(editor.state.seatWind, Wind.east);
      editor.setDealer(false);
      expect(editor.state.seatWind, Wind.south);
      expect(editor.state.dealer, isFalse);
    });

    test('巡目は 1〜18 に収め、null で未指定に戻る', () {
      final editor = editorOf(const ['1m']);
      editor.setTurn(0);
      expect(editor.state.turn, 1);
      editor.setTurn(30);
      expect(editor.state.turn, HandInput.maxTurn);
      editor.setTurn(null);
      expect(editor.state.turn, isNull);
    });

    test('HandInput にまとめて渡せる', () {
      final editor = editorOf(
        hand13,
        base: HandInput(
          tiles: const [],
          seatWind: Wind.west,
          roundWind: Wind.south,
          doraIndicators: const ['1z'],
          turn: 5,
        ),
      );
      editor.setDoraIndicators(const ['1z', '9m']);
      final input = editor.input;
      expect(input.seatWind, Wind.west);
      expect(input.roundWind, Wind.south);
      expect(input.doraIndicators, ['1z', '9m']);
      expect(input.turn, 5);
      expect(input.tiles, hand13);
    });
  });

  group('previewHand（シャンテン数と受け入れ）', () {
    HandInput input(List<String> tiles, {int? tsumoIndex}) =>
        HandInput(tiles: tiles, tsumoIndex: tsumoIndex);

    test('13 枚のテンパイ', () {
      // 123m 456m 789m 123p + 4p の単騎。
      final preview = previewHand(input(hand13))!;
      expect(preview.tileCount, 13);
      expect(preview.shanten, 0);
      expect(preview.ukeireTotal, greaterThan(0));
      expect(preview.bestDiscardId, isNull);
      expect(preview.isComplete, isFalse);
    });

    test('14 枚は最良の打牌後のシャンテン数と受け入れ', () {
      final preview = previewHand(input([...hand13, '9s'], tsumoIndex: 13))!;
      expect(preview.tileCount, 14);
      expect(preview.shanten, 0);
      expect(preview.bestDiscardId, tileIdFromLabel('9s'));
      expect(preview.ukeireTotal, greaterThan(0));
    });

    test('14 枚の和了形', () {
      final preview = previewHand(
        input([
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
          '2p',
          '3p',
          '4p',
          '4p',
        ]),
      )!;
      expect(preview.isComplete, isTrue);
      expect(preview.bestDiscardId, isNull);
      expect(preview.ukeireTotal, 0);
    });

    test('副露があっても解析できる', () {
      final preview = previewHand(
        HandInput(
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
            '4p',
          ],
          melds: [
            MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
          ],
        ),
      )!;
      expect(preview.tileCount, 13);
      expect(preview.shanten, 0);
    });

    test('枚数が合わない・牌が多すぎる入力は null', () {
      expect(previewHand(input(const ['1m', '2m'])), isNull);
      expect(previewHand(HandInput.empty), isNull);
      expect(
        previewHand(input(['1m', '1m', '1m', '1m', '1m', ...hand13.skip(5)])),
        isNull,
      );
    });
  });

  test('TileSlot の確度が閾値未満なら低確度', () {
    expect(const TileSlot('1m', confidence: 0.59).isLowConfidence, isTrue);
    expect(const TileSlot('1m', confidence: 0.6).isLowConfidence, isFalse);
    expect(const TileSlot('1m').isLowConfidence, isFalse);
    expect(
      TileSlot('1m', box: const Rect.fromLTWH(0, 0, 1, 1)).box,
      const Rect.fromLTWH(0, 0, 1, 1),
    );
  });
}

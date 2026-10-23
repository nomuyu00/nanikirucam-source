import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';

/// 認識中・認識結果の修正（手入力を含む）画面の文言。
class RecognitionStrings extends FeatureStrings {
  const RecognitionStrings(super.lang);

  CommonStrings get _common => CommonStrings(lang);

  // --- 認識中 ---
  String get loadingTitle => tr('認識中', 'Recognizing');
  String get loadingMessage => tr('牌を認識しています', 'Recognizing the tiles');
  String get loadingHint => tr(
    '画面中央の横一列を優先して解析しています。',
    'Looking for a row of tiles near the center of the photo.',
  );
  String get imageLoadFailed => tr(
    '撮影画像を読み込めませんでした。もう一度撮影してください。',
    'Could not load the photo. Please take it again.',
  );
  String get modelFailed => tr(
    '牌の認識機能を起動できませんでした。再解析をお試しください。',
    'Could not start tile recognition. Please try again.',
  );
  String get noTiles => tr(
    '牌が検出できませんでした。もう一度撮影するか、手入力してください。',
    'No tiles were found. Take the photo again or enter the tiles by hand.',
  );
  String get retake => tr('撮り直す', 'Retake');
  String get manualInput => tr('手入力する', 'Enter by hand');
  String get reanalyze => tr('再解析', 'Analyze again');
  String get incompleteNotice => tr(
    '13〜14枚に満たない可能性があります。牌の追加・変更を確認してください。',
    'Fewer than 13 tiles may have been found. Check the tiles and add or fix them.',
  );

  // --- 修正画面 ---
  String get title => tr('認識結果の確認', 'Check the tiles');
  String get manualTitle => tr('手入力', 'Enter tiles');
  String get recapture => tr('撮り直す', 'Retake');
  String handHeader(int n) => tr('手牌（$n枚）', 'Hand ($n tiles)');
  String get lowConfidenceNotice => tr(
    '赤枠の牌は認識に自信がありません。タップして確認してください。',
    'Tiles with a red frame are uncertain. Tap to check them.',
  );
  String get editHint => tr(
    '牌が違うときはタップして直せます。足りない牌は＋で追加。',
    'Tap a tile to fix it. Use + to add missing tiles.',
  );
  String get emptyHint =>
      tr('＋から牌を追加して手牌を入力してください', 'Use + to add the tiles of your hand');
  String get addTile => tr('牌を追加', 'Add a tile');
  String get tsumoBadge => tr('ツモ', 'Draw');
  String get tsumoHint => tr(
    'ツモ牌は牌をタップして「ツモ牌にする」で指定できます。',
    'Tap a tile and choose "Mark as drawn tile" to set the tile you just drew.',
  );
  String get photoZoom => tr('撮影した写真を拡大', 'Enlarge the photo');

  // --- 牌の選択 ---
  String get fixTile => tr('この牌を直す', 'Fix this tile');
  String get markTsumo => tr('ツモ牌にする', 'Mark as drawn tile');
  String get unmarkTsumo => tr('ツモ牌を解除', 'Unmark drawn tile');
  String get addTilesTitle =>
      tr('牌を追加（続けてタップで複数追加）', 'Add tiles (tap several in a row)');
  String pickerCounter(String title, int n) =>
      '$title  ($n${tr('枚', ' tiles')})';
  String get doraTitle =>
      tr('ドラ表示牌を選ぶ（カンドラも続けて追加）', 'Pick dora indicators (kan dora too)');
  String get doraTapHint => tr('表示牌（めくれている牌）をタップ', 'Tap the indicator tile(s)');

  // --- 副露 ---
  String get meldsHeader => tr('副露', 'Melds');
  String get noMelds => tr('なし', 'None');
  String get addMeld => tr('副露を追加', 'Add a meld');
  String get meldSuggestion =>
      tr('右端に副露の候補があります', 'A meld may be at the right end');
  String get adoptMeld => tr('副露にする', 'Use as meld');
  String get dismiss => tr('違う', 'Not a meld');
  String get removeMeld => tr('副露をやめる', 'Remove meld');
  String get meldPickerTitle =>
      tr('副露の種類を選び、牌をタップ', 'Pick a kind, then tap the tile');
  String get meldPickerHintChi => tr(
    '順子の最小の牌（例: 3-4-5 なら 3）をタップ',
    'Tap the lowest tile of the run (3 for 3-4-5)',
  );
  String get meldPickerHintOther => tr('牌をタップ', 'Tap the tile');
  String meldKind(MeldKind kind) => switch (kind) {
    MeldKind.chi => tr('チー', 'Chi'),
    MeldKind.pon => tr('ポン', 'Pon'),
    MeldKind.minkan => tr('明槓', 'Open kan'),
    MeldKind.ankan => tr('暗槓', 'Closed kan'),
  };

  // --- 局の条件 ---
  String get conditionsHeader => tr('局の条件', 'Round settings');
  String get seatWind => tr('自風', 'Seat wind');
  String get roundWind => tr('場風', 'Round wind');
  String get dealerLabel => tr('親', 'Dealer');

  /// 自風の選択肢。日本語は東に「（親）」を添える。英語は親の選択が別にあり、
  /// 「East (Dealer)」では 4 つ並べたときに縮んで読めないので風の名前だけにする。
  String seatWindChoice(Wind wind) => wind == Wind.east && !isEnglish
      ? '${_common.windName(wind)}（${_common.dealer}）'
      : _common.windName(wind);
  String get turnLabel => tr('巡目（任意）', 'Turn (optional)');
  String get turnUnset => tr('未指定', 'Not set');
  String turnValue(int turn) => tr('$turn巡目', 'Turn $turn');
  String get turnHint =>
      tr('上がりやすさの％に使います', 'Used for the win-chance estimate');
  String get doraHeader => tr('ドラ表示牌', 'Dora indicators');
  String get pickDora => tr('表示牌を選ぶ', 'Pick indicators');
  String get noDora => tr('未入力', 'Not set');
  String get decrease => tr('減らす', 'Decrease');
  String get increase => tr('増やす', 'Increase');

  // --- 下部バー ---
  String get solveFourteen => tr('この手を解く', 'Solve this hand');
  String get solveThirteen => tr('待ちを見る', 'See the waits');

  // --- 点数計算モード（Pro。和了の点数画面へ進む） ---
  String get scoreTitle => tr('点数計算', 'Score a win');
  String get scoreManualTitle => tr('点数計算（手入力）', 'Score: enter tiles');
  String get scoreButton => tr('点数を計算', 'Score it');
  String get winningBadge => tr('和了', 'Win');
  String get markWinning => tr('和了牌にする', 'Mark as winning tile');
  String get unmarkWinning => tr('和了牌を解除', 'Unmark winning tile');
  String get winningHint => tr(
    '和了牌（ツモった牌・ロンした牌）をタップして「和了牌にする」で指定してください。指定しなければ最後の牌にします。',
    'Tap the winning tile and choose "Mark as winning tile". Otherwise the last tile is used.',
  );
  String get scoreNeedFourteen =>
      tr('和了牌を足して14枚にしてください', 'Add the winning tile to make 14 tiles');
  String scoreNotWinning(int shanten) => tr(
    '和了形ではありません（${_common.shanten(shanten)}）。牌を確かめてください',
    'Not a winning hand (${_common.shanten(shanten)}). Please check the tiles',
  );
  String get scoreReadyNoWinning => tr(
    '和了形です。和了牌を指定してください（未指定なら最後の牌）',
    'Winning hand. Mark the winning tile (or the last tile is used)',
  );
  String scoreReady(String tile) => tr(
    '和了形です（和了牌: ${_common.tileName(tile)}）',
    'Winning hand (winning tile: ${_common.tileName(tile)})',
  );

  /// シャンテン数と受け入れのプレビュー。
  String previewLine({
    required int shanten,
    required int ukeireTotal,
    required int tileCount,
    String? bestDiscard,
  }) {
    if (shanten < 0) return tr('和了形です', 'This is a winning hand');
    final head = _common.shanten(shanten);
    final discard = bestDiscard == null
        ? ''
        : tr(
            '（${_common.tileName(bestDiscard)}切り）',
            ' (discard ${_common.tileName(bestDiscard)})',
          );
    return tr(
      '$head・受け入れ$ukeireTotal枚$discard',
      '$head, $ukeireTotal tiles to improve$discard',
    );
  }

  /// 解析に進めない理由。
  String issueText(HandInputIssue issue) => switch (issue.kind) {
    HandInputIssueKind.invalidLabel => tr(
      '牌として読めないものがあります',
      'There is an unreadable tile',
    ),
    HandInputIssueKind.tooFewTiles => tr(
      '牌が足りません（${issue.detail}枚）。13〜14枚にしてください',
      'Not enough tiles (${issue.detail}). Use 13 or 14.',
    ),
    HandInputIssueKind.tooManyTiles => tr(
      '牌が多すぎます（${issue.detail}枚）。13〜14枚にしてください',
      'Too many tiles (${issue.detail}). Use 13 or 14.',
    ),
    HandInputIssueKind.tooManyOfOneTile => tr(
      '${_common.tileName(issue.detail ?? '')}が5枚以上あります',
      'There are more than four ${_common.tileName(issue.detail ?? '')}',
    ),
    HandInputIssueKind.invalidMeld => tr(
      '副露の牌の組み合わせが正しくありません',
      'A meld has an invalid combination of tiles',
    ),
    HandInputIssueKind.tsumoOutOfRange => tr(
      'ツモ牌の指定が正しくありません',
      'The drawn tile is not valid',
    ),
    HandInputIssueKind.tooManyDoraIndicators => tr(
      'ドラ表示牌が多すぎます',
      'Too many dora indicators',
    ),
    HandInputIssueKind.invalidTurn => tr(
      '巡目は1〜${HandInput.maxTurn}で指定してください',
      'Turn must be 1-${HandInput.maxTurn}',
    ),
  };
}

extension RecognitionStringsContext on BuildContext {
  RecognitionStrings get recognitionStrings => RecognitionStrings(lang);
}

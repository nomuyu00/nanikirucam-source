import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/result/result_logic.dart';

/// 結果・候補の詳細・解説（result/）の文言。
class ResultStrings extends FeatureStrings {
  const ResultStrings(super.lang);

  String get title => tr('結果', 'Result');
  String get candidateTitle => tr('候補の詳細', 'Candidate details');
  String get explanationTitle => tr('解説', 'Explanation');

  String get analyzing => tr('解析しています…', 'Analyzing…');
  String get analysisFailed => tr('解析できませんでした', 'Could not analyze this hand');
  String get noHand => tr('手牌がありません', 'No hand to show');
  String get retry => tr('もう一度', 'Try again');

  // --- 軸 -----------------------------------------------------------------

  /// 軸の切り替えボタン（仕様 4.1）。
  String axis(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('速さ', 'Speed'),
    StrategyAxis.points => tr('打点', 'Points'),
    StrategyAxis.balance => tr('バランス', 'Balance'),
  };

  /// 軸の 1 位のバッジ（仕様 4.1「最速」「高打点」「バランス」）。
  String badge(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('最速', 'Fastest'),
    StrategyAxis.points => tr('高打点', 'Highest value'),
    StrategyAxis.balance => tr('バランス', 'Balanced'),
  };

  /// 「打点重視なら正解」の「打点重視」。
  String focus(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('速さ重視', 'Speed-first'),
    StrategyAxis.points => tr('打点重視', 'Value-first'),
    StrategyAxis.balance => tr('バランス重視', 'Balanced'),
  };

  String axisHint(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr(
      'あがりやすさ優先。シャンテン数 → 受け入れ枚数 → 良形',
      'Win fast: shanten, then tiles to draw, then good waits',
    ),
    StrategyAxis.points => tr(
      '想定打点優先。シャンテン数は最良より 1 悪いまで',
      'Win big: expected value, up to one step slower',
    ),
    StrategyAxis.balance => tr(
      'あがりやすさ × 想定打点。迷ったらこれ',
      'Win rate × expected value. The default',
    ),
  };

  // --- 3 軸の答え -----------------------------------------------------------

  String get oneChoice => tr('一択', 'Only choice');
  String get oneChoiceBody =>
      tr('速さ・打点・バランスのどれで考えても同じ答えです', 'Speed, points and balance all agree');
  String sameTie(int n) =>
      tr('3 軸とも同じ答え（同点 $n 枚）', 'All three axes agree ($n tied tiles)');
  String get splitTitle => tr('方針で答えが分かれる手', 'The answer depends on your plan');

  /// 答えが分かれる手の説明。[online] が false（サーバーなしの版）では、
  /// Web での回答を前提にした「出題すると盛り上がります」を付けない。
  String splitBody({required bool speedVsPoints, bool online = true}) {
    if (!online) {
      return speedVsPoints
          ? tr('速さと打点で答えが分かれる手です', 'Speed and points disagree on this hand')
          : tr('方針によって答えが変わる手です', 'The plan changes the answer on this hand');
    }
    return speedVsPoints
        ? tr(
            '速さと打点で答えが分かれる手。出題すると盛り上がります',
            'Speed and points disagree. A great one to quiz friends with',
          )
        : tr(
            '方針によって答えが変わる手。出題すると盛り上がります',
            'The plan changes the answer. A great one to quiz friends with',
          );
  }

  String answerOf(StrategyAxis a) => tr('${axis(a)}の答え', '${axis(a)} answer');

  /// 上部の要約（「一向聴  受け入れ 24枚」）。
  String ukeireTotal(int n) => tr('受け入れ $n枚', '$n tiles to draw');
  String ukeire(int kinds, int total) =>
      tr('受け入れ $kinds種 $total枚', '$total tiles ($kinds kinds)');

  // --- クイズとの比較 ---------------------------------------------------------

  String get yourChoice => tr('あなたの選択', 'Your choice');
  String get correct => tr('正解！', 'Correct!');
  String get incorrect => tr('不正解', 'Not quite');
  String correctFor(StrategyAxis a) =>
      tr('${focus(a)}なら正解', 'Correct for ${focus(a).toLowerCase()} play');
  String rankOn(StrategyAxis a, int rank) =>
      tr('${axis(a)} $rank位', '#$rank on ${axis(a).toLowerCase()}');
  String get skipped => tr('クイズはスキップしました', 'You skipped the quiz');
  String communityTitle(int n) =>
      tr('みんなの回答（$n 人）', 'How others answered ($n)');
  String get reportProblem => tr('この問題を通報', 'Report this problem');
  String communityRate(int percent, int n) =>
      tr('みんなの正解率 $percent%（$n 人）', '$percent% of $n players got it');

  // --- 候補 ---------------------------------------------------------------

  String get discard => tr('切る', 'Discard');
  String rankLabel(int rank) => tr('$rank位', '#$rank');
  String get notRanked => tr('対象外', 'n/a');

  String shantenChange(ShantenChange change, String shanten) =>
      switch (change) {
        ShantenChange.tenpai => tr('テンパイ', 'Tenpai'),
        ShantenChange.keep => tr('$shantenのまま', 'Stays $shanten'),
        ShantenChange.back => tr('$shantenに戻る', 'Back to $shanten'),
      };

  String get yakuTitle => tr('狙える役', 'Yaku');
  String get noYakuProspect => tr('なし', 'None yet');
  String confidence(YakuConfidence c) => switch (c) {
    YakuConfidence.certain => tr('確定', 'Certain'),
    YakuConfidence.likely => tr('濃厚', 'Likely'),
    YakuConfidence.possible => tr('狙える', 'Possible'),
    YakuConfidence.lost => tr('消える', 'Lost'),
  };
  String confidenceHelp(YakuConfidence c) => switch (c) {
    YakuConfidence.certain => tr('どの受け入れであがっても成立する', 'Holds whatever you draw'),
    YakuConfidence.likely => tr(
      '受け入れの 7 割以上（残り枚数で重み付け）で成立する',
      'Holds on 70%+ of the draws (weighted by tiles left)',
    ),
    YakuConfidence.possible => tr(
      '特定の牌を引けば成立する',
      'Holds if you draw particular tiles',
    ),
    YakuConfidence.lost => tr('この打牌で成立しなくなる', 'This discard gives it up'),
  };
  String enabling(String tiles) => tr('$tilesを引けば', 'draw $tiles');
  String doraCount(int n) => tr('ドラ$n', 'Dora $n');

  String get pointsTitle => tr('想定打点', 'Est. points');
  String get estimate => tr('目安', 'Rough');
  String get riichiIncluded => tr('リーチ込み', 'with riichi');
  String get dama => tr('ダマ', 'No riichi');
  String pointsLevel(PointsLevel level) => switch (level) {
    PointsLevel.cheap => tr('安い', 'Low'),
    PointsLevel.normal => tr('普通', 'Medium'),
    PointsLevel.high => tr('高い', 'High'),
  };
  String about(String points) => tr('約 $points', '~$points');
  String get noPoints => tr('—', '—');
  String rangeMedian(String median) => tr('中央 $median', 'median $median');
  String get pointsNote => tr(
    '現在の親子、ロンとツモの両方。裏ドラ・一発は含みません',
    'For your seat, ron and tsumo. No ura dora or ippatsu',
  );

  String get winEaseTitle => tr('上がりやすさ', 'Win chance');
  String winEaseLevel(WinEaseLevel level) => switch (level) {
    WinEaseLevel.high => tr('高', 'High'),
    WinEaseLevel.medium => tr('中', 'Medium'),
    WinEaseLevel.low => tr('低', 'Low'),
  };
  String get winEaseNote => tr(
    '残り枚数と巡目からの目安。他家の動きは含みません',
    'From tiles left and the turn. Other players are not modeled',
  );

  String get goodShapeTitle => tr('良形率', 'Good waits');
  String get goodShapeHelp => tr(
    'テンパイしたときに両面以上（残り 5 枚以上）の待ちになる割合',
    'How often your tenpai has a wait of 5+ live tiles',
  );
  String get twoStepTitle => tr('2 段階先', 'Two steps ahead');
  String twoStepAverage(String n) =>
      tr('受け入れを引いた後の受け入れ 平均 $n 枚', 'avg. $n tiles after the next draw');
  String get reasonTitle => tr('理由', 'Why');
  String get cautionTitle => tr('注意点', 'Watch out');
  String get proOnly => tr('Pro', 'Pro');
  String moreLocked(int n) => tr(
    '残り $n 件の候補と、役の確度・打点のレンジは Pro で見られます',
    '$n more candidates, yaku odds and point ranges with Pro',
  );
  String get lockedYaku => tr('確度と成立条件', 'Odds and conditions');
  String get lockedRange => tr('レンジ', 'Range');
  String get openDetail => tr('詳しく', 'Details');
  String get closeDetail => tr('閉じる', 'Less');
  String get moreDetail => tr('詳細ページ', 'Full details');

  // --- 結論・候補の一覧 -----------------------------------------------------

  /// 結論のカードの見出し（[axis] はいま選んでいる軸）。
  String conclusionTitle(StrategyAxis a) =>
      tr('おすすめの打牌（${axis(a)}）', 'Best discard (${axis(a)})');
  String get candidatesTitle => tr('候補', 'Candidates');
  String get handTitle => tr('手牌', 'Your hand');

  // --- 13 枚 --------------------------------------------------------------

  String get waitsTitle => tr('待ち', 'Waits');
  String remaining(int n) => tr('残り $n枚', '$n left');
  String waitsSummary(String tiles, int n) =>
      tr('待ち $tiles（残り $n 枚）', 'Waiting on $tiles ($n left)');
  String get ron => tr('ロン', 'Ron');
  String get tsumo => tr('ツモ', 'Tsumo');
  String get noYaku => tr('役なし', 'No yaku');
  String get closedNoYaku => tr(
    '役がありません。リーチをかければあがれます（ツモなら役なしでもあがれます）',
    'No yaku. Declare riichi to win by ron (tsumo wins even without yaku)',
  );
  String get openNoYaku => tr(
    '役がないのであがれません。役がつく形に変えましょう',
    'No yaku, so you cannot win. Change to a shape with a yaku',
  );
  String get riichiPossible => tr('リーチできます', 'You can declare riichi');
  String get openWithYaku => tr('役があるのであがれます', 'You have a yaku and can win');
  String get fewWaits => tr(
    '待ちが少ないので、形を変える候補もあります',
    'Few tiles left for your wait. Changing shape is worth a look',
  );
  String get noWaitsLeft =>
      tr('待ちが残っていません（空テン）', 'No live tiles left for your wait');
  String get drawsTitle => tr('受け入れ', 'Outs');
  String get thirteenHint => tr(
    'ツモ牌を入れて 14 枚にすると、何を切るかを解けます',
    'Add the drawn tile (14 tiles) to solve what to discard',
  );
  String get riichiAdviceTitle => tr('リーチ判断', 'Riichi or not');
  String get riichiRecommend => tr('リーチ推奨', 'Riichi recommended');
  String get riichiWait => tr('様子見（ダマ）', 'Stay quiet (dama)');
  String riichiReason(RiichiReason reason) => switch (reason) {
    RiichiReason.noYaku => tr(
      'ダマでは役がないので、リーチ一択です',
      'No yaku without riichi, so riichi it is',
    ),
    RiichiReason.riichiValue => tr(
      'リーチで打点が上がるので、リーチがおすすめです',
      'Riichi raises the value enough to be worth it',
    ),
    RiichiReason.damaValue => tr(
      'ダマでも打点が十分なので、様子見もあります',
      'Already valuable without riichi; staying quiet is fine',
    ),
    RiichiReason.noWaitsLeft => tr(
      '待ちが残っていないので、リーチしてもあがれません',
      'No live tiles left, so riichi cannot win',
    ),
  };
  String riichiCompare(String points, String ease, String value) => tr(
    'リーチ: 平均 $points 点 × 上がりやすさ $ease = $value',
    'Riichi: avg. $points × win chance $ease = $value',
  );
  String damaCompare(String points, String ease, String value) => tr(
    'ダマ: 平均 $points 点 × $ease × 1.1 = $value',
    'Dama: avg. $points × $ease × 1.1 = $value',
  );
  String get riichiLocked =>
      tr('リーチ判断（打点と上がりやすさの比較）', 'Riichi advice (value comparison)');

  // --- 和了形 -------------------------------------------------------------

  String get winTitle => tr('ツモ和了の形です', 'This is a winning hand (tsumo)');
  String hanFu(int han, int fu) => tr('$han翻 $fu符', '$han han $fu fu');
  String han(int han) => tr('$han翻', '$han han');
  String points(String p) => tr('$p 点', '$p pts');
  String get winNoYaku =>
      tr('和了の形ですが役がありません', 'A complete hand, but without a yaku');

  // --- 下部のボタン ---------------------------------------------------------

  String get nextHand => tr('次の手を撮る', 'Next hand');
  String get share => tr('シェア', 'Share');
  String get publish => tr('友達に出題', 'Quiz friends');

  /// サーバーなしの版の下部ボタン（公開せず、問題カードの画像を共有する）。
  String get shareProblemCardButton => tr('問題カードを共有', 'Share quiz card');
  String get shareResultCard => tr('結果カード', 'Result card');
  String get shareResultCardBody =>
      tr('あなたの選択と 3 軸の答え', 'Your choice vs. the three answers');
  String get shareProblemCard => tr('問題カード', 'Problem card');
  String get shareProblemCardBody =>
      tr('答えを隠して友達に出す', 'Hide the answer and quiz friends');

  /// サーバーなしの版（Web で回答してもらえない）の説明。
  String get shareProblemCardBodyOffline =>
      tr('答えを隠した問題の画像', 'An image of the problem with the answer hidden');

  String get disclaimer => tr(
    '受け入れ枚数と役・打点の計算に基づく解です。他家の河・安全度は考えていません。',
    'Based on tile counts, yaku and points. Other players\' discards and safety are not considered.',
  );

  // --- 候補の詳細・解説 -------------------------------------------------------

  String detailTitle(String tile) => tr('打 $tile', 'Discard $tile');
  String get handAfter => tr('この牌を切ったあとの手', 'Your hand after the discard');
  String get ukeireTiles => tr('受け入れ牌', 'Tiles that help');
  String get perDrawTitle => tr('受け入れ牌ごとの変化', 'After each draw');
  String drawThen(String draw, String discards, String shanten, int n) => tr(
    '$drawを引く → 打$discardsで$shanten（受け入れ $n 枚）',
    'Draw $draw → discard $discards: $shanten ($n tiles)',
  );
  String improveThen(String draw, String discards, int n) => tr(
    '$drawを引く → 打$discardsで受け入れ $n 枚に増える（改良）',
    'Draw $draw → discard $discards: $n tiles (improvement)',
  );
  String get candidateMissing =>
      tr('この候補は見つかりませんでした', 'This candidate was not found');
  String get candidateLockedBody => tr(
    '上位 3 件より下の候補は Pro で見られます',
    'Candidates below the top 3 are available with Pro',
  );
  String get openExplanation => tr('解説を見る', 'Read the explanation');
  String get blocksTitle => tr('ブロック分解', 'Hand breakdown');
  String blockRole(BlockRole role) => switch (role) {
    BlockRole.meld => tr('面子', 'Set'),
    BlockRole.ryanmen => tr('両面', 'Open wait'),
    BlockRole.kanchan => tr('嵌張', 'Closed wait'),
    BlockRole.penchan => tr('辺張', 'Edge wait'),
    BlockRole.pair => tr('対子', 'Pair'),
    BlockRole.head => tr('雀頭', 'Head'),
    BlockRole.isolated => tr('孤立', 'Isolated'),
  };
  String get compareTitle =>
      tr('3 軸の答えとの比較', 'Compared with the three answers');
  String get legendTitle => tr('役の確度の見方', 'How to read yaku odds');
  String get explanationLockedTitle =>
      tr('解説は Pro の機能です', 'The explanation is a Pro feature');
  String get explanationLockedBody => tr(
    'ブロック分解、受け入れ牌ごとの変化、2 段階先、リーチ判断を見られます。動画広告を見ると、この手だけ 1 回見られます。',
    'See the hand breakdown, each draw, two steps ahead and riichi advice. Watch a video to unlock this hand once.',
  );
  String get watchVideo => tr('動画を見て 1 回だけ見る', 'Watch a video to unlock once');
  String get videoUnavailable => tr('動画を読み込めませんでした', 'The video is not ready');
  String get seePro => tr('Pro を見る', 'See Pro');
  String get reasonsEmpty => tr('特記事項はありません', 'Nothing special to note');
  String get choiceReasons => tr('この打牌を選ぶ理由', 'Why this discard');
}

extension ResultStringsContext on BuildContext {
  ResultStrings get resultStrings => ResultStrings(lang);
}

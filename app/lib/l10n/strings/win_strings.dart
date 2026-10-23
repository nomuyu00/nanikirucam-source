import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

/// 和了の役と点数（win/）の文言。共有カード・共有の本文でも使う。
class WinStrings extends FeatureStrings {
  const WinStrings(super.lang);

  CommonStrings get _common => CommonStrings(lang);

  // --- 画面 -----------------------------------------------------------------
  String get title => tr('役と点数', 'Yaku & points');
  String get editHand => tr('手牌を直す', 'Edit tiles');
  String get handHeader => tr('和了の手', 'Winning hand');
  String get tapToChangeWinning =>
      tr('牌をタップすると和了牌を選び直せます', 'Tap a tile to choose the winning tile');
  String get winningTileLabel => tr('和了牌', 'Win');
  String get winTypeLabel => tr('和了', 'Win by');
  String get yakuHeader => tr('役', 'Yaku');
  String get conditionsHeader => tr('条件', 'Conditions');
  String get moreConditions => tr('その他の条件', 'More conditions');
  String moreConditionsSummary(int n) => n == 0
      ? tr('偶然役・本場・供託', 'Lucky yaku, honba, deposits')
      : tr('$n件 設定中', '$n set');
  String get share => tr('共有', 'Share');
  String get shareQuiz => tr('点数を隠して出題', 'Share as a quiz');
  String get shareQuizHint => tr(
    '点数と役を隠した画像で「何点？」と出題します',
    'Shares an image with the points and yaku hidden',
  );

  // --- 結果 -----------------------------------------------------------------

  /// 満貫以上の名前（満貫未満は空）。
  String rankName(HandRank rank) {
    if (!isEnglish) return rank.jaName;
    return switch (rank) {
      HandRank.none => '',
      HandRank.mangan => 'Mangan',
      HandRank.haneman => 'Haneman',
      HandRank.baiman => 'Baiman',
      HandRank.sanbaiman => 'Sanbaiman',
      HandRank.kazoeYakuman => 'Counted yakuman',
      HandRank.yakuman => 'Yakuman',
      HandRank.doubleYakuman => 'Double yakuman',
      HandRank.tripleYakuman => 'Triple yakuman',
      HandRank.quadrupleYakuman => 'Quadruple yakuman',
      HandRank.quintupleYakuman => 'Quintuple yakuman',
      HandRank.sextupleYakuman => 'Sextuple yakuman',
    };
  }

  String hanFu(int han, int fu) => tr('$han翻$fu符', '$han han $fu fu');
  String han(int han) => tr('$han翻', '$han han');
  String fu(int fu) => tr('$fu符', '$fu fu');

  /// 段階名（満貫以上）か「N翻M符」。役満は符を書かない。
  String headline(WinResult r) {
    if (r.rank.isLimit) return rankName(r.rank);
    return hanFu(r.han, r.fu);
  }

  /// 翻・符の補足（「5翻30符」「13翻」。役満・国士は空）。
  String hanFuDetail(WinResult r) {
    if (r.isYakuman) return '';
    if (r.fu <= 0) return han(r.han);
    return hanFu(r.han, r.fu);
  }

  String points(int value) =>
      tr('${formatPoints(value)}点', '${formatPoints(value)} pts');

  /// 支払いの表記（子ロン「8,000」、子ツモ「2,000・4,000」、親ツモ「4,000オール」）。本場込み。
  String paymentText(WinPayment p) {
    if (p.winType == WinType.ron) return formatPoints(p.ron);
    if (p.dealer) {
      return tr(
        '${formatPoints(p.tsumoFromChild)}オール',
        '${formatPoints(p.tsumoFromChild)} all',
      );
    }
    return '${formatPoints(p.tsumoFromChild)}・${formatPoints(p.tsumoFromDealer)}';
  }

  /// 支払いの説明（誰がいくら払うか）。
  String paymentDetail(WinPayment p) {
    if (p.winType == WinType.ron) {
      return tr(
        '放銃した人が ${formatPoints(p.ron)}点',
        'The discarder pays ${formatPoints(p.ron)}',
      );
    }
    if (p.dealer) {
      return tr(
        '子 3 人が ${formatPoints(p.tsumoFromChild)}点ずつ',
        'Each of 3 players pays ${formatPoints(p.tsumoFromChild)}',
      );
    }
    return tr(
      '子 ${formatPoints(p.tsumoFromChild)}点・親 ${formatPoints(p.tsumoFromDealer)}点',
      'Non-dealers ${formatPoints(p.tsumoFromChild)}, dealer ${formatPoints(p.tsumoFromDealer)}',
    );
  }

  /// 本場・供託があるときの内訳（なければ null）。
  String? breakdown(WinPayment p) {
    if (p.honbaPoints == 0 && p.kyotakuPoints == 0) return null;
    final parts = [
      tr(
        '素点 ${formatPoints(p.baseTotal)}',
        'Base ${formatPoints(p.baseTotal)}',
      ),
      if (p.honbaPoints > 0)
        tr(
          '本場 ${formatPoints(p.honbaPoints)}',
          'Honba ${formatPoints(p.honbaPoints)}',
        ),
      if (p.kyotakuPoints > 0)
        tr(
          '供託 ${formatPoints(p.kyotakuPoints)}',
          'Deposits ${formatPoints(p.kyotakuPoints)}',
        ),
    ];
    return '${parts.join(' ＋ ')} ＝ ${points(p.total)}';
  }

  String get dealerRon => tr('親のロン', 'Dealer ron');
  String get childRon => tr('子のロン', 'Non-dealer ron');
  String get dealerTsumo => tr('親のツモ', 'Dealer tsumo');
  String get childTsumo => tr('子のツモ', 'Non-dealer tsumo');
  String who(bool dealer, WinType type) => type == WinType.ron
      ? (dealer ? dealerRon : childRon)
      : (dealer ? dealerTsumo : childTsumo);

  String waitName(WaitType wait) => switch (wait) {
    WaitType.ryanmen => tr('両面待ち', 'Open wait'),
    WaitType.shanpon => tr('シャンポン待ち', 'Double-pair wait'),
    WaitType.kanchan => tr('嵌張待ち', 'Closed wait'),
    WaitType.penchan => tr('辺張待ち', 'Edge wait'),
    WaitType.tanki => tr('単騎待ち', 'Single wait'),
  };

  String closedName(bool closed) =>
      closed ? tr('門前', 'Closed') : tr('副露', 'Open');

  /// 待ちの取り方で点数が変わるとき（高点法で高い方を採った）。
  String alternativeNote({
    required WaitType bestWait,
    required WaitType altWait,
    required int altTotal,
  }) => tr(
    '待ちの取り方で点数が変わる手です。高い方の${waitName(bestWait)}で計算しています（${waitName(altWait)}なら ${formatPoints(altTotal)}点）。',
    'The score depends on how the wait is read. Counted as the higher ${waitName(bestWait).toLowerCase()} '
        '(${formatPoints(altTotal)} pts as a ${waitName(altWait).toLowerCase()}).',
  );

  /// 役の表示名（画面・カード・本文で同じ）。日本語は正式名（門前清自摸和だけ「門前ツモ」）。
  String yakuName(YakuId id) {
    if (isEnglish) return ReasonText(lang).yaku(id);
    return switch (id) {
      YakuId.menzenTsumo => '門前ツモ',
      YakuId.kokushi13 => '国士無双十三面',
      _ => id.jaName,
    };
  }

  /// 役 1 つの翻（「1翻」「役満」「ダブル役満」）。
  String yakuValue(ScoredYaku y) {
    if (!y.isYakuman) return han(y.han);
    return switch (y.yakumanMultiplier) {
      1 => tr('役満', 'Yakuman'),
      2 => tr('ダブル役満', 'Double yakuman'),
      final n => tr('$n倍役満', '${n}x yakuman'),
    };
  }

  String get dora => tr('ドラ', 'Dora');
  String get akaDora => tr('赤ドラ', 'Red fives');
  String get uraDora => tr('裏ドラ', 'Ura dora');
  String doraCount(int n) => tr('$n', '$n');
  String get total => tr('合計', 'Total');
  String suppressed(String names) =>
      tr('役満のため数えない役: $names', 'Not counted with a yakuman: $names');
  String doraNotCounted(int n) =>
      tr('ドラ $n（役満には足しません）', 'Dora $n (not added to a yakuman)');

  // --- 符の内訳 -------------------------------------------------------------
  String fuHeader(int fu) => tr('符の内訳（$fu符）', 'Fu breakdown ($fu fu)');
  String get fuChiitoitsu =>
      tr('七対子は 25 符で固定です', 'Seven pairs is always 25 fu');

  String fuReason(FuPart part) {
    final tile = part.tile;
    final terminal = tile != null && _isTerminalOrHonor(tile);
    final kind = terminal ? tr('么九牌', 'terminal/honor') : tr('中張牌', 'simple');
    final name = tile == null ? '' : tileDisplayName(tile, english: isEnglish);
    return switch (part.reason) {
      FuReason.base => tr('副底', 'Base'),
      FuReason.menzenRon => tr('門前ロン', 'Closed ron'),
      FuReason.tsumo => tr('ツモ', 'Tsumo'),
      FuReason.chiitoitsu => tr('七対子', 'Seven pairs'),
      FuReason.openPinfu => tr('副露の平和形（30符にする）', 'Open pinfu shape (to 30 fu)'),
      FuReason.kanchan => tr('嵌張待ち', 'Closed wait'),
      FuReason.penchan => tr('辺張待ち', 'Edge wait'),
      FuReason.tanki => tr('単騎待ち', 'Single wait'),
      FuReason.pairDragon => tr('雀頭（三元牌 $name）', 'Pair of dragons ($name)'),
      FuReason.pairSeatWind => tr('雀頭（自風 $name）', 'Pair of seat wind ($name)'),
      FuReason.pairRoundWind => tr(
        '雀頭（場風 $name）',
        'Pair of round wind ($name)',
      ),
      FuReason.pairDoubleWind => tr(
        '雀頭（連風牌 $name）',
        'Pair of double wind ($name)',
      ),
      FuReason.minko => tr('明刻（$kind $name）', 'Open triplet ($kind, $name)'),
      FuReason.anko => tr('暗刻（$kind $name）', 'Closed triplet ($kind, $name)'),
      FuReason.minkan => tr('明槓（$kind $name）', 'Open kan ($kind, $name)'),
      FuReason.ankan => tr('暗槓（$kind $name）', 'Closed kan ($kind, $name)'),
      FuReason.roundUp => tr('10符単位に切り上げ', 'Round up to 10'),
    };
  }

  static bool _isTerminalOrHonor(String tile) {
    if (tile.length < 2) return false;
    if (tile[1] == 'z') return true;
    return tile[0] == '1' || tile[0] == '9';
  }

  // --- 条件 -----------------------------------------------------------------
  String get tsumo => tr('ツモ', 'Tsumo');
  String get ron => tr('ロン', 'Ron');
  String get riichiLabel => tr('リーチ', 'Riichi');
  String get riichiNone => tr('なし', 'None');
  String get riichi => tr('リーチ', 'Riichi');
  String get doubleRiichi => tr('ダブル', 'Double');
  String get ippatsu => tr('一発', 'Ippatsu');
  String get openHandNoRiichi =>
      tr('副露しているのでリーチはかけられません', 'You cannot riichi with an open hand');
  String get roundWind => tr('場風', 'Round');
  String get seatWind => tr('自風', 'Seat');
  String get dealerTag => tr('親', 'Dealer');
  String seatChoice(Wind w) =>
      w == Wind.east ? tr('東（親）', 'E (dlr)') : _common.windName(w);
  String windShort(Wind w) =>
      isEnglish ? const ['E', 'S', 'W', 'N'][w.index] : _common.windName(w);
  String get doraIndicators => tr('ドラ表示牌', 'Dora indicators');
  String get uraIndicators => tr('裏ドラ表示牌', 'Ura dora indicators');
  String get addIndicator => tr('追加', 'Add');
  String get noIndicators => tr('なし', 'None');
  String get pickDoraTitle =>
      tr('ドラ表示牌（タップで追加）', 'Dora indicators (tap to add)');
  String get pickUraTitle =>
      tr('裏ドラ表示牌（タップで追加）', 'Ura dora indicators (tap to add)');
  String get pickIndicatorHint =>
      tr('表示牌を選んでください（最大5枚）', 'Pick indicators (up to 5)');
  String get removeIndicator => tr('タップで外す', 'Tap to remove');
  String get luckyYaku => tr('偶然役', 'Lucky yaku');
  String get honba => tr('本場', 'Honba');
  String get kyotaku => tr('供託（リーチ棒）', 'Deposits (riichi sticks)');
  String honbaValue(int n) => tr('$n本場', '$n');
  String kyotakuValue(int n) => tr('$n本', '$n');
  String get decrease => tr('減らす', 'Decrease');
  String get increase => tr('増やす', 'Increase');

  String situationName(YakuId id) => yakuName(id);

  // --- エラー ---------------------------------------------------------------
  String errorTitle(WinError e) => switch (e) {
    WinError.noYaku => tr('役がありません', 'No yaku'),
    WinError.notWinningHand ||
    WinError.wrongTileCount => tr('和了形ではありません', 'Not a winning hand'),
    _ => tr('計算できません', 'Cannot score this hand'),
  };

  /// 何を直せばよいか。
  String errorMessage(WinError e) => switch (e) {
    WinError.invalidTile => tr(
      '読めない牌があります。手牌を直してください。',
      'Some tiles cannot be read. Please fix the tiles.',
    ),
    WinError.invalidMeld => tr(
      '副露の形が正しくありません（チーは続いた3枚、ポンは同じ3枚、カンは同じ4枚）。',
      'A call is not valid (chi: 3 in a row, pon: 3 of a kind, kan: 4 of a kind).',
    ),
    WinError.wrongTileCount => tr(
      '和了の形は副露を含めて14枚です（カンは3枚と数えます）。和了牌を足すか、手牌を直してください。',
      'A winning hand has 14 tiles including calls (a kan counts as 3). Add the winning tile or fix the tiles.',
    ),
    WinError.tooManyCopies => tr(
      '同じ牌が5枚以上あります（ドラ表示牌も数えます）。',
      'There are 5 or more of the same tile (indicators included).',
    ),
    WinError.tooManyRedFives => tr(
      '赤5が多すぎます（萬・筒・索に1枚ずつです）。',
      'Too many red fives (one each of man, pin and sou).',
    ),
    WinError.tooManyIndicators => tr(
      'ドラ表示牌・裏ドラ表示牌はそれぞれ5枚までです。',
      'Up to 5 dora and 5 ura dora indicators.',
    ),
    WinError.winningTileNotInHand => tr(
      '和了牌が手牌にありません。和了牌を選び直してください。',
      'The winning tile is not in the hand. Choose it again.',
    ),
    WinError.unsupportedMode => tr(
      '三人麻雀の点数計算には対応していません。',
      'Three-player scoring is not supported.',
    ),
    WinError.riichiWithOpenHand => tr(
      'リーチは門前のときだけです（暗槓は門前のままです）。',
      'Riichi needs a closed hand (a closed kan keeps it closed).',
    ),
    WinError.ippatsuWithoutRiichi => tr(
      '一発はリーチしたときだけです。',
      'Ippatsu needs riichi.',
    ),
    WinError.chankanWithTsumo => tr('槍槓はロンのときだけです。', 'Robbing a kan is a ron.'),
    WinError.rinshanWithoutTsumo => tr(
      '嶺上開花はツモのときだけです。',
      'After a kan is a tsumo.',
    ),
    WinError.haiteiWithoutTsumo => tr(
      '海底摸月はツモのときだけです。',
      'Last tile draw is a tsumo.',
    ),
    WinError.houteiWithTsumo => tr(
      '河底撈魚はロンのときだけです。',
      'Last tile discard is a ron.',
    ),
    WinError.haiteiWithRinshan => tr(
      '海底摸月と嶺上開花は同時に付きません。',
      'Last tile draw and after a kan cannot both apply.',
    ),
    WinError.houteiWithChankan => tr(
      '河底撈魚と槍槓は同時に付きません。',
      'Last tile discard and robbing a kan cannot both apply.',
    ),
    WinError.tenhouNotDealer => tr(
      '天和は親だけです。',
      'Blessing of heaven is for the dealer.',
    ),
    WinError.tenhouWithoutTsumo => tr(
      '天和はツモだけです。',
      'Blessing of heaven is a tsumo.',
    ),
    WinError.tenhouWithMeld => tr(
      '天和は副露（暗槓を含む）があると付きません。',
      'Blessing of heaven cannot have calls (closed kans included).',
    ),
    WinError.chiihouAsDealer => tr(
      '地和は子だけです。',
      'Blessing of earth is for non-dealers.',
    ),
    WinError.chiihouWithoutTsumo => tr(
      '地和はツモだけです。',
      'Blessing of earth is a tsumo.',
    ),
    WinError.chiihouWithMeld => tr(
      '地和は副露（暗槓を含む）があると付きません。',
      'Blessing of earth cannot have calls (closed kans included).',
    ),
    WinError.renhouAsDealer => tr(
      '人和は子だけです。',
      'Blessing of man is for non-dealers.',
    ),
    WinError.renhouWithTsumo => tr('人和はロンだけです。', 'Blessing of man is a ron.'),
    WinError.renhouWithMeld => tr(
      '人和は副露があると付きません。',
      'Blessing of man cannot have calls.',
    ),
    WinError.rinshanWithoutKan => tr(
      '嶺上開花はカンしたときだけです。副露にカンを入れてください。',
      'After a kan needs a kan. Add the kan to the calls.',
    ),
    WinError.chankanImpossible => tr(
      '和了牌と同じ牌が他にもあるので、槍槓にはなりません。',
      'Robbing a kan is impossible: the winning tile appears elsewhere in the hand.',
    ),
    WinError.ippatsuWithRinshan => tr(
      '一発と嶺上開花は同時に付きません（カンで一発は消えます）。',
      'Ippatsu and after a kan cannot both apply (a kan cancels ippatsu).',
    ),
    WinError.blessingWithOtherSituation => tr(
      '天和・地和には、リーチや他の偶然役は付きません。',
      'Blessings cannot be combined with riichi or other lucky yaku.',
    ),
    WinError.notWinningHand => tr(
      '14枚が和了の形（4面子1雀頭・七対子・国士無双）になっていません。手牌を確かめてください。',
      'The 14 tiles do not form a winning hand (4 sets and a pair, seven pairs or thirteen orphans). Please check the tiles.',
    ),
    WinError.noYaku => tr(
      '役がありません（ドラだけでは和了れません）。リーチ・ツモなどの条件を確かめてください。',
      'There is no yaku (dora alone cannot win). Check riichi, tsumo and the other conditions.',
    ),
  };

  // --- 入口・ロック -----------------------------------------------------------
  String get entryTitle => tr('役と点数を詳しく見る', 'See yaku & points in detail');
  String get entrySubtitle =>
      tr('ロン・リーチ・ドラ・本場まで入れて点数を計算', 'Ron, riichi, dora and honba included');
  String get lockedTitle =>
      tr('役と点数の計算は Pro の機能です', 'Yaku & points is a Pro feature');
  String get lockedBody => tr(
    '和了の手を撮るだけで、役・翻・符・点数・支払いを計算して、画像で共有できます。',
    'Snap a winning hand to get yaku, han, fu, points and payments, and share them as an image.',
  );
  String get goPro => tr('Pro を見る', 'See Pro');

  // --- 共有カード・本文 -------------------------------------------------------
  String get quizHeadline => tr('この手、何点？', 'How many points?');
  String get quizSubline =>
      tr('役・翻・符も考えてみよう', 'Work out the yaku, han and fu too');
  String get quizHidden => tr('？？？？点', '???? pts');
  String get uraLabel => tr('裏ドラ', 'Ura');

  /// カードのフッタの誘導文（通常・点数クイズ）。
  String get storeLead => tr('点数計算はアプリで', 'Score your hands in the app');
  String get quizStoreLead => tr('答えはアプリで', 'Get the answer in the app');

  /// 条件の 1 行（「子・ツモ・東場南家・リーチ・1本場」）。ドラの枚数は書かない。
  String conditionLine(WinRequest r) {
    final parts = <String>[
      r.isDealer ? _common.dealer : _common.nonDealer,
      r.isTsumo ? tsumo : ron,
      isEnglish
          ? '${_common.windName(r.roundWind)} round, ${_common.windName(r.seatWind)} seat'
          : '${_common.windName(r.roundWind)}場${_common.windName(r.seatWind)}家',
      if (r.doubleRiichi)
        yakuName(YakuId.doubleRiichi)
      else if (r.riichi)
        yakuName(YakuId.riichi),
      if (r.ippatsu) yakuName(YakuId.ippatsu),
      if (r.haitei) yakuName(YakuId.haitei),
      if (r.houtei) yakuName(YakuId.houtei),
      if (r.rinshan) yakuName(YakuId.rinshan),
      if (r.chankan) yakuName(YakuId.chankan),
      if (r.tenhou) yakuName(YakuId.tenhou),
      if (r.chiihou) yakuName(YakuId.chiihou),
      if (r.honba > 0) tr('${r.honba}本場', '${r.honba} honba'),
      if (r.kyotaku > 0)
        tr('供託${r.kyotaku}', '${r.kyotaku} deposit${r.kyotaku > 1 ? 's' : ''}'),
    ];
    return parts.join(isEnglish ? ' · ' : '・');
  }

  /// 役の並び（「立直・門前ツモ・断么九・ドラ1」）。役満は役満の役だけ。
  String yakuSummary(WinResult r) {
    final parts = [
      for (final y in orderedYaku(r.yaku)) yakuName(y.id),
      if (!r.isYakuman) ...[
        if (r.doraCount > 0) _withCount(dora, r.doraCount),
        if (r.akaDoraCount > 0) _withCount(akaDora, r.akaDoraCount),
        if (r.uraDoraCount > 0) _withCount(uraDora, r.uraDoraCount),
      ],
    ];
    return parts.join(isEnglish ? ', ' : '・');
  }

  String _withCount(String name, int n) => isEnglish ? '$name $n' : '$name$n';

  /// 共有の本文（「【満貫 8,000点】立直・門前ツモ・断么九・ドラ1 #なにきるカム」）。
  String shareText(WinResult r, {required String url}) {
    final head = '${headline(r)} ${points(r.payment.total)}';
    final yaku = yakuSummary(r);
    return isEnglish
        ? '[$head] $yaku #mahjong #NanikiruCam\n$url'
        : '【$head】$yaku #なにきるカム\n$url';
  }

  /// 点数クイズの本文。答え（点数・役）は書かない。
  String quizShareText(WinRequest r, {required String url}) => isEnglish
      ? '[Score quiz] How many points is this hand? (${conditionLine(r)}) #mahjong #NanikiruCam\n$url'
      : '【点数クイズ】この手、何点？（${conditionLine(r)}）#麻雀点数クイズ #なにきるカム\n$url';
}

extension WinStringsContext on BuildContext {
  WinStrings get winStrings => WinStrings(lang);
}

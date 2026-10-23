import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// ライブナビ（live/）の文言。
class LiveStrings extends FeatureStrings {
  const LiveStrings(super.lang);

  String get title => tr('ライブナビ', 'Live Navi');
  String get summaryTitle => tr('対局サマリー', 'Session summary');

  // --- 状態バッジ（仕様 6.3） ---
  String get stateSearching => tr('探索中', 'Searching');
  String get stateStable => tr('確定', 'Locked');
  String get stateMoving => tr('手が動いています', 'Hand moving');
  String get stateDark => tr('暗い', 'Too dark');
  String get stateFar => tr('遠い', 'Too far');
  String stateCount(int n) => tr('枚数 $n', _en(n, 'tile'));
  String get statePaused => tr('一時停止中', 'Paused');

  // --- 案内の代わりに出すヒント ---
  String get hintSearching =>
      tr('手牌にカメラを向けてください', 'Point the camera at your hand');
  String get hintConfirming => tr('並びを確かめています…', 'Checking the tiles…');
  String get hintMoving => tr('手を止めると案内します', 'Hold still to get advice');
  String get hintDark => tr('暗いので明るくしてください', 'It is too dark. Add some light');
  String get hintFar => tr(
    '近づけてください（手牌が横幅の 7 割ほどに）',
    'Move closer (the hand should fill about 70% of the width)',
  );
  String hintCount(int n) => tr(
    '枚数が合いません（$n枚）。13 枚か 14 枚を横一列に',
    'Tile count does not match ($n). Line up 13 or 14 tiles',
  );
  String get hintLowConfidence =>
      tr('牌を見やすくしてください', 'Make the tiles easier to see');
  String get hintImpossible => tr(
    '牌を読み取れませんでした。牌を見やすくしてください',
    'Could not read the tiles. Make them easier to see',
  );
  String get hintMeld => tr(
    '鳴いた手はライブでは未対応です。写真で解析してください',
    'Called melds are not supported in Live yet. Use a photo instead',
  );
  String get analyzing => tr('解析中…', 'Analyzing…');
  String get roiGuide =>
      tr('手牌をこの枠に横一列で', 'Line up your hand inside this frame');

  // --- 準備・失敗 ---
  String get preparing => tr('認識の準備中…', 'Preparing recognition…');
  String get modelFailed =>
      tr('認識モデルを読み込めませんでした。', 'Could not load the recognition model.');

  // --- 戦略軸 ---
  String axisName(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('速さ', 'Speed'),
    StrategyAxis.points => tr('打点', 'Points'),
    StrategyAxis.balance => tr('バランス', 'Balance'),
  };

  /// 3 軸の解が割れたときのバッジ（仕様 4.1）。
  String axisBadge(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('最速', 'Fastest'),
    StrategyAxis.points => tr('高打点', 'Most points'),
    StrategyAxis.balance => tr('バランス', 'Balanced'),
  };
  String get unanimous => tr('一択', 'Clear choice');

  // --- 14 枚 ---
  String discard(String tileName, {bool unsure = false}) => tr(
    '${tileName + (unsure ? '（？）' : '')}を切る',
    'Discard $tileName${unsure ? ' (?)' : ''}',
  );
  String ukeire(int kinds, int total) => tr(
    '受け入れ $kinds種$total枚',
    '${_en(kinds, 'kind')} / ${_en(total, 'tile')}',
  );
  String alternative(StrategyAxis axis, String tileName) =>
      '${axisName(axis)}: $tileName';
  String confidence(YakuConfidence c) => switch (c) {
    YakuConfidence.certain => tr('確定', 'certain'),
    YakuConfidence.likely => tr('濃厚', 'likely'),
    YakuConfidence.possible => tr('狙える', 'possible'),
    YakuConfidence.lost => tr('消える', 'lost'),
  };
  String prospect(String yakuName, YakuConfidence c) =>
      tr('$yakuName（${confidence(c)}）', '$yakuName (${confidence(c)})');
  String get noProspect => tr('役の見込みなし', 'No yaku in sight');
  String pointRange(int min, int max) => min == max
      ? tr('${_n(min)}点', '${_n(min)} pts')
      : tr('${_n(min)}〜${_n(max)}点', '${_n(min)}–${_n(max)} pts');
  String winEase(double v) {
    final level = v >= 0.5
        ? tr('高', 'high')
        : v >= 0.25
        ? tr('中', 'mid')
        : tr('低', 'low');
    return tr('上がりやすさ $level', 'Win chance $level');
  }

  String get openDetail => tr('くわしく', 'Details');

  // --- 13 枚 ---
  String waits(String tiles) => tr('待ち: $tiles', 'Waits: $tiles');
  String remaining(int n) => tr('残り$n枚', '$n left');
  String get riichiPossible => tr('リーチできます', 'You can riichi');
  String get noYaku =>
      tr('役がありません。リーチかツモであがれます', 'No yaku. Win with riichi or a self-draw');
  String get tapWaitHint =>
      tr('待ち牌をタップでロン時の点数', 'Tap a wait to see the ron score');
  String get ronPossible => tr('ロンできます', 'You can ron');
  String get ronImpossible =>
      tr('ロンできません（役がありません）', 'You cannot ron (no yaku)');
  String ronWith(String tileName) =>
      tr('$tileNameが出たら', 'If $tileName is discarded');
  String get tsumoLabel => tr('ツモ', 'Tsumo');
  String get ronLabel => tr('ロン', 'Ron');
  String get riichiLabel => tr('リーチ込み', 'with riichi');
  String get recordRon => tr('この牌でロンした（記録）', 'I won by ron (record)');
  String get ronRecorded => tr('和了を記録しました', 'Win recorded');

  // --- 和了 ---
  String get tsumoWin => tr('ツモ！', 'Tsumo!');
  String hanFu(int han, int fu) => tr('$han翻 $fu符', '$han han $fu fu');
  String points(int p) => tr('${_n(p)}点', '${_n(p)} pts');
  String get nextHand => tr('次の局へ', 'Next hand');
  String rankName(String rank) => switch (rank) {
    'mangan' => tr('満貫', 'Mangan'),
    'haneman' => tr('跳満', 'Haneman'),
    'baiman' => tr('倍満', 'Baiman'),
    'sanbaiman' => tr('三倍満', 'Sanbaiman'),
    'yakuman' => tr('役満', 'Yakuman'),
    _ => '',
  };

  // --- 上部のボタン・警告 ---
  String trialRemaining(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return tr('体験 残り$m:$s', 'Trial $m:$s left');
  }

  // --- 体験時間の延長（動画広告。Paywall と Home で見せる。ライブ中は出さない） ---
  String get extendButton =>
      tr('動画を見てライブを延長（+1〜3分）', 'Watch a video to extend Live (+1-3 min)');
  String extendHint(int leftToday) => tr(
    '広告が長いほど長く延長されます（今日はあと$leftToday回）',
    'Longer ads extend Live for longer ($leftToday left today)',
  );
  String get extendLoading => tr('広告を読み込み中', 'Loading an ad…');
  String get extendLimit =>
      tr('今日の延長は上限です', 'Today\'s extension limit is reached');
  String extended(int seconds) {
    final minutes = seconds ~/ 60;
    return tr('ライブが+$minutes分延長されました', 'Live extended by $minutes min');
  }

  String get extendFailed =>
      tr('動画を最後まで見ると延長されます', 'Watch the video to the end to extend Live');

  String get pause => tr('一時停止', 'Pause');
  String get resume => tr('再開', 'Resume');
  String get end => tr('終了', 'End');
  String get light => tr('ライト', 'Light');
  String get help => tr('置き方', 'How to set up');
  String get handSettings => tr('局の設定', 'Round settings');
  String get more => tr('その他の操作', 'More');
  String batteryLow(int level) =>
      tr('電池残量が少なくなっています（$level%）', 'Battery is low ($level%)');
  String get thermalWarning => tr(
    '端末が熱くなっています。更新を 1 秒に 1 回に落としています',
    'The device is hot. Updates are slowed to once per second',
  );

  // --- 局の設定 ---
  String get roundWind => tr('場風', 'Round wind');
  String get seatWind => tr('自風', 'Seat wind');
  String get doraIndicators => tr('ドラ表示牌', 'Dora indicators');
  String get addDora => tr('追加', 'Add');
  String get noDora => tr('なし', 'None');
  String get handSettingsNote =>
      tr('役牌・ドラ・親子の点数に使います', 'Used for value honors, dora and dealer scoring');

  // --- 置き方の案内（仕様 3.1.2） ---
  String get guideTitle => tr('ライブナビの置き方', 'Setting up Live Navi');
  List<String> get guideSteps => [
    tr(
      'スタンドで卓の縁に立て、手牌を 30〜45° の斜め上から写します',
      'Use a stand at the table edge and view your hand from 30–45° above',
    ),
    tr(
      '手牌全体が横幅の 7 割以上になる距離（約 30〜40cm）',
      'Keep the whole hand at 70%+ of the width (about 30–40 cm)',
    ),
    tr('縦向きで使います。暗いときはライトを', 'Use portrait. Turn on the light if dark'),
    tr(
      '並びが 1 秒以上変わらないときだけ案内します',
      'Advice appears only after the tiles stay still for a second',
    ),
    tr(
      '手に持って使うこともできますが、案内が安定しにくくなります',
      'Handheld use works but advice is less stable',
    ),
  ];
  String get guideConsent => tr(
    '同卓者の了解を得てから使ってください。画面は自分だけに見える角度に。映像は保存も送信もしません。',
    'Get the other players\' consent first. Keep the screen visible only to you. Video is never saved or sent.',
  );
  String get guideStart => tr('了解して始める', 'Agree and start');

  // --- サマリー（仕様 6.4） ---
  String duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m == 0 ? tr('$s秒', '${s}s') : tr('$m分$s秒', '${m}m ${s}s');
  }

  String get usedTime => tr('利用時間', 'Time');
  String get adviceCount => tr('案内した回数', 'Advice shown');
  String get followRate => tr('採用率', 'Followed');
  String get noFollowData => tr('—', '—');
  String get winsLabel => tr('和了', 'Wins');
  String winCount(int n) => tr('$n回', '$n');
  String get bestPoints => tr('最高打点', 'Best hand');
  String get noWins => tr('和了はありませんでした', 'No wins this time');
  String get share => tr('共有', 'Share');
  String get shareSummary => tr('今日の成果を共有', 'Share today\'s results');
  String get close => tr('閉じる', 'Close');
  String get todayTotal => tr('今日の合計', 'Today');
  String todaySummary(int sessions, int wins) => tr(
    '$sessions回・和了$wins回',
    '${_en(sessions, 'session')}, ${_en(wins, 'win')}',
  );
  String get proHistoryNote =>
      tr('推移の保存は Pro の機能です', 'Saving your progress is a Pro feature');
  String allTimeSummary(int sessions, int wins, int best) => tr(
    'これまで $sessions回・和了$wins回・最高${_n(best)}点',
    'All time: ${_en(sessions, 'session')}, ${_en(wins, 'win')}, '
        'best ${_n(best)} pts',
  );
  String get milestoneFirstWin => tr('初めての和了！', 'Your first win!');
  String get milestoneFirstMangan => tr('初めての満貫！', 'Your first mangan!');
  String get milestoneBest => tr('最高打点を更新！', 'New personal best!');
  String endedBy(String reason) => switch (reason) {
    'trial_limit' => tr('今日の体験時間が終わりました', 'Today\'s trial time is over'),
    'battery' => tr('電池残量が少ないため終了しました', 'Ended because the battery is low'),
    'thermal' => tr('端末が熱くなったため終了しました', 'Ended because the device is hot'),
    _ => '',
  };

  /// 役の名前（エンジンは日本語名。英語は主な役だけ訳す）。
  String yakuName(String jaName) {
    if (!isEnglish) return jaName;
    final match = RegExp(r'^(ドラ|赤ドラ|裏ドラ)(\d+)$').firstMatch(jaName);
    if (match != null) {
      return '${_yakuEn[match.group(1)] ?? match.group(1)} ${match.group(2)}';
    }
    return _yakuEn[jaName] ?? jaName;
  }

  String yakuOf(YakuId id) => yakuName(id.jaName);

  /// 英語の数と名詞（1 は単数、それ以外は複数）。日本語では使わない。
  static String _en(int n, String singular, [String? plural]) =>
      '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

  static String _n(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static const Map<String, String> _yakuEn = {
    '国士無双': 'Thirteen Orphans',
    '国士無双十三面待ち': 'Thirteen Orphans (13-wait)',
    '四暗刻': 'Four Concealed Triplets',
    '四暗刻単騎': 'Four Concealed Triplets (single wait)',
    '大三元': 'Big Three Dragons',
    '小四喜': 'Little Four Winds',
    '大四喜': 'Big Four Winds',
    '字一色': 'All Honors',
    '緑一色': 'All Green',
    '清老頭': 'All Terminals',
    '九蓮宝燈': 'Nine Gates',
    '純正九蓮宝燈': 'True Nine Gates',
    '四槓子': 'Four Kans',
    '清一色': 'Full Flush',
    '混一色': 'Half Flush',
    '純全帯么九': 'Junchan',
    '二盃口': 'Twice Pure Double Sequence',
    '混全帯么九': 'Chanta',
    '三色同順': 'Mixed Triple Sequence',
    '一気通貫': 'Pure Straight',
    '対々和': 'All Triplets',
    '三暗刻': 'Three Concealed Triplets',
    '小三元': 'Little Three Dragons',
    '三色同刻': 'Triple Triplets',
    '三槓子': 'Three Kans',
    '混老頭': 'All Terminals and Honors',
    '七対子': 'Seven Pairs',
    '連風牌': 'Double Wind',
    '役牌 白': 'White Dragon',
    '役牌 發': 'Green Dragon',
    '役牌 中': 'Red Dragon',
    '役牌 自風': 'Seat Wind',
    '役牌 場風': 'Round Wind',
    '断么九': 'All Simples',
    '平和': 'Pinfu',
    '一盃口': 'Pure Double Sequence',
    '立直': 'Riichi',
    'ダブル立直': 'Double Riichi',
    '一発': 'Ippatsu',
    '門前清自摸和': 'Menzen Tsumo',
    'ドラ': 'Dora',
    '赤ドラ': 'Red Five',
    '裏ドラ': 'Ura Dora',
  };
}

extension LiveStringsContext on BuildContext {
  LiveStrings get liveStrings => LiveStrings(lang);
}

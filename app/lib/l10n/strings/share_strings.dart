import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';

/// 共有カード・問題の公開（share/）の文言。
class ShareStrings extends FeatureStrings {
  const ShareStrings(super.lang);

  CommonStrings get _common => CommonStrings(lang);

  String get appName => _common.appName;

  // --- 画面（共有カード） ---------------------------------------------------
  String get cardTitle => tr('共有カード', 'Share card');
  String get formatSquare => tr('正方形 1:1', 'Square 1:1');
  String get formatStory => tr('ストーリー 9:16', 'Story 9:16');
  String get sizeLabel => tr('サイズ', 'Size');
  String get shareButton => tr('シェアする', 'Share');
  String get saveButton => tr('画像を保存', 'Save image');
  String get savedToPhotos => tr('写真に保存しました', 'Saved to Photos');
  String get saveDenied => tr(
    '写真への保存が許可されていません。設定から許可してください',
    'Saving to Photos is not allowed. Please allow it in Settings.',
  );
  String get saveFailed => tr('保存できませんでした', 'Could not save the image');
  String get shareFailed => tr('共有できませんでした', 'Could not share');
  String get preparing => tr('カードを作っています', 'Preparing the card');
  String get cardUnavailable =>
      tr('このカードに必要なデータがありません', 'This card has no data to show');
  String get publishAndShare => tr('問題を公開して共有', 'Publish and share');
  String get cardPrivacyNote => tr(
    '写真は載りません。牌・ドラ・風・巡目・ニックネームだけが載ります。',
    'No photos are included. Only tiles, dora, winds, turn and nickname.',
  );

  // --- 画面（公開） ---------------------------------------------------------
  String get publishTitle => tr('問題を公開', 'Publish a problem');

  /// オンライン機能が無い版（公開しない）の画面タイトル。
  String get shareProblemCardTitle =>
      tr('問題カードを共有', 'Share a problem card');
  String get nicknameLabel => tr('出題者名（ニックネーム）', 'Name shown on the card');
  String get nicknameHint => tr('空欄なら匿名', 'Leave empty to stay anonymous');
  String get publicToggle => tr('問題として公開する', 'Publish as a problem');
  String get publicToggleHelp => tr(
    'Web で誰でも回答できます（インストール不要）。公開するのは牌・ドラ・風・巡目・ニックネームだけです。',
    'Anyone can answer on the web without installing. Only tiles, dora, winds, turn and nickname are published.',
  );
  String get publishAndShareButton => tr('公開して共有', 'Publish and share');
  String get shareOnlyButton => tr('公開せずに共有', 'Share without publishing');
  String get phaseAnalyzing => tr('正解を計算しています', 'Working out the answer');
  String get phasePublishing => tr('問題を公開しています', 'Publishing the problem');
  String get phaseCard => tr('カードを作っています', 'Preparing the card');
  String get phaseSharing => tr('共有しています', 'Sharing');
  String get publishedNote => tr(
    '公開しました。回答が集まると通知でお知らせします。',
    'Published. You will be notified as answers come in.',
  );
  String get queuedNote => tr(
    'オフラインのため公開は後で自動的に行います。カードのQRはストアへ向かいます。',
    'You are offline, so publishing will run later. The card QR points to the store for now.',
  );
  String get unavailableNote => tr(
    'このビルドではオンライン機能が使えないため、カードだけ共有しました。',
    'Online features are off in this build, so only the card was shared.',
  );
  String get viewMyProblems => tr('出題した問題を見る', 'View my problems');
  String get needFourteen =>
      tr('14枚の手だけ出題できます', 'Only a 14-tile hand can be published as a problem');
  String get cannotAnalyze => tr(
    'この手は解析できないため、出題できません',
    'This hand cannot be analyzed, so it cannot be published',
  );

  /// 公開の拒否理由（`details.reason` / `code`）をメッセージにする。
  String publishError({required String code, String? reason}) {
    switch (reason) {
      case 'ng_word':
      case 'invalid_nickname':
        return tr(
          'この出題者名は使えません。別の名前にしてください',
          'This name cannot be used. Please choose another.',
        );
      case 'daily_limit':
        return tr(
          '1日に出題できる数の上限に達しました。明日また出題できます',
          'You reached the daily publishing limit. Try again tomorrow.',
        );
      case 'too_many_same_tile':
      case 'too_many_red':
      case 'invalid_tiles':
      case 'invalid_meld':
      case 'invalid_dora':
      case 'invalid_answer':
        return tr(
          'この手は出題できません。牌の組み合わせを確かめてください',
          'This hand cannot be published. Please check the tiles.',
        );
    }
    if (code == 'resource-exhausted') {
      return tr(
        '1日に出題できる数の上限に達しました',
        'You reached the daily publishing limit.',
      );
    }
    return tr('公開できませんでした', 'Could not publish');
  }

  // --- カードの文言 ---------------------------------------------------------
  String get problemHeadline => tr('この手、何切る？', 'What would you discard?');
  String get problemSubline => tr('あなたの答えは？', 'What is your answer?');
  String get scanToAnswer => tr('スキャンして答える', 'Scan to answer');
  String get scanToInstall => tr('スキャンしてアプリへ', 'Scan to get the app');
  String get seeExplanation => tr('解説はアプリで', 'Explanation in the app');
  String get storeGuide => tr(
    'App Store / Google Play で「なにきるカム」',
    'Search "Nanikiru Cam" on the App Store or Google Play',
  );
  String get watermark => appName;
  String author(String name) =>
      name.isEmpty ? tr('出題: 匿名', 'By anonymous') : tr('出題: $name', 'By $name');
  String answerCount(int n) => tr('$n人が回答', '$n answered');
  String get doraIndicator => tr('ドラ表示', 'Dora');

  /// 「東場 南家 6巡目」。
  String conditions(HandInput input) {
    final round = _common.windName(input.roundWind);
    final seat = _common.windName(input.seatWind);
    final turn = input.turn;
    if (isEnglish) {
      return '$round round · $seat seat${input.dealer ? ' (dealer)' : ''}'
          '${turn == null ? '' : ' · turn $turn'}';
    }
    return '$round場 $seat家${input.dealer ? '（親）' : ''}'
        '${turn == null ? '' : ' $turn巡目'}';
  }

  // 結果カード
  String get resultCorrect => tr('正解！', 'Correct!');
  String get resultWrong => tr('惜しい！', 'Close!');
  String get resultNoChoice => tr('この手の正解は', 'The answer for this hand');
  String get youLabel => tr('あなた', 'You');
  String get answerLabel => tr('正解', 'Answer');
  String ukeireVs(int mine, int best) =>
      tr('受け入れ $mine枚 vs $best枚', 'Ukeire $mine vs $best tiles');
  String ukeireOnly(int best) => tr('受け入れ $best枚', 'Ukeire $best tiles');
  String correctForAxis(StrategyAxis axis) => switch (axis) {
    StrategyAxis.speed => tr('速さ重視なら正解', 'Correct for speed'),
    StrategyAxis.points => tr('打点重視なら正解', 'Correct for points'),
    StrategyAxis.balance => tr('バランス重視なら正解', 'Correct for balance'),
  };
  String communityRate(int percent) =>
      tr('みんなの正解率 $percent%', 'Solved by $percent%');
  String streakDays(int n) => tr('連続 $n日', '$n-day streak');
  String get hardProblem => tr('難問に正解', 'Solved a hard one');

  // ライブ
  String get liveFirstWin => tr('ナビ付きで初和了！', 'First win with the navigator!');
  String get liveWin => tr('ナビで和了！', 'Won with the navigator!');
  String get liveManganWin => tr('ナビで満貫！', 'Mangan with the navigator!');
  String get liveSummaryHeadline => tr('今日の成果', 'Today at the table');
  String get liveNote => tr('友人戦・練習用', 'Friendly games and practice');
  String get livePlayedWithNavi => tr('ナビで打った', 'Played with the navigator');
  String hanFu(int han, int fu) => tr('$han翻$fu符', '$han han $fu fu');
  String points(int points) => tr('$points点', '$points pts');
  String liveDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (seconds < 60) return tr('$seconds秒', '$seconds sec');
    return tr('$minutes分', '$minutes min');
  }

  String liveAdvice(int n) => tr('ナビの案内 $n回', 'Navigator tips: $n');
  String liveFollowed(int followed, int advice) {
    final percent = advice <= 0 ? 0 : (followed * 100 / advice).round();
    return tr('採用 $followed回（$percent%）', 'Followed $followed ($percent%)');
  }

  String liveWins(int n) => tr('和了 $n回', 'Wins: $n');
  String liveBestWin(int points) => tr('最高 $points点', 'Best: $points pts');
  String winRank(int han, int fu) {
    if (han >= 13) return tr('役満', 'Yakuman');
    if (han >= 11) return tr('三倍満', 'Sanbaiman');
    if (han >= 8) return tr('倍満', 'Baiman');
    if (han >= 6) return tr('跳満', 'Haneman');
    if (han >= 5 || (han == 4 && fu >= 40) || (han == 3 && fu >= 70)) {
      return tr('満貫', 'Mangan');
    }
    return '';
  }

  // ストリーク・週間
  String get streakHeadline => tr('連続回答', 'Answer streak');
  String streakBig(int n) => tr('$n日', '$n');
  String get streakUnit => tr('連続', 'days in a row');
  String streakBest(int n) => tr('自己ベスト $n日', 'Best: $n days');
  String get streakKeepGoing =>
      tr('毎日1問、続けています', 'One problem a day, still going');
  String get weeklyHeadline => tr('今週の成績', 'This week');
  String weeklyAnswered(int n) => tr('$n問に挑戦', '$n problems');
  String weeklyCorrect(int n) => tr('正解 $n問', '$n correct');
  String weeklyAccuracy(int percent) =>
      tr('正解率 $percent%', 'Accuracy $percent%');
  String get weeklyHard => tr('今週の難問', 'Hardest problems');
  String get weeklySolved => tr('正解', 'Solved');
  String get weeklyMissed => tr('不正解', 'Missed');
  String weeklyPeriod(DateTime start) {
    final end = start.add(const Duration(days: 6));
    return tr(
      '${start.month}/${start.day} - ${end.month}/${end.day}',
      '${start.month}/${start.day} - ${end.month}/${end.day}',
    );
  }

  // --- 共有テキスト ---------------------------------------------------------
  String problemShareText(String url) => tr(
    'この手、何切る？ #何切る #なにきるカム\n$url',
    'What would you discard? #mahjong #NanikiruCam\n$url',
  );
  String resultShareText({
    required bool correct,
    int? percent,
    required String url,
  }) {
    final head = correct
        ? (percent != null && percent < 40
              ? tr('正解率$percent%の難問に正解！', 'Solved a $percent% problem!')
              : tr('何切る、正解！', 'Got the discard right!'))
        : tr('何切る、挑戦しました', 'Tried a discard problem');
    return '$head #何切る #なにきるカム\n$url';
  }

  String liveShareText(String url) => tr(
    'ナビを使って打ちました（友人戦） #なにきるカム\n$url',
    'Played with the navigator (friendly game) #NanikiruCam\n$url',
  );
  String streakShareText(int days, String url) => tr(
    '何切るを$days日連続で解いています #なにきるカム\n$url',
    'Solving discard problems for $days days in a row #NanikiruCam\n$url',
  );
  String weeklyShareText(String url) => tr(
    '今週の何切る成績 #なにきるカム\n$url',
    'My discard problems this week #NanikiruCam\n$url',
  );
}

extension ShareStringsContext on BuildContext {
  ShareStrings get shareStrings => ShareStrings(lang);
}

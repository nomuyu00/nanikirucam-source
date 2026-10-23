import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart' show DailyLevel;
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';

/// 今日の問題・出題した問題（problems/）の文言。
class ProblemsStrings extends FeatureStrings {
  const ProblemsStrings(super.lang);

  String get todayTitle => tr('今日の問題', 'Problem of the day');
  String get myProblemsTitle => tr('出題した問題', 'My problems');

  // --- 共通 ---------------------------------------------------------------
  String get offline => tr(
    '読み込めませんでした。通信状態を確かめて、もう一度お試しください',
    'Could not load. Check your connection and try again.',
  );
  String get onlineUnavailable =>
      tr('オンライン機能は準備中です', 'Online features are not available yet');
  String get retry => tr('再読み込み', 'Reload');
  String answers(int n) => tr('$n人が回答', '$n answered');
  String get noAnswersYet => tr('まだ回答がありません', 'No answers yet');
  String correctRate(int percent) => tr('正解率 $percent%', 'Solved by $percent%');
  String author(String name) =>
      name.isEmpty ? tr('出題: 匿名', 'By anonymous') : tr('出題: $name', 'By $name');
  String get anonymous => tr('匿名', 'Anonymous');

  // --- 今日の問題 -----------------------------------------------------------
  String dateLabel(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return date;
    return tr('$month月$day日の問題', 'Problems for $month/$day');
  }

  String get officialBadge => tr('公式', 'Official');
  String get communityBadge => tr('みんなの問題', 'Community');
  String get todayEmpty => tr(
    '今日の問題はまだ準備中です。0時に更新されます',
    'Today\'s problems are not ready yet. They update at midnight (JST).',
  );
  String get dayEmpty => tr('この日の問題はありません', 'No problems for this day');
  String get todayPast => tr('前の日の問題', 'Previous day');
  String get todayNext => tr('次の日の問題', 'Next day');
  String get todayTimedNote =>
      tr('制限時間つきで解きます', 'You solve this one against the clock');
  String get pastLockedTitle => tr('過去の問題は Pro で', 'Past problems are for Pro');
  String get pastLockedBody => tr(
    'Pro では過去の「今日の問題」をさかのぼって解けます',
    'With Pro you can solve past daily problems.',
  );
  String get seePro => tr('Pro を見る', 'See Pro');
  String get popularTitle => tr('もっと解く（Pro）', 'Solve more (Pro)');
  String get popularLockedBody => tr(
    'Pro では回答の多い人気問題を、制限なく解けます',
    'With Pro you can solve popular problems without limits.',
  );

  // --- 端末内で作る今日の問題（サーバーなしの版） ------------------------------
  String levelBadge(DailyLevel level) => switch (level) {
    DailyLevel.basic => tr('基本', 'Basic'),
    DailyLevel.standard => tr('標準', 'Standard'),
    DailyLevel.advanced => tr('応用', 'Advanced'),
  };
  String levelHint(DailyLevel level) => switch (level) {
    DailyLevel.basic => tr(
      '受け入れの差がはっきりした手',
      'One discard clearly takes more tiles',
    ),
    DailyLevel.standard => tr('候補の受け入れが拮抗する手', 'Several discards are close'),
    DailyLevel.advanced => tr(
      '速さ・打点・バランスで答えが割れる手',
      'Speed, value and balance disagree',
    ),
  };
  String get solvedBadge => tr('解答済み', 'Solved');
  String dailyProgress(int solved, int total) =>
      tr('$solved / $total 問 解答済み', '$solved of $total solved');
  String allSolved({required bool isToday}) => isToday
      ? tr('今日の 3 問をすべて解きました！', 'You solved all three today!')
      : tr('この日の 3 問をすべて解きました', 'You solved all three for this day');
  String get localDailyNote => tr(
    '問題は毎日 0 時（日本時間）に替わります。端末の中で作るので通信はいりません',
    'New problems every day at midnight (JST). They are made on your device, no connection needed.',
  );
  String get generating => tr('問題を用意しています', 'Preparing the problems');
  String get generateFailed => tr(
    '問題を用意できませんでした。もう一度お試しください',
    'Could not prepare the problems. Please try again.',
  );
  String get tryAgain => tr('もう一度', 'Try again');

  // --- 出題した問題 ---------------------------------------------------------
  String get myProblemsEmpty => tr(
    'まだ出題していません。結果画面の「友達に出題」から問題を公開できます',
    'You have not published any problems yet. Use "Challenge a friend" on the result screen.',
  );
  String get hiddenBadge => tr('非表示', 'Hidden');
  String get hiddenHelp =>
      tr('通報により、他の人には表示されていません', 'Hidden from others after reports');
  String get shareAgain => tr('もう一度シェア', 'Share again');
  String pendingPublish(int n) => tr(
    '公開待ち $n件（通信が戻ると自動で公開します）',
    '$n waiting to publish (they publish automatically when you are back online)',
  );

  /// 回答数が節目（10 / 50 / 100）に届いたときの表示。届いていなければ null。
  String? milestone(int total) {
    final reached = total >= 100
        ? 100
        : total >= 50
        ? 50
        : total >= 10
        ? 10
        : 0;
    if (reached == 0) return null;
    return tr('$reached人が回答！もう一度シェアしよう', '$reached answered! Share it again');
  }

  String createdLabel(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
  }

  // --- 問題を開く -------------------------------------------------------------
  String get problemNotFound => tr(
    'この問題は見つかりませんでした。削除されたか、非表示になっています',
    'This problem was not found. It may have been removed or hidden.',
  );
  String get problemOffline => tr(
    '問題を読み込めませんでした。通信状態を確かめてください',
    'Could not load the problem. Check your connection.',
  );
  String get opening => tr('問題を開いています', 'Opening the problem');

  // --- 通報 -----------------------------------------------------------------
  String get report => tr('この問題を通報', 'Report this problem');
  String get reportTitle => tr('通報の理由', 'Why are you reporting this?');
  String reasonLabel(ProblemReportReason reason) => switch (reason) {
    ProblemReportReason.spam => tr('スパム・宣伝', 'Spam or advertising'),
    ProblemReportReason.offensive => tr('不快な内容', 'Offensive content'),
    ProblemReportReason.wrongAnswer => tr('正解がおかしい', 'The answer looks wrong'),
    ProblemReportReason.other => tr('その他', 'Other'),
  };
  String get reportDone => tr('通報しました。ご協力ありがとうございます', 'Reported. Thank you.');
  String get reportAlready =>
      tr('この問題はすでに通報済みです', 'You already reported this problem');
  String get reportOwn =>
      tr('自分の問題は通報できません', 'You cannot report your own problem');
  String get reportFailed => tr('通報できませんでした', 'Could not report');

  // --- ブロック（App Store 審査ガイドライン 1.2） -----------------------------
  String get blockAuthor => tr('この出題者をブロック', 'Block this author');
  String get blockConfirmTitle => tr('この出題者をブロックしますか？', 'Block this author?');
  String blockConfirmBody(String name) => tr(
    '「${authorName(name)}」の問題は、今日の問題・一覧・リンクから表示されなくなります。設定からいつでも解除できます。',
    'Problems by "${authorName(name)}" will no longer appear in daily problems, lists or links. You can unblock them any time in Settings.',
  );
  String get blockAction => tr('ブロック', 'Block');
  String get blockDone =>
      tr('ブロックしました。設定から解除できます', 'Blocked. You can undo this in Settings.');
  String get blockFailed => tr(
    'ブロックできませんでした。通信状態を確かめてください',
    'Could not block. Check your connection.',
  );
  String get blockSelf =>
      tr('自分の問題の出題者はブロックできません', 'You cannot block yourself');

  /// 出題者名。空なら「匿名の出題者」。
  String authorName(String name) =>
      name.trim().isEmpty ? tr('匿名の出題者', 'Anonymous author') : name.trim();

  String get blockedProblemNotice =>
      tr('ブロック中の出題者の問題です', 'This problem is by a blocked author');
  String get unblockAndOpen => tr('解除して開く', 'Unblock and open');
  String get todayAllBlocked =>
      tr('ブロック中の出題者の問題は表示されません', 'Problems by blocked authors are hidden');

  // 設定: ブロック中の出題者
  String get blockedSection => tr('ブロック中の出題者', 'Blocked authors');
  String get blockedEmpty => tr(
    'ブロックしている出題者はいません。問題のメニューからブロックできます',
    'You have not blocked anyone. You can block an author from a problem\'s menu.',
  );
  String get unblock => tr('解除', 'Unblock');
  String get unblocked => tr('ブロックを解除しました', 'Unblocked');
  String blockedOn(DateTime at) => tr(
    '${at.year}/${at.month}/${at.day} にブロック',
    'Blocked on ${at.year}/${at.month}/${at.day}',
  );
  String get problemMenuTooltip => tr('問題のメニュー', 'Problem menu');
}

extension ProblemsStringsContext on BuildContext {
  ProblemsStrings get problemsStrings => ProblemsStrings(lang);
}

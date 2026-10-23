import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// 通知（notifications/）の文言。ローカル通知は予約した時点の言語で作る。
class NotificationStrings extends FeatureStrings {
  const NotificationStrings(super.lang);

  String get channelName => tr('リマインド', 'Reminders');
  String get channelDescription => tr(
    '今日の問題・連続回答のリマインドと、無料トライアルの終了のお知らせ',
    'Daily problems, streak reminders and free trial ending notices',
  );

  /// ストリークのリマインド（21:00）。[current] はいまの連続日数。
  String streakTitle(int current) => current > 0
      ? tr('$current日連続中！', '$current-day streak!')
      : tr('今日の何切る、まだですか？', 'Have you solved today\'s problem?');

  String streakBody(int current) => current > 0
      ? tr('今日の1問を解いて、記録をつなげましょう。', 'Solve one today to keep it going.')
      : tr('1問だけ解いてみませんか？', 'Try just one problem.');

  /// ライブを使った 24 時間後の「昨日の対局サマリー」（仕様 11 章）。
  String get liveSummaryTitle =>
      tr('昨日の対局サマリー', "Yesterday's match summary");

  String liveSummaryBody(int adviceCount, int winCount) => tr(
    '案内$adviceCount回、和了$winCount回。振り返りと共有はこちらから。',
    '$adviceCount suggestions, $winCount wins. Look back and share.',
  );

  /// 毎朝の今日の問題（サーバーなしの版で端末が予約する。8:00）。
  String get dailyTitle => tr('今日の何切る 3 問', "Today's three problems");
  String get dailyBody => tr(
    '基本・標準・応用の 3 問が新しくなりました。',
    'New basic, standard and advanced problems are ready.',
  );

  String get trialTitle => tr('無料トライアルは明日までです', 'Your free trial ends tomorrow');
  String get trialBody => tr(
    '継続しない場合は、ストアの購読設定から解約してください。',
    'To cancel, manage your subscription in the store settings.',
  );
}

extension NotificationStringsContext on BuildContext {
  NotificationStrings get notificationStrings => NotificationStrings(lang);
}

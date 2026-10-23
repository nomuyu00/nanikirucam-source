import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// Home（ui/home/）の文言。
class HomeStrings extends FeatureStrings {
  const HomeStrings(super.lang);

  String get live => tr('ライブナビ', 'Live Navi');
  String get liveSubtitle =>
      tr('かざすだけで、切る牌を案内', 'Point your camera for live tips');
  String get livePro => tr('Pro: 無制限', 'Pro: unlimited');
  String liveTrialLeft(int minutes, int seconds) => tr(
    '今日の体験 残り $minutes 分 ${seconds.toString().padLeft(2, '0')} 秒',
    'Free trial: ${minutes}m ${seconds.toString().padLeft(2, '0')}s left today',
  );
  String get liveTrialUsed =>
      tr('今日の体験は終了（Pro は無制限）', 'Trial used today (unlimited with Pro)');
  String get photo => tr('写真で解析', 'Analyze a photo');
  String get photoSubtitle => tr('手牌を撮って、何切るを解く', 'Snap a hand and solve it');
  String photoRemaining(int n, int limit) =>
      tr('今日あと $n / $limit 回', '$n of $limit left today');
  String get photoUnlimited => tr('Pro: 無制限', 'Pro: unlimited');
  String get manual => tr('手入力', 'Enter by hand');
  String get score => tr('点数計算', 'Score a win');
  String get scoreSubtitle =>
      tr('和了の手を撮って、役と点数', 'Snap a winning hand for yaku & points');
  String get scoreDetailPro => tr('撮影・手入力', 'Photo or by hand');
  String get scoreDetailFree => tr('Pro の機能', 'Pro feature');
  String get today => tr('今日の問題', 'Problem of the day');
  String get todaySubtitle => tr('毎日 3 問', 'Three a day');
  String todayProgress(int solved, int total) =>
      tr('$solved / $total 問クリア', '$solved of $total solved');
  String get todayDone => tr('今日の 3 問クリア！', 'All done for today!');
  String get more => tr('そのほか', 'More');
  String get myProblems => tr('出題した問題', 'My problems');
  String get history => tr('履歴', 'History');
  String get settings => tr('設定', 'Settings');
  String get pro => tr('Pro', 'Pro');

  String streak(int days) => tr('$days 日連続', '$days-day streak');
  String bestStreak(int days) => tr('最高 $days 日', 'Best $days');
  String get noStreak =>
      tr('今日の 1 問で連続記録を始めよう', 'Answer one today to start a streak');
  String weekAccuracy(int percent, int correct, int answered) => tr(
    '今週の正解率 $percent%（$correct / $answered 問）',
    'This week: $percent% ($correct / $answered)',
  );
  String get weekNone => tr('今週はまだ回答がありません', 'No answers this week yet');
  String lastLive(int minutes, int advice, int wins) => tr(
    '直近のライブ: $minutes 分・案内 $advice 回・和了 $wins 回',
    'Last live: $minutes min · $advice tips · $wins wins',
  );
  String lastLiveBest(String points) => tr('最高 $points 点', 'best $points');
}

extension HomeStringsContext on BuildContext {
  HomeStrings get homeStrings => HomeStrings(lang);
}

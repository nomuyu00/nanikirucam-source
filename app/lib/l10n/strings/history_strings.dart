import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// 履歴・弱点（history/）の文言。
class HistoryStrings extends FeatureStrings {
  const HistoryStrings(super.lang);

  String get title => tr('履歴', 'History');
  String get empty => tr(
    'まだ記録がありません。写真や手入力で解析すると、ここに残ります。',
    'Nothing yet. Hands you analyze will show up here.',
  );
  String get loadFailed => tr('履歴を読み込めませんでした', 'Could not load your history');
  String get correct => tr('正解', 'Correct');
  String get incorrect => tr('不正解', 'Missed');
  String get notAnswered => tr('未回答', 'No answer');
  String get pending => tr('未解析', 'Not analyzed');
  String get pendingSummary => tr(
    '撮るだけモードで保存した手。タップして確認・解析',
    'Saved by quick capture. Tap to check and analyze',
  );
  String yourChoice(String tile) => tr('あなた: $tile', 'You: $tile');
  String answer(String axis, String tiles) =>
      tr('$axisの答え: $tiles', '$axis: $tiles');
  String moreLocked(int n, int free) => tr(
    'それより古い $n 件は Pro で見られます（無料は直近 $free 件）',
    '$n older entries are available with Pro (free shows the latest $free)',
  );
  String get weaknessTitle => tr('弱点分析', 'Your weak spots');
  String get weaknessLocked => tr(
    '弱点分析（軸ごとの正解率・間違えやすい形）',
    'Weak-spot analysis (accuracy by axis, common misses)',
  );
  String get weaknessEmpty =>
      tr('クイズに答えると、ここに集計が出ます', 'Answer quizzes to see your stats');
  String axisAccuracy(String axis, int correct, int answered, int percent) =>
      tr(
        '$axis  $correct / $answered 問（$percent%）',
        '$axis  $correct / $answered ($percent%)',
      );
  String get missedTagsTitle => tr('間違えた問題に多い形', 'Most common in your misses');
  String tagCount(String tag, int n) => tr('$tag（$n 問）', '$tag ($n)');
  String get clear => tr('履歴を消す', 'Clear history');
  String get clearConfirm =>
      tr('端末に残っている履歴をすべて消します。よろしいですか？', 'Delete all history on this device?');
  String get clearAction => tr('消す', 'Delete');
  String thirteenTiles(String shanten) =>
      tr('13 枚・$shanten', '13 tiles · $shanten');

  /// 一覧の日付の見出し（今日・昨日・「10月21日（火）」）。
  String dayHeader(DateTime day, DateTime now) {
    final d = DateTime(day.year, day.month, day.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return tr('今日', 'Today');
    if (diff == 1) return tr('昨日', 'Yesterday');
    const ja = ['月', '火', '水', '木', '金', '土', '日'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final w = day.weekday - 1;
    final sameYear = day.year == now.year;
    return tr(
      '${sameYear ? '' : '${day.year}年'}${day.month}月${day.day}日（${ja[w]}）',
      '${en[w]}, ${months[day.month - 1]} ${day.day}${sameYear ? '' : ', ${day.year}'}',
    );
  }
}

extension HistoryStringsContext on BuildContext {
  HistoryStrings get historyStrings => HistoryStrings(lang);
}

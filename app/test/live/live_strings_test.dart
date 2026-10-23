import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';

void main() {
  const en = LiveStrings(AppLang.en);
  const ja = LiveStrings(AppLang.ja);

  test('英語は 1 なら単数、それ以外は複数', () {
    expect(en.todaySummary(1, 0), '1 session, 0 wins');
    expect(en.todaySummary(2, 1), '2 sessions, 1 win');
    expect(
      en.allTimeSummary(1, 1, 8000),
      'All time: 1 session, 1 win, best 8,000 pts',
    );
    expect(en.ukeire(1, 4), '1 kind / 4 tiles');
    expect(en.ukeire(8, 1), '8 kinds / 1 tile');
    expect(en.stateCount(12), '12 tiles');
  });

  test('日本語はそのまま', () {
    expect(ja.todaySummary(1, 0), '1回・和了0回');
    expect(ja.ukeire(1, 4), '受け入れ 1種4枚');
    expect(ja.allTimeSummary(3, 2, 12000), 'これまで 3回・和了2回・最高12,000点');
  });
}

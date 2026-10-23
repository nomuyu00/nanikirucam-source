import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';

void main() {
  group('対局サマリーの通知の時刻', () {
    test('ふつうは終了の 24 時間後', () {
      expect(
        LocalScheduler.liveSummaryTime(DateTime(2026, 10, 21, 22, 30)),
        DateTime(2026, 10, 22, 22, 30),
      );
      expect(
        LocalScheduler.liveSummaryTime(DateTime(2026, 10, 21, 8)),
        DateTime(2026, 10, 22, 8),
      );
    });

    test('深夜（0 時〜8 時）に当たるときはその日の 9 時にずらす', () {
      expect(
        LocalScheduler.liveSummaryTime(DateTime(2026, 10, 21, 0, 40)),
        DateTime(2026, 10, 22, 9),
      );
      expect(
        LocalScheduler.liveSummaryTime(DateTime(2026, 10, 21, 7, 59)),
        DateTime(2026, 10, 22, 9),
      );
    });
  });
}

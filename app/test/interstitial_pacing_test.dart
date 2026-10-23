import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ads/interstitial_pacing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late InterstitialPacing pacing;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 21, 12);
    pacing = InterstitialPacing(
      await SharedPreferences.getInstance(),
      now: () => now,
    );
  });

  Future<void> results(int n) async {
    for (var i = 0; i < n; i++) {
      await pacing.recordResult();
    }
  }

  test('最初の 3 回の結果では出さない（仕様 9 章）', () async {
    await results(3);
    expect(pacing.shouldShow(), isFalse);
  });

  test('4 回目の結果から出せる。出したら 3 回分たまるまで出さない', () async {
    await results(4);
    expect(pacing.shouldShow(), isTrue);
    await pacing.markShown();
    await results(2);
    now = now.add(const Duration(minutes: 10));
    expect(pacing.shouldShow(), isFalse);
    await results(1);
    expect(pacing.shouldShow(), isTrue);
  });

  test('前回から 4 分以上空ける', () async {
    await results(4);
    await pacing.markShown();
    await results(3);
    now = now.add(const Duration(minutes: 3, seconds: 59));
    expect(pacing.shouldShow(), isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(pacing.shouldShow(), isTrue);
  });

  test('共有した直後は出さない', () async {
    await results(10);
    expect(pacing.shouldShow(sharedJustNow: true), isFalse);
    expect(pacing.shouldShow(), isTrue);
  });
}

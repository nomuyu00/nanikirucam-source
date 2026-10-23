import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;

  Future<LiveTrial> create([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return LiveTrial(await SharedPreferences.getInstance(), now: () => now);
  }

  setUp(() => now = DateTime(2026, 10, 21, 20, 30));

  test('滞在秒数を足して保存する（live_trial_v1）', () async {
    final trial = await create();
    expect(trial.load(pro: false).usedSeconds, 0);
    expect(trial.load(pro: false).remainingSeconds, 300);

    await trial.addSeconds(5, pro: false);
    final state = await trial.addSeconds(60, pro: false);
    expect(state.usedSeconds, 65);
    expect(state.remainingSeconds, 235);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(LiveTrial.preferenceKey)!), {
      'date': '2026-10-21',
      'usedSeconds': 65,
      'bonusSeconds': 0,
      'bonusGrants': 0,
    });
  });

  test('300 秒で使い切り（残りは 0 未満にならない）', () async {
    final trial = await create();
    await trial.addSeconds(299, pro: false);
    expect(trial.load(pro: false).exhausted, isFalse);
    final state = await trial.addSeconds(5, pro: false);
    expect(state.exhausted, isTrue);
    expect(state.remainingSeconds, 0);
  });

  test('日付が変わったら 0 から', () async {
    final trial = await create({
      LiveTrial.preferenceKey: jsonEncode({
        'date': '2026-10-21',
        'usedSeconds': 300,
      }),
    });
    expect(trial.load(pro: false).exhausted, isTrue);
    now = DateTime(2026, 10, 22, 0, 0, 1);
    expect(trial.load(pro: false).usedSeconds, 0);
    final next = await trial.addSeconds(10, pro: false);
    expect(next.date, '2026-10-22');
    expect(next.usedSeconds, 10);
  });

  test('Pro は数えない（使い切りにもならない）', () async {
    final trial = await create({
      LiveTrial.preferenceKey: jsonEncode({
        'date': '2026-10-21',
        'usedSeconds': 300,
      }),
    });
    final state = await trial.addSeconds(60, pro: true);
    expect(state.unlimited, isTrue);
    expect(state.exhausted, isFalse);
    expect(trial.load(pro: false).usedSeconds, 300, reason: '保存値は変えない');
  });

  test('壊れた値は 0 として扱う', () async {
    final trial = await create({LiveTrial.preferenceKey: 'not json'});
    expect(trial.load(pro: false).usedSeconds, 0);
  });

  group('動画での延長（bonus）', () {
    test('広告を見た時間で 3 段階: 12 秒未満 +1 分 / 25 秒未満 +2 分 / それ以上 +3 分', () {
      int f(int ms) => LiveTrial.bonusSecondsFor(Duration(milliseconds: ms));
      expect(f(0), 60);
      expect(f(11999), 60);
      expect(f(12000), 120);
      expect(f(24999), 120);
      expect(f(25000), 180);
      expect(f(90000), 180);
    });

    test('表示時刻が取れなかったとき（null）は +1 分', () {
      expect(LiveTrial.bonusSecondsFor(null), 60);
    });

    test('延長すると上限が増え、使い切りが解ける。保存する', () async {
      final trial = await create({
        LiveTrial.preferenceKey: jsonEncode({
          'date': '2026-10-21',
          'usedSeconds': 300,
        }),
      });
      expect(trial.load(pro: false).exhausted, isTrue);
      expect(trial.load(pro: false).canExtend, isTrue);

      final state = await trial.grantBonus(120, pro: false);
      expect(state.bonusSeconds, 120);
      expect(state.bonusGrants, 1);
      expect(state.limitSeconds, 420);
      expect(state.remainingSeconds, 120);
      expect(state.exhausted, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(LiveTrial.preferenceKey)!), {
        'date': '2026-10-21',
        'usedSeconds': 300,
        'bonusSeconds': 120,
        'bonusGrants': 1,
      });
      expect(trial.load(pro: false).limitSeconds, 420);
    });

    test('滞在秒数を足しても延長分を落とさない。延長後も 420 秒で使い切り', () async {
      final trial = await create();
      await trial.addSeconds(300, pro: false);
      await trial.grantBonus(120, pro: false);
      final state = await trial.addSeconds(100, pro: false);
      expect(state.bonusSeconds, 120);
      expect(state.bonusGrants, 1);
      expect(state.usedSeconds, 400);
      expect(state.exhausted, isFalse);
      expect(state.remainingSeconds, 20);
      final done = await trial.addSeconds(30, pro: false);
      expect(done.exhausted, isTrue);
      expect(done.remainingSeconds, 0);
    });

    test('旧データ（bonus なし）は 0 として読む', () async {
      final trial = await create({
        LiveTrial.preferenceKey: jsonEncode({
          'date': '2026-10-21',
          'usedSeconds': 100,
        }),
      });
      final state = trial.load(pro: false);
      expect(state.usedSeconds, 100);
      expect(state.bonusSeconds, 0);
      expect(state.bonusGrants, 0);
      expect(state.limitSeconds, 300);
      expect(state.canExtend, isTrue);
    });

    test('壊れた bonus の値は 0 として扱う', () async {
      final trial = await create({
        LiveTrial.preferenceKey: jsonEncode({
          'date': '2026-10-21',
          'usedSeconds': 10,
          'bonusSeconds': 'x',
          'bonusGrants': -3,
        }),
      });
      final state = trial.load(pro: false);
      expect(state.bonusSeconds, 0);
      expect(state.bonusGrants, 0);
    });

    test('延長は 1 日 5 回まで（最大 +15 分）。超えたら何も足さない', () async {
      final trial = await create();
      for (var i = 0; i < LiveTrial.maxBonusGrantsPerDay; i++) {
        expect(trial.load(pro: false).canExtend, isTrue);
        await trial.grantBonus(180, pro: false);
      }
      final full = trial.load(pro: false);
      expect(full.bonusGrants, 5);
      expect(full.bonusSeconds, 900);
      expect(full.limitSeconds, 1200);
      expect(full.canExtend, isFalse);

      final extra = await trial.grantBonus(180, pro: false);
      expect(extra.bonusGrants, 5);
      expect(extra.bonusSeconds, 900);
      expect(trial.load(pro: false).bonusSeconds, 900);
    });

    test('日付が変わったら延長もリセットされる', () async {
      final trial = await create();
      await trial.addSeconds(300, pro: false);
      await trial.grantBonus(180, pro: false);
      expect(trial.load(pro: false).limitSeconds, 480);

      now = DateTime(2026, 10, 22, 0, 0, 1);
      final next = trial.load(pro: false);
      expect(next.bonusSeconds, 0);
      expect(next.bonusGrants, 0);
      expect(next.limitSeconds, 300);
      expect(next.usedSeconds, 0);
      expect(next.canExtend, isTrue);

      final granted = await trial.grantBonus(60, pro: false);
      expect(granted.date, '2026-10-22');
      expect(granted.bonusGrants, 1);
      expect(granted.usedSeconds, 0);
    });

    test('Pro は延長しない（保存値も変えない）', () async {
      final trial = await create({
        LiveTrial.preferenceKey: jsonEncode({
          'date': '2026-10-21',
          'usedSeconds': 300,
        }),
      });
      final state = await trial.grantBonus(180, pro: true);
      expect(state.unlimited, isTrue);
      expect(state.canExtend, isFalse);
      expect(state.bonusGrants, 0);
      expect(trial.load(pro: false).bonusSeconds, 0);
    });

    test('0 秒以下は延長にならない', () async {
      final trial = await create();
      final state = await trial.grantBonus(0, pro: false);
      expect(state.bonusGrants, 0);
      expect(state.bonusSeconds, 0);
    });
  });
}

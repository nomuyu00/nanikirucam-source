import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<LiveSessionStore> create() async {
    SharedPreferences.setMockInitialValues({});
    return LiveSessionStore(await SharedPreferences.getInstance());
  }

  final hand = HandInput(
    tiles: const [
      '1m', '2m', '3m', '4m', '5m', '6m', '7p', '8p', //
      '9p', '2s', '3s', '4s', '5z', '5z',
    ],
    tsumoIndex: 13,
    seatWind: Wind.east,
  );

  LiveSession session(int minute, {List<LiveWinRecord> wins = const []}) =>
      LiveSession(
        startedAt: DateTime(2026, 10, 21, 20, minute),
        durationSec: 120,
        adviceCount: 6,
        followedCount: 2,
        followChecks: 3,
        wins: wins,
        endedBy: 'user',
      );

  test('保存して新しい順に読む（live_sessions_v1）', () async {
    final store = await create();
    await store.add(session(1));
    await store.add(
      session(
        2,
        wins: [
          LiveWinRecord(
            han: 3,
            fu: 40,
            points: 7700,
            yaku: const ['門前清自摸和', '役牌 白'],
            rank: 'none',
            hand: hand,
          ),
        ],
      ),
    );
    final loaded = store.load();
    expect(loaded.map((s) => s.startedAt.minute), [2, 1]);
    final first = loaded.first;
    expect(first.durationSec, 120);
    expect(first.adviceCount, 6);
    expect(first.followRate, closeTo(2 / 3, 1e-9));
    expect(first.wins.single.points, 7700);
    expect(first.wins.single.yaku, ['門前清自摸和', '役牌 白']);
    expect(first.wins.single.hand, hand);
    expect(store.find(DateTime(2026, 10, 21, 20, 1))?.adviceCount, 6);

    final args = first.toSummaryArgs();
    expect(args.wins.single.han, 3);
    expect(args.followedCount, 2);
    expect(args.followChecks, 3);
  });

  test('最大件数を超えたら古いものから消す', () async {
    final store = await create();
    for (var i = 0; i < LiveSessionStore.maxSessions + 3; i++) {
      await store.add(
        LiveSession(
          startedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          durationSec: i,
        ),
      );
    }
    final loaded = store.load();
    expect(loaded.length, LiveSessionStore.maxSessions);
    expect(loaded.first.durationSec, LiveSessionStore.maxSessions + 2);
  });

  test('壊れた値・消去', () async {
    SharedPreferences.setMockInitialValues({
      LiveSessionStore.preferenceKey: '[{"startedAt":"x"},{}, 3]',
    });
    final store = LiveSessionStore(await SharedPreferences.getInstance());
    expect(store.load(), isEmpty);
    await store.add(session(5));
    expect(store.load().length, 1);
    await store.clear();
    expect(store.load(), isEmpty);
  });
}

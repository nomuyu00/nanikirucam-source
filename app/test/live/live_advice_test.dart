import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_device.dart';

import 'support/live_fakes.dart';

void main() {
  group('採用率（AdviceFollowTracker）', () {
    final hand14 = HandFixtures.fourteen;
    final counts14 = countsOfLabels(hand14);
    final east = tileIdFromLabel('1z');

    test('案内した牌が次の 13 枚から消えていれば followed=true', () {
      final follow = AdviceFollowTracker()..onDiscardAdvice(counts14, east);
      final hand13 = [...hand14]..remove('1z');
      expect(follow.onStableThirteen(countsOfLabels(hand13)), isTrue);
      expect(follow.hasPending, isFalse, reason: '1 回だけ判定する');
      expect(follow.onStableThirteen(countsOfLabels(hand13)), isNull);
    });

    test('別の牌を切っていれば followed=false', () {
      final follow = AdviceFollowTracker()..onDiscardAdvice(counts14, east);
      final hand13 = [...hand14]..remove('3p');
      expect(follow.onStableThirteen(countsOfLabels(hand13)), isFalse);
    });

    test('14 枚から 1 枚切った手でなければ判定しない（誤認識・次の局）', () {
      final follow = AdviceFollowTracker()..onDiscardAdvice(counts14, east);
      final other = [...hand14]
        ..remove('1z')
        ..remove('2s')
        ..add('9s');
      expect(follow.onStableThirteen(countsOfLabels(other)), isNull);
    });

    test('軸を切り替えたら、今出ている牌で判定する', () {
      final follow = AdviceFollowTracker()
        ..onDiscardAdvice(counts14, east)
        ..onDiscardAdvice(counts14, tileIdFromLabel('2s'));
      final hand13 = [...hand14]..remove('1z');
      expect(follow.onStableThirteen(countsOfLabels(hand13)), isFalse);
    });
  });

  group('slotForDiscard', () {
    test('同じ牌が複数あれば赤でない右側の牌、ツモ牌が同じならツモ牌', () {
      final labels = ['1m', '5m', '0m', '5m', '7p', '9s'];
      final five = tileIdFromLabel('5m');
      expect(slotForDiscard(labels, five), 3);
      expect(slotForDiscard(labels, five, tsumoIndex: 1), 1);
      // ツモ牌が赤5で、他に普通の 5 があるなら赤は残す。
      expect(slotForDiscard(labels, five, tsumoIndex: 2), 3);
      expect(slotForDiscard(['0p', '1z'], tileIdFromLabel('5p')), 0);
      expect(slotForDiscard(labels, tileIdFromLabel('1z')), isNull);
    });
  });

  group('rolesForSlots', () {
    test('面子・搭子・孤立を左からのスロットに割り当てる', () {
      final labels = HandFixtures.fourteen;
      final roles = rolesForSlots(
        labels,
        HandInput(tiles: labels).toHandState(),
      );
      expect(roles.length, 14);
      expect(roles.where((r) => r == LiveTileRole.meld).length, 9);
      expect(roles.where((r) => r == LiveTileRole.partial).length, 4);
      expect(roles.last, LiveTileRole.isolated, reason: '孤立の東');
    });
  });

  group('和了', () {
    test('格は翻・符から（切り上げ満貫は数えない）', () {
      expect(winRank(han: 2, fu: 40), 'none');
      expect(winRank(han: 3, fu: 60), 'none');
      expect(winRank(han: 3, fu: 70), 'mangan');
      expect(winRank(han: 4, fu: 40), 'mangan');
      expect(winRank(han: 5, fu: 30), 'mangan');
      expect(winRank(han: 7, fu: 30), 'haneman');
      expect(winRank(han: 9, fu: 30), 'baiman');
      expect(winRank(han: 12, fu: 30), 'sanbaiman');
      expect(winRank(han: 13, fu: 30), 'yakuman');
    });

    test('役の名前（ドラは枚数つき）', () {
      final report = DefaultNanikiruEngine().analyze(
        HandInput(
          tiles: HandFixtures.win,
          doraIndicators: const ['7z'],
        ).toHandState(),
        deep: false,
      );
      final score = report.win!;
      final names = yakuNames(score);
      // 白は対子（雀頭）なので役牌ではない。表示牌が中なのでドラは白 2 枚。
      expect(names, contains('門前清自摸和'));
      expect(names, isNot(contains('役牌 白')));
      expect(names, contains('ドラ2'));
    });
  });

  group('端末の状態', () {
    test('iOS の thermalState: serious 以上で警告、critical で終了', () {
      expect(
        ThermalStatus.fromPlatform({
          'platform': 'ios',
          'state': 'fair',
        }).warning,
        isFalse,
      );
      final serious = ThermalStatus.fromPlatform({'state': 'serious'});
      expect(serious.warning, isTrue);
      expect(serious.critical, isFalse);
      expect(
        ThermalStatus.fromPlatform({'state': 'critical'}).critical,
        isTrue,
      );
    });

    test('Android: headroom 0.8 以上か SEVERE 以上で警告', () {
      ThermalStatus android(int? status, double? headroom) =>
          ThermalStatus.fromPlatform({
            'platform': 'android',
            'status': status,
            'headroom': headroom,
          });
      expect(android(1, 0.5).warning, isFalse);
      expect(android(1, 0.8).warning, isTrue);
      expect(android(3, null).warning, isTrue);
      expect(android(2, 1.0).critical, isTrue);
      expect(android(4, null).critical, isTrue);
      expect(android(null, null).warning, isFalse);
      expect(ThermalStatus.fromPlatform(null).warning, isFalse);
    });

    test('Android: 端末のしきい値が取れればそれを使う（API 35+）', () {
      // エミュレータの HAL は skin 30℃ から熱いとみなすので headroom が 0.91 前後になるが、
      // その端末の MODERATE は 0.967、SEVERE は 1.0。固定の 0.8 だと誤って警告していた。
      ThermalStatus android(
        double headroom, {
        double? moderate,
        double? severe,
      }) => ThermalStatus.fromPlatform({
        'platform': 'android',
        'status': 0,
        'headroom': headroom,
        'moderateHeadroom': moderate,
        'severeHeadroom': severe,
      });
      expect(android(0.91, moderate: 0.967, severe: 1.0).warning, isFalse);
      expect(android(0.97, moderate: 0.967, severe: 1.0).warning, isTrue);
      expect(android(0.97, moderate: 0.967, severe: 1.0).critical, isFalse);
      expect(android(1.0, moderate: 0.967, severe: 1.0).critical, isTrue);
      // しきい値が NaN（取れない）なら固定値。
      expect(android(0.85, moderate: double.nan).warning, isTrue);
      expect(android(0.85).warning, isTrue);
    });

    test('電池: 15% 未満で警告、5% 以下で終了（充電中は出さない）', () {
      expect(const BatteryStatus(level: 15).low, isFalse);
      expect(const BatteryStatus(level: 14).low, isTrue);
      expect(const BatteryStatus(level: 14, charging: true).low, isFalse);
      expect(const BatteryStatus(level: 5).critical, isTrue);
      expect(BatteryStatus.unknown.low, isFalse);
    });
  });
}

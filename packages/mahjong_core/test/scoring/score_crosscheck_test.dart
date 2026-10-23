import 'dart:io';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'mpsz_test_utils.dart';

// 期待値は ml/crosscheck_score.py が Python の mahjong==2.0.0
// （HandCalculator.estimate_hand_value）で出したもの。形式はフィクスチャ先頭のコメントを参照。
// 別のシードで試すときは環境変数 SCORE_CROSSCHECK_FIXTURE にパスを入れる。
final String _fixturePath =
    Platform.environment['SCORE_CROSSCHECK_FIXTURE'] ??
    'test/fixtures/score_crosscheck.txt';

/// フィクスチャのルール記号 → Ruleset（ml/crosscheck_score.py の PROFILES と 1 対 1）。
final Map<String, Ruleset> _profiles = {
  'A': Rulesets.mLeague(),
  'B': Rulesets.mLeague().copyWith(
    kuitan: false,
    redFives: 0,
    kiriageMangan: true,
  ),
  'C': Rulesets.mLeague().copyWith(
    doubleYakuman: true,
    countedYakuman: false,
    renhou: RenhouValue.yakuman,
  ),
  'D': Rulesets.mLeague().copyWith(renhou: RenhouValue.mangan),
};

/// Python の yaku_id → YakuId。風牌（18〜25）は別に扱う。
const Map<int, YakuId> _pyYaku = {
  0: YakuId.menzenTsumo,
  1: YakuId.riichi,
  3: YakuId.ippatsu,
  4: YakuId.chankan,
  5: YakuId.rinshan,
  6: YakuId.haitei,
  7: YakuId.houtei,
  8: YakuId.doubleRiichi,
  11: YakuId.renhou,
  12: YakuId.pinfu,
  13: YakuId.tanyao,
  14: YakuId.iipeikou,
  15: YakuId.yakuhaiHaku,
  16: YakuId.yakuhaiHatsu,
  17: YakuId.yakuhaiChun,
  26: YakuId.sanshoku,
  27: YakuId.ittsu,
  28: YakuId.chanta,
  29: YakuId.honroutou,
  30: YakuId.toitoi,
  31: YakuId.sanankou,
  32: YakuId.sankantsu,
  33: YakuId.sanshokuDoukou,
  34: YakuId.chiitoitsu,
  35: YakuId.shousangen,
  36: YakuId.honitsu,
  37: YakuId.junchan,
  38: YakuId.ryanpeikou,
  39: YakuId.chinitsu,
  100: YakuId.kokushi,
  101: YakuId.chuuren,
  102: YakuId.suuankou,
  103: YakuId.daisangen,
  104: YakuId.shousuushii,
  105: YakuId.ryuuiisou,
  106: YakuId.suukantsu,
  107: YakuId.tsuuiisou,
  108: YakuId.chinroutou,
  111: YakuId.daisuushii,
  112: YakuId.kokushi13,
  113: YakuId.suuankouTanki,
  114: YakuId.junseiChuuren,
  115: YakuId.tenhou,
  116: YakuId.chiihou,
  117: YakuId.renhou,
  120: YakuId.dora,
  121: YakuId.akaDora,
  122: YakuId.uraDora,
};

const Map<String, WinError> _pyErrors = {
  'winning_tile_not_in_hand': WinError.winningTileNotInHand,
  'hand_not_winning': WinError.notWinningHand,
  'no_yaku': WinError.noYaku,
  'open_hand_riichi_not_allowed': WinError.riichiWithOpenHand,
  'open_hand_daburi_not_allowed': WinError.riichiWithOpenHand,
  'ippatsu_without_riichi_not_allowed': WinError.ippatsuWithoutRiichi,
  'chankan_with_tsumo_not_allowed': WinError.chankanWithTsumo,
  'rinshan_without_tsumo_not_allowed': WinError.rinshanWithoutTsumo,
  'haitei_without_tsumo_not_allowed': WinError.haiteiWithoutTsumo,
  'houtei_with_tsumo_not_allowed': WinError.houteiWithTsumo,
  'haitei_with_rinshan_not_allowed': WinError.haiteiWithRinshan,
  'houtei_with_chankan_not_allowed': WinError.houteiWithChankan,
  'tenhou_not_as_dealer_not_allowed': WinError.tenhouNotDealer,
  'tenhou_without_tsumo_not_allowed': WinError.tenhouWithoutTsumo,
  'tenhou_with_meld_not_allowed': WinError.tenhouWithMeld,
  'chiihou_as_dealer_not_allowed': WinError.chiihouAsDealer,
  'chiihou_without_tsumo_not_allowed': WinError.chiihouWithoutTsumo,
  'chiihou_with_meld_not_allowed': WinError.chiihouWithMeld,
  'renhou_as_dealer_not_allowed': WinError.renhouAsDealer,
  'renhou_with_tsumo_not_allowed': WinError.renhouWithTsumo,
  'renhou_with_meld_not_allowed': WinError.renhouWithMeld,
};

const Map<HandRank, String> _pyLevels = {
  HandRank.none: '-',
  HandRank.mangan: 'mangan',
  HandRank.haneman: 'haneman',
  HandRank.baiman: 'baiman',
  HandRank.sanbaiman: 'sanbaiman',
  // 参照実装は数え役満の yaku_level を最後に "yakuman" で上書きする。
  HandRank.kazoeYakuman: 'yakuman',
  HandRank.yakuman: 'yakuman',
  HandRank.doubleYakuman: '2x_yakuman',
  HandRank.tripleYakuman: '3x_yakuman',
  HandRank.quadrupleYakuman: '4x_yakuman',
  HandRank.quintupleYakuman: '5x_yakuman',
  HandRank.sextupleYakuman: '6x_yakuman',
};

const Map<String, CalledMeldType> _meldKinds = {
  'c': CalledMeldType.chi,
  'p': CalledMeldType.pon,
  'm': CalledMeldType.minkan,
  'a': CalledMeldType.ankan,
  'k': CalledMeldType.kakan,
};

class _Case {
  final int lineNo;
  final String line;
  final String profile;
  final WinRequest request;
  final String expected;
  _Case(this.lineNo, this.line, this.profile, this.request, this.expected);
}

List<_Case> _loadCases() {
  final lines = File(_fixturePath).readAsLinesSync();
  final cases = <_Case>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final f = line.split(' ');
    if (f.length != 8) {
      throw FormatException('フィクスチャ ${i + 1} 行目の形式が違う: $line');
    }
    final melds = f[2] == '-'
        ? const <CalledMeld>[]
        : [
            for (final m in f[2].split(','))
              CalledMeld(_meldKinds[m[0]]!, parseMpsz(m.substring(1))),
          ];
    final ctx = f[4].split(',');
    final flags = ctx[5];
    bool flag(String c) => flags.contains(c);
    final request = WinRequest(
      handTiles: parseMpsz(f[1]),
      melds: melds,
      winningTile: f[3],
      winType: ctx[0] == 'T' ? WinType.tsumo : WinType.ron,
      roundWind: Wind.values[int.parse(ctx[1]) - 1],
      seatWind: Wind.values[int.parse(ctx[2]) - 1],
      honba: int.parse(ctx[3]),
      kyotaku: int.parse(ctx[4]),
      riichi: flag('r'),
      doubleRiichi: flag('d'),
      ippatsu: flag('i'),
      haitei: flag('h'),
      houtei: flag('H'),
      rinshan: flag('n'),
      chankan: flag('c'),
      tenhou: flag('t'),
      chiihou: flag('j'),
      renhou: flag('e'),
      doraIndicators: parseMpsz(f[5]),
      uraDoraIndicators: parseMpsz(f[6]),
    );
    cases.add(_Case(i + 1, line, f[0], request, f[7]));
  }
  return cases;
}

/// Python の役の一覧を「id名:翻」の並び（整列済み）にする。同じ風の自風＋場風は連風牌にまとめる。
List<String> _expectedYaku(String spec) {
  final items = <String>[];
  final seat = <int>{};
  final round = <int>{};
  for (final item in spec.split('+')) {
    if (item.isEmpty) continue;
    final parts = item.split(':');
    final id = int.parse(parts[0]);
    final han = int.parse(parts[1]);
    if (id >= 18 && id <= 21) {
      seat.add(id - 18);
      continue;
    }
    if (id >= 22 && id <= 25) {
      round.add(id - 22);
      continue;
    }
    final yaku = _pyYaku[id];
    if (yaku == null) throw StateError('未対応の yaku_id $id');
    items.add('${yaku.name}:$han');
  }
  for (final w in seat.union(round)) {
    if (seat.contains(w) && round.contains(w)) {
      items.add('${YakuId.doubleWind.name}:2');
    } else if (seat.contains(w)) {
      items.add('${YakuId.yakuhaiSeatWind.name}:1');
    } else {
      items.add('${YakuId.yakuhaiRoundWind.name}:1');
    }
  }
  return items..sort();
}

List<String> _actualYaku(WinResult r) {
  final items = [for (final y in r.yaku) '${y.id.name}:${y.han}'];
  if (!r.isYakuman) {
    if (r.doraCount > 0) items.add('${YakuId.dora.name}:${r.doraCount}');
    if (r.akaDoraCount > 0) {
      items.add('${YakuId.akaDora.name}:${r.akaDoraCount}');
    }
    if (r.uraDoraCount > 0) {
      items.add('${YakuId.uraDora.name}:${r.uraDoraCount}');
    }
  }
  return items..sort();
}

/// 期待値との違い（なければ null）。
String? _compare(_Case c, WinOutcome outcome) {
  final exp = c.expected;
  if (exp.startsWith('E:')) {
    final want = _pyErrors[exp.substring(2)];
    if (want == null) return '未対応のエラー $exp';
    if (outcome is WinRejected && outcome.error == want) return null;
    return '期待 ${want.name} / 実際 ${_describe(outcome)}';
  }
  if (outcome is! WinScored) {
    return '期待 $exp / 実際 ${_describe(outcome)}';
  }
  return _diffResult(c, outcome.best);
}

/// 期待値（成功）と 1 つの解釈との違い（なければ null）。
String? _diffResult(_Case c, WinResult r) {
  final f = c.expected.split(',');
  final han = int.parse(f[0]);
  final fu = int.parse(f[1]);
  final level = f[2];
  final main = int.parse(f[3]);
  final mainBonus = int.parse(f[4]);
  final additional = int.parse(f[5]);
  final additionalBonus = int.parse(f[6]);
  final kyotaku = int.parse(f[7]);
  final total = int.parse(f[8]);
  final diffs = <String>[];
  if (r.han != han) diffs.add('翻 $han≠${r.han}');
  if (r.fu != fu) diffs.add('符 $fu≠${r.fu}');
  final ey = _expectedYaku(f[9]);
  final ay = _actualYaku(r);
  if (ey.join(' ') != ay.join(' ')) {
    diffs.add('役 [${ey.join(' ')}]≠[${ay.join(' ')}]');
  }
  final p = r.payment;
  final req = c.request;
  final int aMain;
  final int aMainBonus;
  final int aAdd;
  final int aAddBonus;
  if (req.winType == WinType.ron) {
    aMain = p.ronBase;
    aMainBonus = p.ron - p.ronBase;
    aAdd = 0;
    aAddBonus = 0;
  } else if (req.isDealer) {
    aMain = p.tsumoFromChildBase;
    aMainBonus = p.tsumoFromChild - p.tsumoFromChildBase;
    aAdd = p.tsumoFromChildBase;
    aAddBonus = aMainBonus;
  } else {
    aMain = p.tsumoFromDealerBase;
    aMainBonus = p.tsumoFromDealer - p.tsumoFromDealerBase;
    aAdd = p.tsumoFromChildBase;
    aAddBonus = p.tsumoFromChild - p.tsumoFromChildBase;
  }
  if (aMain != main ||
      aMainBonus != mainBonus ||
      aAdd != additional ||
      aAddBonus != additionalBonus ||
      p.kyotakuPoints != kyotaku ||
      p.total != total) {
    diffs.add(
      '支払い $main/$mainBonus/$additional/$additionalBonus/$kyotaku/$total'
      '≠$aMain/$aMainBonus/$aAdd/$aAddBonus/${p.kyotakuPoints}/${p.total}',
    );
  }
  final wantLevel = _pyLevels[r.rank]!;
  if (wantLevel != level && !_levelException(c, r, level)) {
    diffs.add('段階 $level≠${r.rank.name}');
  }
  return diffs.isEmpty ? null : diffs.join(' / ');
}

/// 参照実装の yaku_level の既知の違い（点数は同じ）。
bool _levelException(_Case c, WinResult r, String level) {
  final rules = _profiles[c.profile]!;
  // 切り上げ満貫ありのとき、5 翻未満の満貫は yaku_level が空になる
  // （scores.py の `elif rounded > 2000` が `if config.options.kiriage` に掛かっている）。
  if (rules.kiriageMangan && r.han < 5 && r.rank == HandRank.mangan) {
    if (level == '-' || level == 'kiriage_mangan') return true;
  }
  return false;
}

String _describe(WinOutcome o) => switch (o) {
  WinRejected(:final error) => 'E:${error.name}',
  WinScored(:final best) =>
    '${best.han}翻${best.fu}符 ${best.yaku.map((y) => y.id.name).join('+')}',
};

/// 例外として認める違い（理由はフィクスチャの照合結果と一緒に報告する）。
///
/// kazoeOverYakuman: 同じ基本点（8000）になる解釈が「役満」と「数え役満（役満でない役＋ドラで
/// 13 翻以上）」の両方にあるとき、参照実装は翻の多い数え役満を、こちらは役満を選ぶ。点数・支払いは
/// 同じで、参照実装が選んだ解釈はこちらの次善の解釈（alternatives）に入っていることも確かめる。
String? _exception(_Case c, WinOutcome outcome) {
  if (outcome is! WinScored || c.expected.startsWith('E:')) return null;
  final best = outcome.best;
  final f = c.expected.split(',');
  final pyHan = int.parse(f[0]);
  final pyHasYakuman = f[9]
      .split('+')
      .where((e) => e.isNotEmpty)
      .any(
        (e) =>
            int.parse(e.split(':')[0]) >= 100 &&
            int.parse(e.split(':')[0]) < 120,
      );
  if (best.isYakuman &&
      best.yakumanMultiplier == 1 &&
      !pyHasYakuman &&
      pyHan >= 13 &&
      _profiles[c.profile]!.countedYakuman &&
      outcome.alternatives.any((alt) => _diffResult(c, alt) == null)) {
    return 'kazoeOverYakuman';
  }
  return null;
}

void main() {
  final cases = _loadCases();

  test('フィクスチャが読める（20,000 件以上）', () {
    expect(cases.length, greaterThanOrEqualTo(20000));
  });

  test('Python mahjong==2.0.0 と全件一致する（例外は理由つきで数える）', () {
    final scorers = {
      for (final e in _profiles.entries) e.key: WinScorer(e.value),
    };
    final failures = <String>[];
    final exceptions = <String, List<int>>{};
    for (final c in cases) {
      final outcome = scorers[c.profile]!.score(c.request);
      final diff = _compare(c, outcome);
      if (diff == null) continue;
      final reason = _exception(c, outcome);
      if (reason != null) {
        exceptions.putIfAbsent(reason, () => []).add(c.lineNo);
        continue;
      }
      failures.add('行${c.lineNo}: ${c.line}\n    $diff');
    }
    // ignore: avoid_print
    print(
      '照合 ${cases.length} 件 / 不一致 ${failures.length} 件 / 例外 '
      '${exceptions.entries.map((e) => '${e.key}=${e.value.length}（行 ${e.value.take(10).join(',')}）').join(' ')}',
    );
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print(failures.take(40).join('\n'));
    }
    expect(failures, isEmpty, reason: '${failures.length} 件不一致');
    // 例外は数が少ないことも確かめる（生成を変えて増えたら理由を調べ直す）。
    final exceptionCount = exceptions.values.fold<int>(
      0,
      (a, b) => a + b.length,
    );
    expect(exceptionCount, lessThanOrEqualTo(cases.length ~/ 1000));
  });
}

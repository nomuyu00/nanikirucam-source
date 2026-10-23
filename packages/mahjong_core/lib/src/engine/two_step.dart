/// 2 段階先（設計書 4.5、Pro）。
///
/// 候補の打牌後の 13 枚について、引く牌ごとに「引いてから最良の打牌をした後の受け入れ
/// 枚数」を求める。最良の打牌は速さの順（シャンテン数 ↑ → 受け入れ枚数 ↓）。
///
/// - 受け入れ（引くとシャンテン数が進む牌）: 進んだ後の受け入れ枚数を、引く牌の残り
///   枚数で重み付け平均したものが [TwoStep.average]（仕様 4.2「受け入れを引いた後の
///   受け入れ平均」）。テンパイの候補は受け入れ＝和了なので null。
/// - 改良（進まないが、打牌を選べば受け入れが増える牌）: [TwoStep.draws] に
///   `progress = false` で入れる。平均には入れない（進んだ後の受け入れと、進む前の
///   受け入れの増えた枚数は比べられる量ではないため。設計書 4.5 との違い）。
///   テンパイの候補では「待ちが増える牌」。
///
/// 残り枚数は [HandState.discard] と同じく、切った牌を見えている牌に移して数える
/// （引いた牌は手に入るので、その牌の残りは 1 減る）。
library;

import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';

/// 2 段階先の、引く牌 1 つ分。
class TwoStepDraw extends Equatable {
  /// 引く牌。
  final int tileId;

  /// 引く牌の残り枚数（平均の重み）。
  final int remaining;

  /// true は受け入れ（シャンテン数が進む）、false は改良。
  final bool progress;

  /// 引いた後の最良の打牌（同じ受け入れ枚数ならすべて、牌 id の昇順）。
  final List<int> discards;

  /// その打牌後のシャンテン数。
  final int shantenAfter;

  /// その打牌後の受け入れ枚数。
  final int ukeireAfter;

  TwoStepDraw({
    required this.tileId,
    required this.remaining,
    required this.progress,
    required List<int> discards,
    required this.shantenAfter,
    required this.ukeireAfter,
  }) : discards = List.unmodifiable(discards);

  @override
  List<Object?> get props => [
    tileId,
    remaining,
    progress,
    discards,
    shantenAfter,
    ukeireAfter,
  ];

  @override
  String toString() =>
      'TwoStepDraw($tileId x$remaining ${progress ? '進む' : '改良'} '
      '打$discards → $shantenAfter向聴 $ukeireAfter枚)';
}

/// 候補 1 つの 2 段階先。
class TwoStep extends Equatable {
  /// 受け入れを引いた後の受け入れ枚数の、残り枚数で重み付けした平均。テンパイの
  /// 候補と、受け入れが残っていない候補は null。
  final double? average;

  /// 受け入れと改良の牌（牌 id の昇順）。テンパイの候補は改良だけ。
  final List<TwoStepDraw> draws;

  TwoStep({required this.average, required List<TwoStepDraw> draws})
    : draws = List.unmodifiable(draws);

  /// 改良の牌と残り枚数（[Ukeire] の形で返す。中身は「進まないが受け入れが増える牌」）。
  Ukeire get improvement => Ukeire({
    for (final d in draws)
      if (!d.progress) d.tileId: d.remaining,
  });

  @override
  List<Object?> get props => [average, draws];
}

/// 14 枚の手の各候補の 2 段階先を計算する。打牌の組（切る牌 2 枚と引く牌 1 枚）ごとの
/// シャンテン数と受け入れ枚数を、候補をまたいでメモする。
class TwoStepCalculator {
  final HandState hand;
  final int _meldCount;
  final List<int> _counts;
  final List<int> _visible;
  final List<int> _meldTiles;

  // 添字 (lo * 34 + hi) * 34 + t。lo・hi は切る 2 枚（順不同）、t は引く牌。
  final Int8List _shanten13 = Int8List(kTileKinds * kTileKinds * kTileKinds)
    ..fillRange(0, kTileKinds * kTileKinds * kTileKinds, -9);
  final Int16List _ukeire13 = Int16List(kTileKinds * kTileKinds * kTileKinds)
    ..fillRange(0, kTileKinds * kTileKinds * kTileKinds, -1);

  TwoStepCalculator(this.hand)
    : _meldCount = hand.meldCount,
      _counts = List<int>.of(hand.counts),
      _visible = List<int>.of(hand.visible),
      _meldTiles = [
        for (var i = 0; i < kTileKinds; i++) hand.meldTileCount(i),
      ] {
    if (hand.tileCount != 14) {
      throw ArgumentError.value(hand.tileCount, 'hand', '14 枚（副露込み）の手ではない');
    }
  }

  /// [discardId] を切った候補の 2 段階先。
  TwoStep of(int discardId) {
    final d = discardId;
    if (d < 0 || d >= kTileKinds || hand.counts[d] == 0) {
      throw ArgumentError.value(d, 'discardId', '手牌にない牌は切れない');
    }
    final c = _counts;
    final v = _visible;
    c[d]--;
    v[d]++;
    try {
      final s = _shanten(c);
      final base = _ukeireTotal(c, v, s);
      final draws = <TwoStepDraw>[];
      var weight = 0;
      var sum = 0;
      for (var t = 0; t < kTileKinds; t++) {
        if (c[t] >= 4) continue;
        final r = 4 - c[t] - _meldTiles[t] - v[t];
        if (r <= 0) continue;
        c[t]++;
        final s14 = _shanten(c);
        TwoStepDraw? entry;
        if (s14 < s) {
          // 受け入れ。テンパイからの受け入れは和了なので数えない。
          if (s >= 1) {
            entry = _bestAfter(d, t, s14, r, progress: true);
            weight += r;
            sum += r * entry.ukeireAfter;
          }
        } else {
          final e = _bestAfter(d, t, s, r, progress: false);
          if (e.ukeireAfter > base) entry = e;
        }
        c[t]--;
        if (entry != null) draws.add(entry);
      }
      return TwoStep(average: weight == 0 ? null : sum / weight, draws: draws);
    } finally {
      c[d]++;
      v[d]--;
    }
  }

  /// 引いた後の 14 枚（[_counts] は d を切って t を引いた状態）から、シャンテン数が
  /// [target] になる打牌のうち受け入れ最大のもの。
  TwoStepDraw _bestAfter(
    int d,
    int t,
    int target,
    int remaining, {
    required bool progress,
  }) {
    final c = _counts;
    final v = _visible;
    var best = -1;
    final discards = <int>[];
    for (var d2 = 0; d2 < kTileKinds; d2++) {
      if (c[d2] == 0) continue;
      final key = _key(d, d2, t);
      c[d2]--;
      v[d2]++;
      var s2 = _shanten13[key];
      if (s2 == -9) {
        s2 = _shanten(c);
        _shanten13[key] = s2;
      }
      if (s2 == target) {
        var u = _ukeire13[key];
        if (u < 0) {
          u = _ukeireTotal(c, v, s2);
          _ukeire13[key] = u;
        }
        if (u > best) {
          best = u;
          discards
            ..clear()
            ..add(d2);
        } else if (u == best) {
          discards.add(d2);
        }
      }
      c[d2]++;
      v[d2]--;
    }
    return TwoStepDraw(
      tileId: t,
      remaining: remaining,
      progress: progress,
      discards: discards,
      shantenAfter: target,
      ukeireAfter: best < 0 ? 0 : best,
    );
  }

  static int _key(int a, int b, int t) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return (lo * kTileKinds + hi) * kTileKinds + t;
  }

  int _shanten(List<int> counts) =>
      shantenFromCounts(counts, meldCount: _meldCount).shanten;

  /// 13 枚（[counts]、シャンテン数 [s0]）の受け入れ枚数（`ukeire` と同じ数え方）。
  int _ukeireTotal(List<int> counts, List<int> visible, int s0) {
    var total = 0;
    for (var id = 0; id < kTileKinds; id++) {
      if (counts[id] >= 4) continue;
      final left = 4 - counts[id] - _meldTiles[id] - visible[id];
      if (left <= 0) continue;
      counts[id]++;
      final s = _shanten(counts);
      counts[id]--;
      if (s < s0) total += left;
    }
    return total;
  }
}

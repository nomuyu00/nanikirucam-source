import 'dart:collection';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';

/// シャンテン数を出した形。同値なら standard → sevenPairs → kokushi の順に優先する。
enum ShantenType { standard, sevenPairs, kokushi }

class ShantenResult extends Equatable {
  /// -1=和了, 0=テンパイ, 1=一向聴 …
  final int shanten;
  final ShantenType type;
  const ShantenResult({required this.shanten, required this.type});

  @override
  List<Object?> get props => [shanten, type];

  @override
  String toString() => 'ShantenResult($shanten, ${type.name})';
}

/// 手牌（副露を除く）と副露数から総合のシャンテン数を求める。
/// 副露があれば一般形だけ、門前なら七対子・国士も比べる。
ShantenResult shantenFromCounts(List<int> counts, {int meldCount = 0}) {
  final standard = standardShanten(counts, meldCount);
  if (meldCount > 0) {
    return ShantenResult(shanten: standard, type: ShantenType.standard);
  }
  var best = standard;
  var type = ShantenType.standard;
  final pairs = sevenPairsShanten(counts);
  if (pairs < best) {
    best = pairs;
    type = ShantenType.sevenPairs;
  }
  final kokushi = kokushiShanten(counts);
  if (kokushi < best) {
    best = kokushi;
    type = ShantenType.kokushi;
  }
  return ShantenResult(shanten: best, type: type);
}

/// [HandState] の総合シャンテン数。
ShantenResult shanten(HandState hand) =>
    shantenFromCounts(hand.counts, meldCount: hand.meldCount);

/// 一般形（4 面子 1 雀頭）のシャンテン数。
///
/// [counts] は副露を除いた手牌（長さ 34）、[meldCount] は副露（暗槓を含む）の数。
/// 手牌 + 3×副露数 は 13 か 14 であること。
///
/// 「和了形にするために入れ替える牌の最小枚数 − 1」を厳密に求める。
/// 値は設計書 4.3 の `8 − 2m − t − h`（m + t ≤ 4）の最小と同じだが、目標の和了形は
/// 各牌 4 枚までなので、手の中に 4 枚ある牌の単騎待ちのような「5 枚目が要る」形は
/// テンパイと数えない（`mahjong` ライブラリと同じ扱い。例: 1111m234p567p789p は 1）。
/// 面子・雀頭は色をまたがないので、色ごとに「k 面子 + p 雀頭を作るのに足りない枚数」
/// を求めて counts（5 進数）でメモ化し、色を組み合わせて最小を取る。
int standardShanten(List<int> counts, int meldCount) {
  if (counts.length != kTileKinds) {
    throw ArgumentError.value(counts.length, 'counts', '長さは 34');
  }
  if (meldCount < 0 || meldCount > 4) {
    throw ArgumentError.value(meldCount, 'meldCount', '0〜4');
  }
  var total = 0;
  for (var i = 0; i < kTileKinds; i++) {
    final c = counts[i];
    if (c < 0 || c > 4) {
      throw ArgumentError('牌 $i の枚数 $c は 0〜4 ではない');
    }
    total += c;
  }
  final tiles = total + 3 * meldCount;
  if (tiles != 13 && tiles != 14) {
    throw ArgumentError('手牌 $total 枚 + 副露 $meldCount 個は 13/14 枚ではない');
  }

  final need = 4 - meldCount;
  final man = _suitDistances(counts, 0);
  final pin = _suitDistances(counts, 9);
  final sou = _suitDistances(counts, 18);
  final honor = _suitDistances(counts, 27);

  // 2 色ずつ合成し、最後は必要な (need 面子, 1 雀頭) だけ求める。
  _combine(man, pin, _accA, need);
  _combine(_accA, sou, _accB, need);
  var best = _inf;
  for (var k1 = 0; k1 <= need; k1++) {
    final k2 = need - k1;
    // 雀頭が既に合成側にある / 字牌側にある
    final a0 = _accB[k1 * 2 + 1] + honor[k2 * 2];
    if (a0 < best) best = a0;
    final a1 = _accB[k1 * 2] + honor[k2 * 2 + 1];
    if (a1 < best) best = a1;
  }
  return best - 1;
}

/// 七対子のシャンテン数。同種 4 枚は対子 1 つとだけ数え、種類が 7 未満なら不足分を足す。
int sevenPairsShanten(List<int> counts) {
  var pairs = 0;
  var kinds = 0;
  for (var i = 0; i < kTileKinds; i++) {
    final c = counts[i];
    if (c >= 1) kinds++;
    if (c >= 2) pairs++;
  }
  if (pairs >= 7) return -1;
  return 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
}

const List<int> _yaochuIds = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];

/// 国士無双のシャンテン数。
int kokushiShanten(List<int> counts) {
  var kinds = 0;
  var hasPair = false;
  for (final id in _yaochuIds) {
    final c = counts[id];
    if (c >= 1) kinds++;
    if (c >= 2) hasPair = true;
  }
  return 13 - kinds - (hasPair ? 1 : 0);
}

/// 色ごとのメモをすべて捨てる（ベンチ用）。
void clearShantenCache() {
  _numberCache.clear();
  _honorCache.clear();
}

const int _inf = 99;
// 1 件 100 バイト前後。超えたら丸ごと捨てる（計算し直しても 1 色 10 µs 前後）。
const int _cacheLimit = 50000;

final HashMap<int, Int8List> _numberCache = HashMap<int, Int8List>();
final HashMap<int, Int8List> _honorCache = HashMap<int, Int8List>();
final Int32List _accA = Int32List(10);
final Int32List _accB = Int32List(10);

/// [base] から始まる 1 色（字牌は 7 種）の「k 面子 + p 雀頭」に足りない枚数。
/// 返り値の添字は k*2+p（k=0..4, p=0..1）。
Int8List _suitDistances(List<int> counts, int base) {
  final honors = base == 27;
  final len = honors ? 7 : 9;
  var key = 0;
  for (var i = len - 1; i >= 0; i--) {
    key = key * 5 + counts[base + i];
  }
  final cache = honors ? _honorCache : _numberCache;
  final cached = cache[key];
  if (cached != null) return cached;
  if (cache.length >= _cacheLimit) cache.clear();
  final result = _computeSuit(counts, base, len, !honors);
  cache[key] = result;
  return result;
}

// 状態 (c1=1 つ前から始まる順子数, c2=2 つ前から始まる順子数, k=面子数, p=雀頭数)
// の添字。順子は 1 か所に 4 つまでなので c1+c2 ≤ 4。
int _stateIndex(int c1, int c2, int k, int p) =>
    ((c1 * 5 + c2) * 5 + k) * 2 + p;

const int _stateSize = 250;

/// 位置ごとに「ここから始まる順子の数・刻子の有無・雀頭の有無」を選ぶ DP。
/// 位置 i で目標が使う枚数 = c1 + c2 + 新しい順子 + 3×刻子 + 2×雀頭（4 以下）で、
/// 手牌より多く使う分が足りない枚数になる。
Int8List _computeSuit(List<int> counts, int base, int len, bool sequences) {
  var cur = Int8List(_stateSize)..fillRange(0, _stateSize, _inf);
  var next = Int8List(_stateSize);
  cur[0] = 0;
  for (var i = 0; i < len; i++) {
    next.fillRange(0, _stateSize, _inf);
    final have = counts[base + i];
    final maxStart = sequences && i <= len - 3 ? 4 : 0;
    for (var c1 = 0; c1 <= 4; c1++) {
      for (var c2 = 0; c1 + c2 <= 4; c2++) {
        final carry = c1 + c2;
        for (var k = 0; k <= 4; k++) {
          for (var p = 0; p <= 1; p++) {
            final cost = cur[_stateIndex(c1, c2, k, p)];
            if (cost >= _inf) continue;
            for (
              var a = 0;
              a <= maxStart && carry + a <= 4 && k + a <= 4;
              a++
            ) {
              for (var t = 0; t <= 1 && k + a + t <= 4; t++) {
                for (var q = 0; p + q <= 1; q++) {
                  final use = carry + a + 3 * t + 2 * q;
                  if (use > 4) break;
                  final value = cost + (use > have ? use - have : 0);
                  final idx = _stateIndex(a, c1, k + a + t, p + q);
                  if (value < next[idx]) next[idx] = value;
                }
              }
            }
          }
        }
      }
    }
    final swap = cur;
    cur = next;
    next = swap;
  }
  final result = Int8List(10);
  for (var k = 0; k <= 4; k++) {
    for (var p = 0; p <= 1; p++) {
      result[k * 2 + p] = cur[_stateIndex(0, 0, k, p)];
    }
  }
  return result;
}

/// a と b を合成して out に入れる（面子は need まで、雀頭は 1 つまで）。
void _combine(List<int> a, List<int> b, Int32List out, int need) {
  out.fillRange(0, 10, _inf);
  for (var k1 = 0; k1 <= need; k1++) {
    for (var p1 = 0; p1 <= 1; p1++) {
      final x = a[k1 * 2 + p1];
      if (x >= _inf) continue;
      for (var k2 = 0; k1 + k2 <= need; k2++) {
        for (var p2 = 0; p1 + p2 <= 1; p2++) {
          final y = b[k2 * 2 + p2];
          if (y >= _inf) continue;
          final idx = (k1 + k2) * 2 + p1 + p2;
          final v = x + y;
          if (v < out[idx]) out[idx] = v;
        }
      }
    }
  }
}

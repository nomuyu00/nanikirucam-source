import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/analysis_report.dart';
import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/nanikiru_engine.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/tile_utils.dart';

/// 今日の問題（1 日 3 問）を、サーバーなしで端末内だけで作る生成器。
///
/// 同じ日付（JST の `YYYY-MM-DD`）と問題番号からは、どの端末でも何度でも同じ手になる。
/// `dart:math` の `Random` は実装（版や VM）で列が変わり得るので使わず、日付文字列の
/// FNV-1a（32 bit）でシードを作り、自前の xoshiro128** で乱数を引く。
///
/// 手の作り方（実戦らしい手にする）:
/// 1. 136 枚の山（赤5は萬・筒・索に 1 枚ずつ。アプリの既定ルール = 赤あり）を混ぜる。
/// 2. 13 枚配り、4〜9 巡（乱数）「ツモ → 打牌」を繰り返す。打牌は高速な方針で、
///    シャンテン数が最小になる牌のうち受け入れ枚数（自分の手だけで数える）が最大の牌
///    （同じなら乱数で 1 つ。赤5と通常の5があれば通常の5を切る）。
/// 3. 最後に 1 枚ツモって 14 枚（ツモ牌は末尾、ほかは理牌）。ドラ表示牌は王牌から 1 枚、
///    場風（東・南）と自風は乱数。巡目は「最後のツモ」の巡（5〜10）。
/// 4. エンジン（[NanikiruEngine.analyze]、無料モード・既定ルール）で解析し、難易度ごとの
///    条件（[DailyLevel]）に合う手が出るまで 2〜3 を繰り返す。試行回数に上限があり、
///    見つからなければ条件を段階的に緩める（[DailyHand.stage]）ので、必ず手を返す。
///
/// 結果は生成器の手順だけでなく、エンジンの解析結果（[kEngineVersion]）にも依存する。
/// エンジンの版が違うアプリ同士では、同じ日でも別の問題になることがある。
///
/// **版数**: 山・乱数・打牌の方針・選別の条件・試行回数など、同じ日付から出る手が変わる
/// 変更をしたら [kDailyGeneratorVersion] を 1 上げる（版はシードに含まれる）。
const int kDailyGeneratorVersion = 1;

/// 1 日の問題数。
const int kDailyProblemCount = 3;

/// 今日の問題の難易度（問題番号 1〜3 の順）。
enum DailyLevel {
  /// 1 問目「基本」: 1〜2 シャンテンで、3 軸の解が同じ 1 枚、しかも受け入れの差がはっきり。
  basic,

  /// 2 問目「標準」: 1〜2 シャンテンで、3 軸の解は同じだが、候補の受け入れが拮抗している。
  standard,

  /// 3 問目「応用」: 3 軸（速さ・打点・バランス）の最善の打牌が一致しない手。
  advanced;

  /// 問題番号（1〜3）の難易度。
  static DailyLevel ofNumber(int number) => DailyLevel.values[number - 1];
}

/// 生成した 1 問。
class DailyHand extends Equatable {
  const DailyHand({
    required this.date,
    required this.number,
    required this.level,
    required this.tiles,
    required this.doraIndicator,
    required this.seatWind,
    required this.roundWind,
    required this.turn,
    required this.shanten,
    required this.split,
    required this.stage,
    required this.attempts,
  });

  /// JST の `YYYY-MM-DD`。
  final String date;

  /// 1〜[kDailyProblemCount]。
  final int number;
  final DailyLevel level;

  /// 14 枚の牌ラベル（`1m`〜`7z`、赤5は `0m` `0p` `0s`）。先頭 13 枚は理牌済み、末尾がツモ牌。
  final List<String> tiles;

  /// ドラ表示牌（1 枚）。
  final String doraIndicator;
  final Wind seatWind;
  final Wind roundWind;

  /// 巡目（5〜10）。
  final int turn;

  /// 14 枚のシャンテン数（最善の打牌の後のシャンテン数と同じ。0 以上）。
  final int shanten;

  /// 既定ルールのエンジンで、3 軸の最善の打牌が割れたか。
  final bool split;

  /// 採用した条件の段階。0 が難易度どおり、数が大きいほど緩めた条件（最大 3）。
  final int stage;

  /// 作った手の数（1 から。条件に合わず捨てた手を含む）。
  final int attempts;

  /// 親か（自風が東）。
  bool get dealer => seatWind == Wind.east;

  /// ツモ牌の添字（末尾）。
  int get tsumoIndex => tiles.length - 1;

  /// 解析エンジンの入力（アプリの `HandInput.toHandState` と同じ組み立て方）。
  HandState toHandState() => _handStateOf(
    tiles,
    doraIndicator: doraIndicator,
    seatWind: seatWind,
    roundWind: roundWind,
    turn: turn,
  );

  @override
  List<Object?> get props => [
    date,
    number,
    level,
    tiles,
    doraIndicator,
    seatWind,
    roundWind,
    turn,
    shanten,
    split,
    stage,
    attempts,
  ];

  @override
  String toString() =>
      'DailyHand($date#$number ${level.name} ${tiles.join(' ')} '
      'ドラ表示=$doraIndicator 場=${roundWind.name} 自=${seatWind.name} '
      '$turn巡目 $shanten向聴 split=$split stage=$stage attempts=$attempts)';
}

/// 今日の問題の生成器。重い（数十〜数百 ms）ので、アプリでは Isolate で呼ぶ。
class DailyProblemGenerator {
  DailyProblemGenerator({NanikiruEngine? engine})
    : _engine = engine ?? DefaultNanikiruEngine(cacheSize: 4);

  final NanikiruEngine _engine;

  /// 段階ごとの試行回数の上限（段階 0〜3）。合計を超えたら最後の手（和了形でないもの）を返す。
  static const List<int> attemptsPerStage = [40, 30, 20, 10];

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// [date] の 3 問（問題番号 1〜3 = 基本・標準・応用）。
  List<DailyHand> generate(String date) => [
    for (var n = 1; n <= kDailyProblemCount; n++) generateOne(date, n),
  ];

  /// [date] の [number] 問目（1〜[kDailyProblemCount]）。ほかの問題とは独立に作るので、
  /// 1 問だけ作り直せる。
  DailyHand generateOne(String date, int number) {
    if (!_datePattern.hasMatch(date)) {
      throw ArgumentError.value(date, 'date', 'YYYY-MM-DD ではない');
    }
    if (number < 1 || number > kDailyProblemCount) {
      throw RangeError.range(number, 1, kDailyProblemCount, 'number');
    }
    final level = DailyLevel.ofNumber(number);
    final rng = DailyRandom.fromString(
      'nanikiru-daily|v$kDailyGeneratorVersion|$date|$number',
    );
    var attempts = 0;
    _Dealt? lastPlayable;
    for (var stage = 0; stage < attemptsPerStage.length; stage++) {
      for (var i = 0; i < attemptsPerStage[stage]; i++) {
        attempts++;
        final dealt = _deal(rng);
        if (dealt.shanten < 0) continue; // 和了形は問題にならない。
        lastPlayable = dealt;
        if (!_shantenFits(level, stage, dealt.shanten)) continue;
        final hand = dealt.toHandState();
        final report = _engine.analyze(hand, deep: false);
        final verdict = _judge(level, stage, report);
        if (verdict == null) continue;
        return dealt.toDailyHand(
          date: date,
          number: number,
          level: level,
          split: verdict,
          stage: stage,
          attempts: attempts,
        );
      }
    }
    // ここに来るのは極めてまれ（和了形しか出ない列）。最後の手、それも無ければ固定の手。
    final fallback = lastPlayable ?? _Dealt.fixed;
    final report = _engine.analyze(fallback.toHandState(), deep: false);
    return fallback.toDailyHand(
      date: date,
      number: number,
      level: level,
      split: _isSplit(report),
      stage: attemptsPerStage.length - 1,
      attempts: attempts,
    );
  }

  // --- 手を作る ---------------------------------------------------------------

  static const _redFiveIds = {4, 13, 22};

  /// 山を混ぜて配り、数巡打ってから最後の 1 枚をツモる。
  static _Dealt _deal(DailyRandom rng) {
    // 牌の符号 = id * 4 + 何枚目か。赤5は 5m・5p・5s の 0 枚目。
    final wall = List<int>.generate(136, (i) => i);
    for (var i = wall.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = wall[i];
      wall[i] = wall[j];
      wall[j] = t;
    }
    // 王牌は末尾 14 枚。ドラ表示牌はその中の 1 枚。
    final doraIndicator = _labelOf(wall[wall.length - 5]);
    var next = 0;
    final hand = <int>[for (var i = 0; i < 13; i++) wall[next++]];
    final turns = 4 + rng.nextInt(6); // 4〜9 巡
    final counts = List<int>.filled(kTileKinds, 0);
    for (final code in hand) {
      counts[code >> 2]++;
    }
    for (var t = 0; t < turns; t++) {
      final drawn = wall[next++];
      hand.add(drawn);
      counts[drawn >> 2]++;
      final discardId = _chooseDiscard(counts, rng);
      // 同じ牌が複数あれば赤5を残す（通常の 5 を切る）。
      var index = -1;
      for (var k = 0; k < hand.length; k++) {
        if (hand[k] >> 2 != discardId) continue;
        if (index < 0 || _isRed(hand[index])) index = k;
      }
      hand.removeAt(index);
      counts[discardId]--;
    }
    final tsumo = wall[next++];
    hand.sort();
    counts[tsumo >> 2]++;
    final roundWind = rng.nextInt(2) == 0 ? Wind.east : Wind.south;
    final seatWind = Wind.values[rng.nextInt(4)];
    return _Dealt(
      tiles: [for (final code in hand) _labelOf(code), _labelOf(tsumo)],
      doraIndicator: doraIndicator,
      seatWind: seatWind,
      roundWind: roundWind,
      turn: turns + 1,
      shanten: shantenFromCounts(counts).shanten,
    );
  }

  /// 14 枚の [counts] から切る牌: シャンテン数が最小、その中で受け入れ枚数が最大。
  static int _chooseDiscard(List<int> counts, DailyRandom rng) {
    var bestShanten = 99;
    final byShanten = <int>[];
    final shantenOf = List<int>.filled(kTileKinds, 99);
    for (var id = 0; id < kTileKinds; id++) {
      if (counts[id] == 0) continue;
      counts[id]--;
      final s = shantenFromCounts(counts).shanten;
      counts[id]++;
      shantenOf[id] = s;
      if (s < bestShanten) bestShanten = s;
    }
    for (var id = 0; id < kTileKinds; id++) {
      if (shantenOf[id] == bestShanten) byShanten.add(id);
    }
    if (byShanten.length == 1) return byShanten.first;
    var bestUkeire = -1;
    final best = <int>[];
    for (final id in byShanten) {
      counts[id]--;
      var total = 0;
      for (var k = 0; k < kTileKinds; k++) {
        if (counts[k] >= 4) continue;
        counts[k]++;
        final s = shantenFromCounts(counts).shanten;
        counts[k]--;
        // 残り枚数は自分の手だけで数える（切った牌も含め、河は見ない）。
        if (s < bestShanten) total += 4 - counts[k];
      }
      counts[id]++;
      if (total > bestUkeire) {
        bestUkeire = total;
        best
          ..clear()
          ..add(id);
      } else if (total == bestUkeire) {
        best.add(id);
      }
    }
    return best.length == 1 ? best.first : best[rng.nextInt(best.length)];
  }

  static bool _isRed(int code) =>
      code & 3 == 0 && _redFiveIds.contains(code >> 2);

  static String _labelOf(int code) {
    final id = code >> 2;
    if (id >= 27) return '${id - 26}z';
    final suit = const ['m', 'p', 's'][id ~/ 9];
    if (_isRed(code)) return '0$suit';
    return '${id % 9 + 1}$suit';
  }

  // --- 選別 -------------------------------------------------------------------

  /// 解析の前に、14 枚のシャンテン数だけで落とす（エンジンを呼ぶ回数を減らす）。
  static bool _shantenFits(DailyLevel level, int stage, int shanten) {
    switch (stage) {
      case 0:
        return level == DailyLevel.advanced
            ? shanten >= 0 && shanten <= 2
            : shanten >= 1 && shanten <= 2;
      case 1:
        return shanten >= 0 && shanten <= 3;
      default:
        return shanten >= 0;
    }
  }

  /// 条件に合えば 3 軸が割れたか（true/false）、合わなければ null。
  static bool? _judge(DailyLevel level, int stage, AnalysisReport report) {
    final candidates = report.candidates;
    if (candidates.isEmpty || report.shanten.shanten < 0) return null;
    final split = _isSplit(report);
    if (stage >= 3) return split;
    final bestShanten = candidates
        .map((c) => c.shantenAfter)
        .reduce((a, b) => a < b ? a : b);
    final keep = [
      for (final c in candidates)
        if (c.shantenAfter == bestShanten) c,
    ];
    final balance = report.bestByAxis[StrategyAxis.balance] ?? const [];
    // 選ぶ余地がない手・候補がみな同じ評価の手は問題にならない。
    if (keep.length < 2 || balance.isEmpty || balance.length >= keep.length) {
      return null;
    }
    if (stage == 2) return split;

    final maxTie = StrategyAxis.values
        .map((a) => report.bestByAxis[a]?.length ?? 0)
        .reduce((a, b) => a > b ? a : b);
    switch (level) {
      case DailyLevel.advanced:
        if (!split) return null;
        if (stage == 0 && maxTie > 2) return null;
        return true;
      case DailyLevel.basic:
      case DailyLevel.standard:
        if (split || maxTie > 2) return null;
        final margin = _ukeireMargin(keep, balance);
        if (level == DailyLevel.basic) {
          if (balance.length != 1) return null;
          return margin >= (stage == 0 ? 4 : 2) ? false : null;
        }
        if (stage == 0 && (keep.length < 3 || margin >= 4)) return null;
        return false;
    }
  }

  /// 解（[best]）の受け入れ枚数と、それ以外で同じシャンテン数を保つ候補の最大との差。
  static int _ukeireMargin(List<DiscardCandidate> keep, List<int> best) {
    var bestTotal = 0;
    var otherTotal = 0;
    for (final c in keep) {
      if (best.contains(c.discardId)) {
        if (c.ukeire.total > bestTotal) bestTotal = c.ukeire.total;
      } else if (c.ukeire.total > otherTotal) {
        otherTotal = c.ukeire.total;
      }
    }
    return bestTotal - otherTotal;
  }

  static bool _isSplit(AnalysisReport report) {
    if (report.candidates.isEmpty) return false;
    Set<int> setOf(StrategyAxis axis) =>
        (report.bestByAxis[axis] ?? const <int>[]).toSet();
    final first = setOf(StrategyAxis.speed);
    for (final axis in StrategyAxis.values) {
      final s = setOf(axis);
      if (s.length != first.length || !s.containsAll(first)) return true;
    }
    return false;
  }
}

class _Dealt {
  const _Dealt({
    required this.tiles,
    required this.doraIndicator,
    required this.seatWind,
    required this.roundWind,
    required this.turn,
    required this.shanten,
  });

  /// どうしても手が見つからないときの固定の手（一向聴）。
  static const fixed = _Dealt(
    tiles: [
      '1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', //
      '2z', '2z', '9p',
    ],
    doraIndicator: '3z',
    seatWind: Wind.south,
    roundWind: Wind.east,
    turn: 6,
    shanten: 0,
  );

  final List<String> tiles;
  final String doraIndicator;
  final Wind seatWind;
  final Wind roundWind;
  final int turn;
  final int shanten;

  HandState toHandState() => _handStateOf(
    tiles,
    doraIndicator: doraIndicator,
    seatWind: seatWind,
    roundWind: roundWind,
    turn: turn,
  );

  DailyHand toDailyHand({
    required String date,
    required int number,
    required DailyLevel level,
    required bool split,
    required int stage,
    required int attempts,
  }) => DailyHand(
    date: date,
    number: number,
    level: level,
    tiles: List.unmodifiable(tiles),
    doraIndicator: doraIndicator,
    seatWind: seatWind,
    roundWind: roundWind,
    turn: turn,
    shanten: shanten,
    split: split,
    stage: stage,
    attempts: attempts,
  );
}

HandState _handStateOf(
  List<String> tiles, {
  required String doraIndicator,
  required Wind seatWind,
  required Wind roundWind,
  required int turn,
}) => HandState.fromLabels(
  tiles,
  visible: [doraIndicator],
  doraIds: [tileIdFromLabel(doraFromIndicator(doraIndicator))],
  seatWind: seatWind,
  roundWind: roundWind,
  dealer: seatWind == Wind.east,
  turn: turn,
);

/// 今日の問題用の決定的な乱数（xoshiro128**、32 bit）。
///
/// シードは文字列の FNV-1a（32 bit）を splitmix32 で 4 語に広げる。演算はすべて
/// 32 bit に丸めるので、Dart のネイティブ（64 bit int）で端末によらず同じ列になる。
/// 他言語へ移すときは 32 bit の符号なし乗算（JS なら `Math.imul`）で同じ列を作れる。
class DailyRandom {
  DailyRandom._(this._s0, this._s1, this._s2, this._s3);

  factory DailyRandom.fromString(String seed) {
    var x = fnv1a32(seed);
    int nextSeed() {
      x = (x + 0x9e3779b9) & _mask;
      var z = x;
      z = _mul32(z ^ (z >> 16), 0x85ebca6b);
      z = _mul32(z ^ (z >> 13), 0xc2b2ae35);
      return z ^ (z >> 16);
    }

    final s = [nextSeed(), nextSeed(), nextSeed(), nextSeed()];
    // 全部 0 だと止まるので避ける（実際には起きない）。
    if (s.every((v) => v == 0)) s[0] = 1;
    return DailyRandom._(s[0], s[1], s[2], s[3]);
  }

  static const int _mask = 0xFFFFFFFF;

  int _s0;
  int _s1;
  int _s2;
  int _s3;

  /// 32 bit の符号なし乱数（0〜0xFFFFFFFF）。
  int nextUint32() {
    final result = _mul32(_rotl(_mul32(_s1, 5), 7), 9);
    final t = (_s1 << 9) & _mask;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 11);
    return result;
  }

  /// 0 以上 [max] 未満の一様な整数（棄却法で偏りなし）。
  int nextInt(int max) {
    if (max <= 0 || max > 0x100000000) {
      throw RangeError.range(max, 1, 0x100000000, 'max');
    }
    const range = 0x100000000;
    final limit = range - range % max;
    while (true) {
      final r = nextUint32();
      if (r < limit) return r % max;
    }
  }

  static int _rotl(int x, int k) =>
      ((x << k) & _mask) | ((x & _mask) >> (32 - k));

  static int _mul32(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + (hi << 16)) & _mask;
  }
}

/// 文字列（UTF-16 の符号単位。日付などの ASCII を想定）の FNV-1a 32 bit。
int fnv1a32(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit & 0xFF;
    hash = DailyRandom._mul32(hash, 0x01000193);
    if (unit > 0xFF) {
      hash ^= unit >> 8;
      hash = DailyRandom._mul32(hash, 0x01000193);
    }
  }
  return hash;
}

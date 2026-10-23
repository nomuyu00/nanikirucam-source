import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';

/// ライブの認識状態（仕様 13 章 `live_state` の `state`）。
enum LiveTrackState {
  /// 牌が見つからない・並びを確かめている。
  searching,

  /// 枚数（13/14）とラベル列が 1.0 秒以上変わらない。案内を出せる。
  stable,

  /// 並びが変わっている（手を動かしている）。
  moving,

  /// 暗い。
  dark,

  /// 手牌が小さく写っている（画面幅の 50% 未満）。
  far,

  /// 枚数が 13/14 でない。
  countMismatch;

  /// 計測で送る名前。
  String get analyticsName => switch (this) {
    LiveTrackState.countMismatch => 'count_mismatch',
    _ => name,
  };
}

/// 安定しているのに案内を止める理由。
enum AdviceBlock {
  /// 確度 [TrackerConfig.lowConfidence] 未満の牌が 2 枚以上（「牌を見やすくしてください」）。
  lowConfidence,

  /// 同じ牌が 5 枚以上あり、手として成り立たない（誤認識）。
  impossibleHand,
}

/// [TileTracker] のしきい値（設計書 3.3）。
///
/// 手持ち撮影の手ぶれに耐えるため、履歴の窓・取りこぼしの扱いは時間で決める
/// （fps が 5 でも 2 でも同じ意味になるように）。
class TrackerConfig {
  const TrackerConfig({
    this.window = 12,
    this.windowSpan = const Duration(milliseconds: 1800),
    this.minWindowFrames = 4,
    this.stableAfter = const Duration(milliseconds: 1000),
    this.minSupportFrames = 3,
    this.changeFrames = 2,
    this.switchFrames = 3,
    this.darkLuminance = 0.15,
    this.minHandWidth = 0.5,
    this.lowConfidence = 0.6,
    this.lowConfidenceExit = 0.65,
    this.maxLowConfidenceTiles = 1,
    this.minScore = 0.25,
    this.minRowTiles = 3,
    this.glitchTolerance = 1,
    this.invalidGrace = const Duration(milliseconds: 800),
    this.maxFrameGap = const Duration(seconds: 2),
    this.blurRatio = 0.6,
    this.sharpnessHistory = 9,
    this.minSharpnessSamples = 5,
    this.boxSmoothing = 0.5,
    this.arrangementFrames = 5,
  });

  /// 多数決に使うフレームの最大数（時間の窓 [windowSpan] の中でもこれを超えない）。
  final int window;

  /// 多数決に使う時間の窓。これより古いフレームは捨てる（ただし [minWindowFrames] は残す）。
  final Duration windowSpan;

  /// 時間の窓から外れても残す、直近のフレームの数（低い fps でも多数決できるように）。
  final int minWindowFrames;

  /// 枚数とラベル列がこの時間以上同じなら [LiveTrackState.stable]。
  final Duration stableAfter;

  /// stable にするのに必要な、同じ枚数のフレームの最小数（低 fps でも 2 枚では決めない）。
  final int minSupportFrames;

  /// 直近のこのフレーム数が続けて多数決と食い違い、しかも「同じ別の並び」か「2 枚以上の
  /// 違い」を示したら、手が動いたとみなす（案内を消す）。1 枚欠け・1 枚の読み違いが
  /// ばらばらに出るだけなら揺れとして多数決に任せる。
  final int changeFrames;

  /// 直近のこのフレーム数が続けて「同じ別の並び（枚数も違う）」なら、古いフレームを捨てて
  /// 新しい手に切り替える。
  final int switchFrames;

  /// 平均輝度（0〜1）がこれ未満なら [LiveTrackState.dark]。
  final double darkLuminance;

  /// 手牌の幅（画面幅に対する割合）がこれ未満なら [LiveTrackState.far]。
  final double minHandWidth;

  /// 平均確度がこれ未満の牌は「確度が低い」（枠を赤く、名前に「？」）。
  final double lowConfidence;

  /// 確度が低いとした牌は、平均確度がこれ以上に戻るまで低いままにする（出入りの揺れを防ぐ）。
  final double lowConfidenceExit;

  /// 確度の低い牌がこの枚数を超えたら、stable でも案内しない（仕様 3.1.3: 2 枚以上で止める）。
  final int maxLowConfidenceTiles;

  /// これ未満の検出は手牌の列に入れない。
  final double minScore;

  /// 列の牌がこの枚数未満なら「探索中」。
  final int minRowTiles;

  /// 「見つからない・暗い・遠い・ぶれた」フレームは、続けてこの回数までなら（時間によらず）
  /// 直前の状態を保つ。
  final int glitchTolerance;

  /// 最後の有効なフレームからこの時間以内の「見つからない・暗い・遠い・ぶれた」フレームは
  /// 無視して直前の状態を保つ（履歴も消さない。stable の経過は延ばさない）。
  /// これを超えて続いたら履歴を捨てる。
  final Duration invalidGrace;

  /// フレームの間がこれ以上空いたら（一時停止など）、履歴を捨てて最初から。
  final Duration maxFrameGap;

  /// 鮮鋭度が直近の中央値のこの割合未満なら「ぶれた」フレームとして投票に入れない。
  final double blurRatio;

  /// 鮮鋭度の中央値に使う直近のフレーム数。
  final int sharpnessHistory;

  /// ぶれの判定を始めるのに必要な鮮鋭度の数。
  final int minSharpnessSamples;

  /// 枠の平滑化（指数移動平均）の新しい枠の重み（0〜1）。牌の幅の半分以上動いたらそのまま追う。
  final double boxSmoothing;

  /// 副露・ツモ牌の判定に渡す、直近の（多数決と同じ枚数の）フレームの数。
  final int arrangementFrames;
}

/// 1 フレームの観測（推論結果と時刻）。
class TrackerObservation {
  const TrackerObservation({
    required this.timestamp,
    required this.tiles,
    required this.luminance,
    this.sharpness = 0,
  });

  factory TrackerObservation.fromDetections(
    Duration timestamp,
    LiveDetections detections,
  ) => TrackerObservation(
    timestamp: timestamp,
    tiles: detections.tiles,
    luminance: detections.luminance,
    sharpness: detections.sharpness,
  );

  /// フレームの時刻（単調増加。テストでは偽の時計）。
  final Duration timestamp;
  final List<LiveTileBox> tiles;
  final double luminance;

  /// 推論範囲の鮮鋭度（`liveSharpness`）。0 以下は「測っていない」（ぶれの判定をしない）。
  final double sharpness;
}

/// スロット（左から i 番目）の牌。
class TrackedTile {
  const TrackedTile({
    required this.label,
    required this.confidence,
    required this.box,
    required this.lowConfidence,
  });

  /// 多数決で決めたラベル。
  final String label;

  /// 直近のフレームの確度の平均（多数決で負けたフレームは 0 として数える）。
  final double confidence;

  /// 枠（正立フレームに対する 0〜1）。手ぶれの細かい揺れを均した位置。
  final Rect box;
  final bool lowConfidence;

  int get tileId => tileIdFromLabel(label);
}

/// [TileTracker.update] の結果。
class TrackerSnapshot {
  const TrackerSnapshot({
    required this.state,
    this.tiles = const [],
    this.rawTiles = const [],
    this.count = 0,
    this.stableFor = Duration.zero,
    this.settledFor = Duration.zero,
    this.lowConfidenceCount = 0,
    this.block,
    this.handWidth = 0,
    this.rawAgrees = false,
    this.handChanging = false,
    this.supportBoxes = const [],
  });

  static const TrackerSnapshot initial = TrackerSnapshot(
    state: LiveTrackState.searching,
  );

  final LiveTrackState state;

  /// 多数決で決めた牌（左から右）。stable・moving・枚数違いのときに入る。
  final List<TrackedTile> tiles;

  /// 最新のフレームの列（表示用。多数決の前）。
  final List<LiveTileBox> rawTiles;

  /// 枚数（多数決）。
  final int count;

  /// stable になってからの時間（stable でなければ 0）。
  final Duration stableFor;

  /// 今の並びになってからの時間（手が止まってからの時間）。
  final Duration settledFor;

  final int lowConfidenceCount;

  /// stable でも案内を止める理由。
  final AdviceBlock? block;

  /// 手牌の幅（画面幅に対する割合）。
  final double handWidth;

  /// 最新のフレームが多数決の並びと一致しているか。
  final bool rawAgrees;

  /// 手が本当に変わった（牌を切った・入れ替えた・動かしている）と判定した。前の手の案内は
  /// 保持せずにすぐ消す。
  final bool handChanging;

  /// 直近の（多数決と同じ枚数の）フレームの生の枠（古い順、各フレームは左から [count] 枚）。
  /// 副露・ツモ牌を 1 フレームで決めないために使う。
  final List<List<Rect>> supportBoxes;

  bool get isStable => state == LiveTrackState.stable;

  /// 案内を出してよい（stable で、確度の低い牌が 1 枚以下、手として成り立つ）。
  bool get canAdvise => isStable && block == null;

  List<String> get labels => [for (final t in tiles) t.label];

  /// 手の識別子（同じ手かどうかの比較とキャッシュのキー）。
  String get handKey => labels.join(',');

  TrackerSnapshot _held() => TrackerSnapshot(
    state: state,
    tiles: tiles,
    rawTiles: rawTiles,
    count: count,
    stableFor: stableFor,
    settledFor: settledFor,
    lowConfidenceCount: lowConfidenceCount,
    block: block,
    handWidth: handWidth,
    // 見えていないフレームなので「一致」とはしない（fps を落とさず、早く見直す）。
    rawAgrees: false,
    handChanging: handChanging,
    supportBoxes: supportBoxes,
  );
}

class _Row {
  _Row(this.tiles) : key = tiles.map((t) => t.label).join(',');
  final List<LiveTileBox> tiles;

  /// ラベル列（枚数も含めて比べられる）。
  final String key;
  int get count => tiles.length;
}

class _Frame {
  const _Frame(this.timestamp, this.row);
  final Duration timestamp;
  final _Row row;
}

/// 時間方向の多数決と安定判定（設計書 3.3、中核）。純 Dart で、時刻は観測に入れて渡す。
///
/// 1. 検出枠のうち、確度 [TrackerConfig.minScore] 以上の牌から、直線上に並ぶ（傾いていてもよい）
///    いちばん枚数の多い列を選び、x の順に並べる（左から i 番目 = スロット i）。
/// 2. 直近 [TrackerConfig.windowSpan]（最大 [TrackerConfig.window] フレーム）で枚数を多数決し、
///    同じ枚数のフレームだけでスロットごとにラベルを多数決する。同票なら今のラベルを保つ。
///    確度はその平均（負けたフレームは 0 として数えるので、揺れる牌は確度が下がる）。
/// 3. 枚数（13/14）と多数決のラベル列が [TrackerConfig.stableAfter] 以上変わらなければ
///    stable。直近 [TrackerConfig.changeFrames] フレームが続けて「同じ別の並び」か
///    「2 枚以上違う並び」を示したら、手が動いたとみなして moving（案内を消す）。
///    ばらばらな 1 枚の欠け・読み違いは揺れとして多数決に任せる。
/// 4. 見つからない・暗い・遠い・ぶれたフレームは、最後の有効なフレームから
///    [TrackerConfig.invalidGrace] 以内なら無視して直前の状態を保つ（手持ちの短いぶれで
///    履歴を消さない）。それを超えて続いたら履歴を捨てる。
class TileTracker {
  TileTracker({this.config = const TrackerConfig()});

  final TrackerConfig config;

  /// 列を拾うときに許す傾き（tan 25°）。
  static const double maxRowSlope = 0.47;

  final List<_Frame> _history = [];
  final List<double> _sharpness = [];
  final List<_Row> _disagreeing = [];
  Duration? _lastTimestamp;
  Duration? _lastValidAt;
  String? _candidateKey;
  Duration? _candidateSince;
  Duration? _stableSince;
  bool _changedFromPrevious = false;
  int _invalidStreak = 0;
  List<TrackedTile> _tiles = const [];
  TrackerSnapshot _last = TrackerSnapshot.initial;

  TrackerSnapshot get snapshot => _last;

  /// 履歴を捨てて最初から（一時停止・カメラの切り替え）。
  void reset() {
    _clearHand();
    _sharpness.clear();
    _lastTimestamp = null;
    _lastValidAt = null;
    _invalidStreak = 0;
    _last = TrackerSnapshot.initial;
  }

  void _clearHand() {
    _history.clear();
    _disagreeing.clear();
    _candidateKey = null;
    _candidateSince = null;
    _stableSince = null;
    _changedFromPrevious = false;
    _tiles = const [];
  }

  TrackerSnapshot update(TrackerObservation obs) {
    final now = obs.timestamp;
    final last = _lastTimestamp;
    if (last != null && now - last > config.maxFrameGap) _clearHand();
    _lastTimestamp = now;

    // --- 1 フレームの判定 ---
    final row = _extractRow(obs.tiles);
    final width = _width(row.tiles);
    LiveTrackState? invalid;
    if (obs.luminance < config.darkLuminance) {
      invalid = LiveTrackState.dark;
    } else if (row.count < config.minRowTiles) {
      invalid = LiveTrackState.searching;
    } else if (width < config.minHandWidth) {
      invalid = LiveTrackState.far;
    }
    final blurry = invalid == null && _isBlurry(obs.sharpness);
    if (invalid == null && obs.sharpness > 0) _recordSharpness(obs.sharpness);

    if (invalid != null || blurry) {
      _invalidStreak++;
      final validAt = _lastValidAt;
      final withinGrace =
          _invalidStreak <= config.glitchTolerance ||
          (validAt != null && now - validAt <= config.invalidGrace);
      if (_history.isNotEmpty && withinGrace) {
        // 短い取りこぼし・ぶれは無視して、直前の状態を保つ（履歴も stable の時間も変えない）。
        return _last = _last._held();
      }
      if (invalid != null) {
        _clearHand();
        return _last = TrackerSnapshot(
          state: invalid,
          rawTiles: row.tiles,
          count: row.count,
          handWidth: width,
        );
      }
      // ぶれが長く続く: 中央値が追いつくまでの間も、見えている列で判定する。
    }
    _invalidStreak = 0;
    _lastValidAt = now;

    // --- 履歴に足す（時間の窓 + フレーム数の上限） ---
    _history.add(_Frame(now, row));
    while (_history.length > config.window) {
      _history.removeAt(0);
    }
    while (_history.length > config.minWindowFrames &&
        now - _history.first.timestamp > config.windowSpan) {
      _history.removeAt(0);
    }

    // 「同じ別の並び（枚数も違う）」が続いたら、古い手のフレームを捨てる。
    // 1 枚欠けがばらばらに混ざるだけ（並びが毎回違う）では捨てない。
    if (_history.length >= config.switchFrames) {
      final recent = _history.reversed.take(config.switchFrames);
      if (recent.every((f) => f.row.key == row.key) &&
          _history.any((f) => f.row.count != row.count)) {
        _history.removeWhere((f) => f.row.count != row.count);
      }
    }

    // --- 多数決 ---
    final previous = _tiles;
    final count = _modeCount(previous.length);
    final support = [
      for (final f in _history)
        if (f.row.count == count) f,
    ];
    final samePrevious = previous.length == count;
    final tiles = <TrackedTile>[];
    for (var k = 0; k < count; k++) {
      final votes = <String, int>{};
      final scoreSums = <String, double>{};
      for (final f in support) {
        final t = f.row.tiles[k];
        votes.update(t.label, (v) => v + 1, ifAbsent: () => 1);
        scoreSums.update(t.label, (v) => v + t.score, ifAbsent: () => t.score);
      }
      final current = samePrevious ? previous[k].label : null;
      String? winner;
      for (final label in votes.keys) {
        if (winner == null) {
          winner = label;
          continue;
        }
        final v = votes[label]!;
        final w = votes[winner]!;
        if (v > w) {
          winner = label;
        } else if (v == w) {
          // 同票: 今のラベルを保つ（交互に揺れる牌で並びが反転し続けないように）。
          if (winner == current) continue;
          if (label == current || scoreSums[label]! > scoreSums[winner]!) {
            winner = label;
          }
        }
      }
      final confidence = scoreSums[winner]! / support.length;
      final wasLow =
          samePrevious &&
          previous[k].label == winner &&
          previous[k].lowConfidence;
      final raw = support.last.row.tiles[k].box;
      tiles.add(
        TrackedTile(
          label: winner!,
          confidence: confidence,
          box: samePrevious ? _smooth(previous[k].box, raw) : raw,
          lowConfidence: wasLow
              ? confidence < config.lowConfidenceExit
              : confidence < config.lowConfidence,
        ),
      );
    }
    _tiles = tiles;

    final key = '$count:${tiles.map((t) => t.label).join(',')}';
    if (key != _candidateKey) {
      if (_candidateKey != null) _changedFromPrevious = true;
      _candidateKey = key;
      _disagreeing.clear();
      // 新しい並びに見え始めた時刻: 最新から遡って、この並びと一致するフレームが続く所まで。
      var since = now;
      for (final f in _history.reversed) {
        if (!_matches(f.row, tiles)) break;
        since = f.timestamp;
      }
      _candidateSince = since;
      _stableSince = null;
    }

    // 最新のフレームが多数決と一致しているか（ばらばらな揺れは多数決が吸収する）。
    final rawAgrees = _matches(row, tiles);
    if (rawAgrees) {
      _disagreeing.clear();
    } else {
      _disagreeing.add(row);
      if (_disagreeing.length > 4) _disagreeing.removeAt(0);
    }
    final changing = _isChanging(tiles);

    final settledFor = now - (_candidateSince ?? now);
    final lowCount = tiles.where((t) => t.lowConfidence).length;
    AdviceBlock? block;
    if (_impossible(tiles)) {
      block = AdviceBlock.impossibleHand;
    } else if (lowCount > config.maxLowConfidenceTiles) {
      block = AdviceBlock.lowConfidence;
    }

    final LiveTrackState state;
    if (count != 13 && count != 14) {
      state = LiveTrackState.countMismatch;
      _stableSince = null;
    } else if (changing) {
      state = LiveTrackState.moving;
      _stableSince = null;
    } else if (settledFor >= config.stableAfter &&
        support.length >= config.minSupportFrames) {
      state = LiveTrackState.stable;
      _stableSince ??= now;
      _changedFromPrevious = false;
    } else {
      state = (_changedFromPrevious || !rawAgrees)
          ? LiveTrackState.moving
          : LiveTrackState.searching;
      _stableSince = null;
    }

    final recentSupport = support.length > config.arrangementFrames
        ? support.sublist(support.length - config.arrangementFrames)
        : support;
    return _last = TrackerSnapshot(
      state: state,
      tiles: List.unmodifiable(tiles),
      rawTiles: row.tiles,
      count: count,
      stableFor: state == LiveTrackState.stable
          ? now - (_stableSince ?? now)
          : Duration.zero,
      settledFor: settledFor,
      lowConfidenceCount: lowCount,
      block: block,
      handWidth: width,
      rawAgrees: rawAgrees,
      handChanging: changing,
      supportBoxes: List.unmodifiable([
        for (final f in recentSupport)
          List<Rect>.unmodifiable([for (final t in f.row.tiles) t.box]),
      ]),
    );
  }

  /// 鮮鋭度が直近の中央値より大きく低い（ぶれた）フレームか。
  bool _isBlurry(double sharpness) {
    if (sharpness <= 0 || _sharpness.length < config.minSharpnessSamples) {
      return false;
    }
    final sorted = [..._sharpness]..sort();
    final median = sorted[sorted.length ~/ 2];
    return sharpness < median * config.blurRatio;
  }

  void _recordSharpness(double sharpness) {
    _sharpness.add(sharpness);
    while (_sharpness.length > config.sharpnessHistory) {
      _sharpness.removeAt(0);
    }
  }

  /// 多数決と食い違うフレームが、本当の手の変化を示しているか。
  ///
  /// - 直近 [TrackerConfig.changeFrames] フレームが同じ別の並び（ラベル列が同じ）。
  /// - 直近 [TrackerConfig.changeFrames] フレームがどれも 2 枚以上違う。
  /// - 食い違いが [TrackerConfig.changeFrames] + 1 フレーム以上続き、その中に 2 枚以上違う
  ///   フレームがある。
  /// どれでもなければ（1 枚欠け・1 枚の読み違いがばらばらに出るだけ）揺れとみなす。
  bool _isChanging(List<TrackedTile> tiles) {
    final n = _disagreeing.length;
    if (n < config.changeFrames) return false;
    final recent = _disagreeing.sublist(n - config.changeFrames);
    if (recent.every((r) => r.key == recent.first.key)) return true;
    final labels = [for (final t in tiles) t.label];
    final distances = [for (final r in _disagreeing) _editDistance(r, labels)];
    if (distances.sublist(n - config.changeFrames).every((d) => d >= 2)) {
      return true;
    }
    return n > config.changeFrames && distances.any((d) => d >= 2);
  }

  /// ラベル列の編集距離（1 枚の欠け・余分・読み違いが 1）。
  static int _editDistance(_Row row, List<String> labels) {
    final a = row.tiles;
    final m = a.length;
    final n = labels.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      final ai = a[i - 1].label;
      for (var j = 1; j <= n; j++) {
        final sub = prev[j - 1] + (ai == labels[j - 1] ? 0 : 1);
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        cur[j] = math.min(sub, math.min(del, ins));
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[n];
  }

  /// 枠の指数移動平均。牌の幅の半分以上動いたら（手全体を動かした）そのまま追う。
  Rect _smooth(Rect previous, Rect raw) {
    final moved = (raw.center - previous.center).distance;
    if (moved > raw.width * 0.5) return raw;
    final a = config.boxSmoothing;
    return Rect.lerp(previous, raw, a)!;
  }

  /// 枚数の多数決。同票なら今の枚数（[current]）、なければ最新のフレームの枚数。
  int _modeCount(int current) {
    final tally = <int, int>{};
    for (final f in _history) {
      tally.update(f.row.count, (v) => v + 1, ifAbsent: () => 1);
    }
    var best = _history.last.row.count;
    var bestVotes = tally[best]!;
    for (final e in tally.entries) {
      if (e.value > bestVotes || (e.value == bestVotes && e.key == current)) {
        best = e.key;
        bestVotes = e.value;
      }
    }
    return best;
  }

  static bool _matches(_Row row, List<TrackedTile> tiles) {
    if (row.count != tiles.length) return false;
    for (var k = 0; k < tiles.length; k++) {
      if (row.tiles[k].label != tiles[k].label) return false;
    }
    return true;
  }

  static bool _impossible(List<TrackedTile> tiles) {
    final perId = <int, int>{};
    for (final t in tiles) {
      final id = tileIdFromLabel(t.label);
      if (id < 0) return true;
      final n = perId.update(id, (v) => v + 1, ifAbsent: () => 1);
      if (n > 4) return true;
    }
    return false;
  }

  static double _width(List<LiveTileBox> row) {
    if (row.isEmpty) return 0;
    var left = double.infinity;
    var right = double.negativeInfinity;
    for (final t in row) {
      left = math.min(left, t.box.left);
      right = math.max(right, t.box.right);
    }
    return right - left;
  }

  /// 検出枠から手牌の列を選ぶ（左から右）。裏向き（`0b`）と確度の低い枠は除く。
  ///
  /// 各枠を基準に、近くの枠との傾き（±25° まで）と水平の直線を候補にし、牌の中心がその直線から
  /// 枠の高さの中央値の 0.6 倍以内にある枠を集める。集めた枠に直線を当てはめ直して集め直し、
  /// いちばん多い（同数なら確度の合計が大きい）列を選ぶ。手持ちでカメラが傾いても端の牌を
  /// 落とさないため。同じ位置に重なる枠は確度の高い方だけ残す。
  List<LiveTileBox> extractRow(List<LiveTileBox> detections) =>
      _extractRow(detections).tiles;

  _Row _extractRow(List<LiveTileBox> detections) {
    final candidates = [
      for (final t in detections)
        if (t.score >= config.minScore &&
            t.label != '0b' &&
            tileIdFromLabel(t.label) >= 0)
          t,
    ]..sort((a, b) => b.score.compareTo(a.score));
    if (candidates.isEmpty) return _Row(const []);

    final heights = candidates.map((t) => t.box.height).toList()..sort();
    final widths = candidates.map((t) => t.box.width).toList()..sort();
    final medianH = heights[heights.length ~/ 2];
    final medianW = widths[widths.length ~/ 2];
    final tolerance = medianH * 0.6;
    final duplicateDistance = medianW * 0.5;
    final minDx = medianW * 0.5;
    final maxDx = medianW * 6;
    final n = candidates.length;
    final cx = Float64List(n);
    final cy = Float64List(n);
    for (var i = 0; i < n; i++) {
      cx[i] = candidates[i].box.center.dx;
      cy[i] = candidates[i].box.center.dy;
    }

    // 直線 y = y0 + s (x - x0) から [tolerance] 以内の枠を、確度の高い順に重なりを除いて集める。
    List<int> collect(double x0, double y0, double s) {
      final norm = math.sqrt(1 + s * s);
      final band = <int>[];
      for (var i = 0; i < n; i++) {
        final d = ((cy[i] - y0) - s * (cx[i] - x0)).abs() / norm;
        if (d > tolerance) continue;
        var duplicate = false;
        for (final k in band) {
          final dx = cx[k] - cx[i];
          final dy = cy[k] - cy[i];
          if (math.sqrt(dx * dx + dy * dy) < duplicateDistance ||
              _iou(candidates[k], candidates[i]) >= 0.35) {
            duplicate = true;
            break;
          }
        }
        if (!duplicate) band.add(i);
      }
      return band;
    }

    List<int> best = const [];
    var bestSet = <int>{};
    var bestScore = -1.0;
    void consider(List<int> band) {
      var score = 0.0;
      for (final i in band) {
        score += candidates[i].score;
      }
      if (band.length > best.length ||
          (band.length == best.length && score > bestScore)) {
        best = band;
        bestSet = band.toSet();
        bestScore = score;
      }
    }

    final tried = <int>{};
    for (var a = 0; a < n; a++) {
      final slopes = <double>[0];
      for (var b = 0; b < n; b++) {
        if (b == a) continue;
        // 今いちばんの列の 2 枚を通る直線は、その列で当てはめ直し済み（重い場面での省略）。
        if (bestSet.contains(a) && bestSet.contains(b)) continue;
        final dx = cx[b] - cx[a];
        if (dx.abs() < minDx || dx.abs() > maxDx) continue;
        final s = (cy[b] - cy[a]) / dx;
        if (s.abs() <= maxRowSlope) slopes.add(s);
      }
      for (final s0 in slopes) {
        var band = collect(cx[a], cy[a], s0);
        // 同じ組み合わせの列は 1 度だけ当てはめ直す。
        final signature = Object.hashAllUnordered(band);
        if (!tried.add(signature)) continue;
        // 集めた枠に直線を当てはめ直して、集め直す（2 回まで）。
        for (var iter = 0; iter < 2 && band.length >= 3; iter++) {
          final fit = _fitLine(band, cx, cy);
          if (fit == null || fit.$3.abs() > maxRowSlope) break;
          final refit = collect(fit.$1, fit.$2, fit.$3);
          if (refit.length < band.length) break;
          final same =
              refit.length == band.length && refit.toSet().containsAll(band);
          band = refit;
          if (same) break;
        }
        consider(band);
      }
    }
    final row = [for (final i in best) candidates[i]]
      ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));
    return _Row(List.unmodifiable(row));
  }

  /// 最小二乗の直線（重心 x0, y0 と傾き s）。縦に並ぶ（x が揃う）ときは null。
  static (double, double, double)? _fitLine(
    List<int> band,
    Float64List cx,
    Float64List cy,
  ) {
    var mx = 0.0;
    var my = 0.0;
    for (final i in band) {
      mx += cx[i];
      my += cy[i];
    }
    mx /= band.length;
    my /= band.length;
    var sxx = 0.0;
    var sxy = 0.0;
    for (final i in band) {
      final dx = cx[i] - mx;
      sxx += dx * dx;
      sxy += dx * (cy[i] - my);
    }
    if (sxx <= 1e-12) return null;
    return (mx, my, sxy / sxx);
  }

  static double _iou(LiveTileBox a, LiveTileBox b) {
    final r = a.box.intersect(b.box);
    if (r.width <= 0 || r.height <= 0) return 0;
    final inter = r.width * r.height;
    final union =
        a.box.width * a.box.height + b.box.width * b.box.height - inter;
    return union <= 0 ? 0 : inter / union;
  }
}

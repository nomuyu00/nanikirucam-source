import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/live/frame_gate.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_detector.dart';
import 'package:nanikiru_cam/live/live_model_tier.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_arrangement.dart';

/// 単調に進む時計（フレームの時刻）。テストでは偽物に差し替える。
abstract class LiveClock {
  Duration get elapsed;
}

class StopwatchLiveClock implements LiveClock {
  final Stopwatch _watch = Stopwatch()..start();

  @override
  Duration get elapsed => _watch.elapsed;
}

/// ライブで解析に渡す局の条件（ライブ画面の設定シートで変える）。
class LiveHandContext {
  const LiveHandContext({
    this.seatWind = Wind.south,
    this.roundWind = Wind.east,
    this.doraIndicators = const [],
  });

  final Wind seatWind;
  final Wind roundWind;
  final List<String> doraIndicators;

  HandInput inputFor(List<String> labels, {int? tsumoIndex}) => HandInput(
    tiles: labels,
    tsumoIndex: tsumoIndex,
    seatWind: seatWind,
    roundWind: roundWind,
    doraIndicators: doraIndicators,
  );

  LiveHandContext copyWith({
    Wind? seatWind,
    Wind? roundWind,
    List<String>? doraIndicators,
  }) => LiveHandContext(
    seatWind: seatWind ?? this.seatWind,
    roundWind: roundWind ?? this.roundWind,
    doraIndicators: doraIndicators ?? this.doraIndicators,
  );

  String get key =>
      '${seatWind.name}|${roundWind.name}|${doraIndicators.join(',')}';
}

/// 計測の送り先（`AppAnalytics.logEvent` を包む）。
typedef LiveEventLogger =
    void Function(AnalyticsEvent event, Map<String, Object> parameters);

/// カメラのフレーム → 推論 → 安定判定 → 解析 → 案内 をまとめる（設計書 3.3）。
///
/// 案内は [TrackerSnapshot.canAdvise]（stable かつ確度の低い牌が 1 枚以下）で、解析した
/// 手と今の手が同じときだけ出す（[advice]）。手持ちの揺れで canAdvise が一瞬落ちても、
/// 同じ手のままなら [adviceHold] の間は直前の案内を保つ（[adviceHeld]、画面では薄く出す）。
/// 手が変わった（[TrackerSnapshot.handChanging]・手のキーが変わった）ときはすぐ消す。
///
/// [modelTiering] があれば、始めの数十フレームの「前処理 + 推論」の中央値が遅いときに、
/// セッション中により速いモデルへ 1 段ずつ切り替える（[LiveModelTiering]）。切り替えの間は
/// 検出を止めて追跡を消し、案内を出さない。null ならモデルは固定。
class LiveController extends ChangeNotifier {
  LiveController({
    required this._detector,
    required this._analysis,
    required this._clock,
    this._log,
    TrackerConfig trackerConfig = const TrackerConfig(),
    this._policy = const LiveFrameRatePolicy(),
    LiveHandContext handContext = const LiveHandContext(),
    StrategyAxis initialAxis = StrategyAxis.balance,
    this.onAdviceShown,
    this.modelTiering,
    this.adviceHold = const Duration(milliseconds: 700),
  }) : _tracker = TileTracker(config: trackerConfig),
       _context = handContext,
       _axis = initialAxis,
       _speed = LiveSpeedWindow(
         warmupFrames:
             modelTiering?.warmupFrames ?? LiveModelTiering.defaultWarmupFrames,
         sampleFrames:
             modelTiering?.sampleFrames ?? LiveModelTiering.defaultSampleFrames,
       );

  final LiveDetector _detector;
  final AnalysisService _analysis;
  final LiveClock _clock;
  final LiveEventLogger? _log;
  final TileTracker _tracker;
  final LiveFrameRatePolicy _policy;
  final FrameGate _gate = FrameGate();
  final AdviceFollowTracker _follow = AdviceFollowTracker();

  /// 新しい案内を出したとき（ハプティクス・音）。
  final void Function(LiveAdvice advice)? onAdviceShown;

  /// モデルの自動切り替えの設定（null なら固定）。
  final LiveModelTiering? modelTiering;

  /// canAdvise が落ちても、同じ手なら直前の案内を保つ時間（フレームの時刻で数える）。
  final Duration adviceHold;

  // モデルの速度の計測（最初の数十フレーム）と切り替え。
  final LiveSpeedWindow _speed;
  bool _speedSettled = false;
  bool _switching = false;
  int _modelEpoch = 0;

  LiveHandContext _context;
  TrackerSnapshot _snapshot = TrackerSnapshot.initial;
  LiveAdvice? _advice;
  String? _analysisKey;
  int _analysisGeneration = 0;
  bool _analyzing = false;
  bool _paused = false;
  bool _thermalWarning = false;
  bool _disposed = false;
  bool _meldSuspected = false;
  int? _tsumoIndex;
  String? _arrangementKey;
  Duration? _lastAdvisableAt;
  Duration? _lastObservedAt;
  StrategyAxis _axis;
  bool _axisChosen = false;

  String? _shownKey;
  final Set<String> _winKeys = {};
  LiveWinRecord? _activeWin;
  String? _dismissedWinKey;

  int _adviceCount = 0;
  int _followedCount = 0;
  int _followChecks = 0;
  final List<LiveWinRecord> _wins = [];

  final Map<LiveTrackState, Duration> _stateDurations = {};
  LiveTrackState? _lastState;
  Duration? _lastStateAt;

  int _framesProcessed = 0;
  int _detectErrors = 0;
  int _lastInferenceMicros = 0;
  int _lastPreprocessMicros = 0;

  // --- 読み取り ------------------------------------------------------------

  TrackerSnapshot get snapshot => _snapshot;

  /// 今出してよい案内。stable で、解析済みで、手が同じときだけ。
  ///
  /// canAdvise が落ちても、手のキーが同じで手が変わったと判定していなければ、最後に
  /// canAdvise だったフレームから [adviceHold] の間は保つ（[adviceHeld]）。
  LiveAdvice? get advice {
    final a = _advice;
    if (a == null || _paused || _switching || _meldSuspected) return null;
    if (a.handKey != _snapshot.handKey) return null;
    if (_snapshot.canAdvise) return a;
    return _holding ? a : null;
  }

  /// 案内を保っている間（canAdvise ではないが、直前の案内を出している）。画面では薄く出す。
  bool get adviceHeld => !_snapshot.canAdvise && advice != null;

  bool get _holding {
    if (_snapshot.handChanging || _snapshot.tiles.isEmpty) return false;
    final since = _lastAdvisableAt;
    final now = _lastObservedAt;
    if (since == null || now == null) return false;
    return now - since <= adviceHold;
  }

  /// 解析中（stable になって案内を待っている）。
  bool get analyzing => _analyzing && _snapshot.canAdvise;

  /// 右端に鳴いた（横向きの）牌があるらしい。ライブ v1.0 は門前のみ対応なので案内しない。
  bool get meldSuspected => _meldSuspected && _snapshot.isStable;

  bool get paused => _paused;
  bool get thermalWarning => _thermalWarning;
  StrategyAxis get axis => _axis;
  LiveHandContext get handContext => _context;
  int? get tsumoIndex => _tsumoIndex;

  int get adviceCount => _adviceCount;
  int get followedCount => _followedCount;
  int get followChecks => _followChecks;
  List<LiveWinRecord> get wins => List.unmodifiable(_wins);

  /// 「ツモ！」の大きな表示（「次の局へ」で消す）。
  LiveWinRecord? get activeWin {
    final a = advice;
    if (_activeWin == null || a == null || a.kind != LiveAdviceKind.win) {
      return null;
    }
    if (_dismissedWinKey == a.handKey) return null;
    return _activeWin;
  }

  double get targetFps => _gate.targetFps;
  int get framesProcessed => _framesProcessed;
  int get detectErrors => _detectErrors;
  int get lastInferenceMs => _lastInferenceMicros ~/ 1000;
  int get lastPreprocessMs => _lastPreprocessMicros ~/ 1000;

  /// モデルを切り替えている間（検出を止めている）。
  bool get switching => _switching;

  /// 今動いているモデル名（debug 表示用）。
  String? get modelLabel => _detector.modelLabel;

  /// 「前処理 + 推論」の中央値（ミリ秒）。最初の捨てフレームのあと、集めた分から。まだなら null。
  double? get speedMedianMs => _speed.medianMs;

  /// 状態ごとの割合（%）。終了時の `live_state` に使う。
  Map<LiveTrackState, int> stateRatiosPct() {
    final total = _stateDurations.values.fold<int>(
      0,
      (s, d) => s + d.inMicroseconds,
    );
    if (total <= 0) return const {};
    return {
      for (final e in _stateDurations.entries)
        if (e.value > Duration.zero)
          e.key: (e.value.inMicroseconds * 100 / total).round(),
    };
  }

  // --- 入力 ----------------------------------------------------------------

  /// カメラのフレーム。推論中・間引きで捨てるものは [FrameGate] が判定する。
  void onFrame(LiveFrame frame, {required int quarterTurns}) {
    if (_disposed || _paused || _switching || !_detector.isReady) return;
    final now = _clock.elapsed;
    _gate.targetFps = _policy.targetFps(
      snapshot: _snapshot,
      thermalWarning: _thermalWarning,
    );
    if (!_gate.tryAcquire(now)) return;
    final epoch = _modelEpoch;
    _detector
        .detect(frame, quarterTurns: quarterTurns)
        .then(
          (detections) {
            // モデルを切り替える前に始めた推論の結果は捨てる（門も切り替えで作り直し済み）。
            if (epoch != _modelEpoch) return;
            _gate.release();
            if (_disposed || _paused) return;
            _lastInferenceMicros = detections.inferenceMicros;
            _lastPreprocessMicros = detections.preprocessMicros;
            // 遅くて切り替えを始めたら、この結果も使わない。
            if (_sampleSpeed(detections)) return;
            _observe(TrackerObservation.fromDetections(now, detections));
          },
          onError: (Object error) {
            if (epoch != _modelEpoch) return;
            _gate.release();
            _detectErrors++;
            if (_detectErrors <= 3) debugPrint('[Live] detect failed: $error');
          },
        );
  }

  /// 1 フレームぶんの「前処理 + 推論」の時間を数え、窓がそろったら中央値で判定する。
  /// 遅くて次の段へ切り替えを始めたら true。
  bool _sampleSpeed(LiveDetections detections) {
    if (_speedSettled) return false;
    if (!_speed.add(detections.preprocessMicros + detections.inferenceMicros)) {
      return false;
    }
    // 窓がそろった: 速ければ（または次の段がなければ）これで決まり。
    final tiering = modelTiering;
    final median = _speed.medianMs ?? 0;
    final next = tiering != null && median > tiering.slowThresholdMs
        ? tiering.nextTier(_detector.activeModel)
        : null;
    if (next == null) {
      _speedSettled = true;
      return false;
    }
    debugPrint(
      '[Live] slow model (median ${median.toStringAsFixed(0)} ms > '
      '${tiering!.slowThresholdMs.toStringAsFixed(0)} ms): '
      '${_detector.activeModel} -> $next',
    );
    unawaited(_switchModel(next));
    return true;
  }

  /// 検出を止め、追跡を消して、[next] のモデルに差し替える。1 段ずつ、戻さない。
  Future<void> _switchModel(String next) async {
    _switching = true;
    _modelEpoch++;
    _resetTracking();
    notifyListeners();
    var switched = false;
    try {
      switched = await _detector.switchModel(next);
    } catch (error) {
      debugPrint('[Live] model switch failed: $error');
    }
    if (_disposed) return;
    if (switched) {
      // 新しいモデルで測り直す（さらに遅ければもう 1 段）。
      _speed.reset();
      try {
        modelTiering?.onSwitched?.call(next);
      } catch (error) {
        debugPrint('[Live] saving the model tier failed: $error');
      }
    } else {
      // 開けなかった: 今のモデルのまま続け、もう切り替えない。
      _speedSettled = true;
    }
    _gate.reset();
    _switching = false;
    notifyListeners();
  }

  /// 追跡・安定判定・間引きをやり直す（一時停止・モデルの切り替え）。
  void _resetTracking() {
    _tracker.reset();
    _gate.reset();
    _snapshot = TrackerSnapshot.initial;
    _arrangementKey = null;
    _lastAdvisableAt = null;
    _lastObservedAt = null;
    _lastState = null;
    _lastStateAt = null;
  }

  /// 推論結果を直接入れる（テスト・記録の再生用）。
  @visibleForTesting
  void observe(TrackerObservation observation) => _observe(observation);

  void _observe(TrackerObservation obs) {
    _framesProcessed++;
    final snapshot = _tracker.update(obs);
    _accountState(snapshot.state, obs.timestamp);

    _snapshot = snapshot;
    _lastObservedAt = obs.timestamp;
    if (snapshot.isStable) {
      // 副露・ツモ牌は直近の複数フレームの多数決で決める。ツモ牌は手ごとに 1 回、副露は
      // stable の間ずっと見直す（1 フレームの偽の副露で案内が止まり続けないように）。
      final first = snapshot.handKey != _arrangementKey;
      _arrangementKey = snapshot.handKey;
      _inspectArrangement(snapshot, decideTsumo: first);
    }
    if (snapshot.canAdvise) {
      _lastAdvisableAt = obs.timestamp;
      _onStableHand(snapshot);
    }
    _maybeShowAdvice();
    notifyListeners();
  }

  void _accountState(LiveTrackState state, Duration at) {
    final last = _lastState;
    final lastAt = _lastStateAt;
    if (last != null && lastAt != null && at > lastAt) {
      // 一時停止などで空いた時間は数えない（最大 2 秒）。
      final delta = Duration(
        microseconds: math.min(
          (at - lastAt).inMicroseconds,
          const Duration(seconds: 2).inMicroseconds,
        ),
      );
      _stateDurations.update(last, (d) => d + delta, ifAbsent: () => delta);
    }
    _lastState = state;
    _lastStateAt = at;
  }

  /// 副露・ツモ牌を、直近の（多数決と同じ枚数の）フレームそれぞれの枠で判定して多数決する。
  /// 副露は過半数のフレームで見えたときだけ。ツモ牌はいちばん多かった添字（なしも 1 票）。
  void _inspectArrangement(
    TrackerSnapshot snapshot, {
    required bool decideTsumo,
  }) {
    final tiles = snapshot.tiles;
    final frames = [
      for (final boxes in snapshot.supportBoxes)
        if (boxes.length == tiles.length) boxes,
    ];
    if (frames.isEmpty) frames.add([for (final t in tiles) t.box]);
    var meldVotes = 0;
    final tsumoVotes = <int?, int>{};
    for (final boxes in frames) {
      final ordered = [
        for (var i = 0; i < tiles.length; i++)
          TileDetection(
            box: boxes[i],
            label: tiles[i].label,
            score: tiles[i].confidence,
          ),
      ];
      final arrangement = TileArrangementDetector.analyze(ordered);
      if (arrangement.melds.isNotEmpty) meldVotes++;
      tsumoVotes.update(
        arrangement.tsumoIndex,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    _meldSuspected = meldVotes * 2 > frames.length;
    if (!decideTsumo) return;
    int? tsumo;
    var best = 0;
    for (final e in tsumoVotes.entries) {
      // 同票なら「ツモ牌なし」を選ぶ（推定しない方が安全）。
      if (e.value > best || (e.value == best && e.key == null)) {
        tsumo = e.key;
        best = e.value;
      }
    }
    _tsumoIndex = snapshot.count == 14 ? tsumo : null;
  }

  void _onStableHand(TrackerSnapshot snapshot) {
    if (_meldSuspected) return;
    // 採用率: 13 枚が stable になったら、直前の 14 枚の案内と比べる。
    if (snapshot.count == 13 && _follow.hasPending) {
      final followed = _follow.onStableThirteen(
        countsOfLabels(snapshot.labels),
      );
      if (followed != null) {
        _followChecks++;
        if (followed) _followedCount++;
        _log?.call(AnalyticsEvent.liveAdviceFollowed, {
          'followed': followed ? 1 : 0,
        });
      }
    }
    final key = '${snapshot.handKey}|${_context.key}';
    if (key == _analysisKey) return;
    final input = _context.inputFor(snapshot.labels, tsumoIndex: _tsumoIndex);
    if (!input.isAnalyzable) return;
    _analysisKey = key;
    _analyzing = true;
    final generation = ++_analysisGeneration;
    final handKey = snapshot.handKey;
    final labels = snapshot.labels;
    _analysis
        .analyze(input, deep: false)
        .then(
          (report) {
            if (_disposed || generation != _analysisGeneration) return;
            _advice = LiveAdvice(
              handKey: handKey,
              input: input,
              report: report,
              roles: rolesForSlots(labels, input.toHandState()),
            );
            _analyzing = false;
            _maybeShowAdvice();
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _analysisGeneration) return;
            debugPrint('[Live] analysis failed: $error');
            _analyzing = false;
            notifyListeners();
          },
        );
  }

  void _maybeShowAdvice() {
    final a = advice;
    if (a == null || a.handKey == _shownKey) return;
    _shownKey = a.handKey;
    _adviceCount++;
    _log?.call(AnalyticsEvent.liveAdviceShown, {
      'hand_size': a.handSize,
      'stable_ms': _snapshot.settledFor.inMilliseconds,
      'low_confidence_tiles': _snapshot.lowConfidenceCount,
      'axis': _axis.name,
    });
    switch (a.kind) {
      case LiveAdviceKind.discard:
        final discard = a.discardFor(_axis);
        if (discard != null) {
          _follow.onDiscardAdvice(countsOfLabels(a.input.tiles), discard);
        }
      case LiveAdviceKind.win:
        _follow.clear();
        _recordTsumo(a);
      case LiveAdviceKind.thirteen:
        break;
    }
    onAdviceShown?.call(a);
  }

  void _recordTsumo(LiveAdvice a) {
    final score = a.report.win;
    if (score == null || _winKeys.contains(a.handKey)) return;
    _winKeys.add(a.handKey);
    final record = LiveWinRecord(
      han: score.han,
      fu: score.fu,
      points: a.report.winPoints ?? 0,
      yaku: yakuNames(score),
      winType: 'tsumo',
      rank: winRank(han: score.han, fu: score.fu, yaku: score.yaku),
      hand: a.input,
    );
    _wins.add(record);
    _activeWin = record;
    _log?.call(AnalyticsEvent.liveWinDetected, {
      'win_type': 'tsumo',
      'han': score.han,
      'rank': record.rank,
    });
  }

  /// 13 枚のテンパイで、待ち牌が出てロンした（ユーザーが記録）。役がなければ null。
  LiveWinRecord? recordRon(WaitInfo wait) {
    final a = advice;
    final score = wait.ronScore;
    if (a == null || score == null) return null;
    final key = '${a.handKey}|ron|${wait.tileId}';
    if (_winKeys.contains(key)) return null;
    _winKeys.add(key);
    final record = LiveWinRecord(
      han: score.han,
      fu: score.fu,
      points: wait.ronPoints ?? 0,
      yaku: yakuNames(score),
      winType: 'ron',
      rank: winRank(han: score.han, fu: score.fu, yaku: score.yaku),
      hand: a.input.copyWith(
        tiles: [...a.input.tiles, tileLabelOfId(wait.tileId)],
        tsumoIndex: a.input.tiles.length,
      ),
    );
    _wins.add(record);
    _log?.call(AnalyticsEvent.liveWinDetected, {
      'win_type': 'ron',
      'han': score.han,
      'rank': record.rank,
    });
    notifyListeners();
    return record;
  }

  void dismissWin() {
    final a = advice;
    if (a != null) _dismissedWinKey = a.handKey;
    _activeWin = null;
    notifyListeners();
  }

  /// 画面で軸を切り替えた（`axis_changed` を送る）。
  void setAxis(StrategyAxis axis) {
    _axisChosen = true;
    if (axis == _axis) return;
    final from = _axis;
    _axis = axis;
    _log?.call(AnalyticsEvent.axisChanged, {
      'axis_from': from.name,
      'axis_to': axis.name,
      'screen': 'live',
    });
    _followCurrentAxis();
    notifyListeners();
  }

  /// 設定の「最初に表示する軸」。画面で軸を選んだ後は変えない（計測もしない）。
  void applyDefaultAxis(StrategyAxis axis) {
    if (_axisChosen || axis == _axis) return;
    _axis = axis;
    _followCurrentAxis();
    notifyListeners();
  }

  /// 採用率は、今画面に出ている牌で判定する。
  void _followCurrentAxis() {
    final a = advice;
    if (a != null && a.kind == LiveAdviceKind.discard) {
      final discard = a.discardFor(_axis);
      if (discard != null) {
        _follow.onDiscardAdvice(countsOfLabels(a.input.tiles), discard);
      }
    }
  }

  void setHandContext(LiveHandContext context) {
    if (context.key == _context.key) return;
    _context = context;
    _advice = null;
    _analysisKey = null;
    _analyzing = false;
    _analysisGeneration++;
    if (_snapshot.canAdvise) _onStableHand(_snapshot);
    notifyListeners();
  }

  void setThermalWarning(bool warning) {
    if (warning == _thermalWarning) return;
    _thermalWarning = warning;
    _gate.targetFps = _policy.targetFps(
      snapshot: _snapshot,
      thermalWarning: warning,
    );
    notifyListeners();
  }

  /// 一時停止（カメラは画面側が止める）。再開すると最初から安定を待つ。
  void setPaused(bool paused) {
    if (paused == _paused) return;
    _paused = paused;
    _resetTracking();
    notifyListeners();
  }

  /// このセッションの記録。
  LiveSession buildSession({
    required DateTime startedAt,
    required int durationSec,
    required String endedBy,
  }) => LiveSession(
    startedAt: startedAt,
    durationSec: durationSec,
    adviceCount: _adviceCount,
    followedCount: _followedCount,
    followChecks: _followChecks,
    wins: List.of(_wins),
    endedBy: endedBy,
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

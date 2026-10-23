import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/ads/interstitial_pacing.dart';

/// 全画面広告の SDK 側（読み込みと表示）。[PacedInterstitialController] のテスト用の境界。
abstract class InterstitialPort {
  /// 同意が得られていて、Pro でないとき true。
  bool get enabled;

  Future<void> load();

  /// 表示して、閉じられたら true。出せなかったら false。
  Future<bool> show();
}

/// 全画面広告（`next_hand_interstitial`）の出し方の制御（設計書 10 章、仕様 9 章）。
/// - 最初の 3 回の結果では出さない
/// - 結果 3 回につき最大 1 回、かつ前回から 4 分以上
/// - 共有した直後は出さない
/// 回数の記録は [InterstitialPacing]（再起動をまたぐ）。
class PacedInterstitialController {
  PacedInterstitialController({
    required this._pacing,
    required this._port,
    DateTime Function()? now,
    this.sharedGrace = const Duration(minutes: 2),
  }) : _now = now ?? DateTime.now;

  final Future<InterstitialPacing> Function() _pacing;
  final InterstitialPort _port;
  final DateTime Function() _now;

  /// 共有を終えてからこの間は「共有直後」として出さない。
  final Duration sharedGrace;

  DateTime? _sharedAt;

  /// Result を表示したことを数える。出せる条件に近づいたら先に読み込んでおく。
  Future<void> onResultViewed() async {
    // 新しい結果が出たら、前の共有の影響は終わり。
    _sharedAt = null;
    try {
      final pacing = await _pacing();
      await pacing.recordResult();
      if (_port.enabled && pacing.shouldShow()) await _port.load();
    } catch (error) {
      debugPrint('[Interstitial] onResultViewed failed: $error');
    }
  }

  void onShared() => _sharedAt = _now();

  bool get _sharedJustNow {
    final at = _sharedAt;
    return at != null && _now().difference(at) < sharedGrace;
  }

  /// 「次の手を撮る」の直前。条件に合えば表示し、閉じられるまで待つ。
  Future<void> maybeShowBeforeNextHand() async {
    if (!_port.enabled) return;
    try {
      final pacing = await _pacing();
      if (!pacing.shouldShow(sharedJustNow: _sharedJustNow)) return;
      if (await _port.show()) await pacing.markShown();
    } catch (error) {
      debugPrint('[Interstitial] show failed: $error');
    }
  }
}

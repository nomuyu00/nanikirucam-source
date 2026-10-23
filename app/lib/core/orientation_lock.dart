// 流用元: reference/agari_cam/lib/core/orientation_lock.dart（2026-10-21 時点）
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OrientationHandle {
  bool _released = false;
  final OrientationLock _lock;
  final _OrientationRequest _request;

  OrientationHandle._(this._lock, this._request);

  void release() {
    if (_released) return;
    _released = true;
    _lock._release(_request);
  }
}

class OrientationLock {
  OrientationLock._();

  static final OrientationLock instance = OrientationLock._();

  final List<_OrientationRequest> _stack = <_OrientationRequest>[];
  List<DeviceOrientation>? _current;

  OrientationHandle lockLandscape() {
    return _lock(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  OrientationHandle lockPortrait() {
    return _lock(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  OrientationHandle lock(List<DeviceOrientation> orientations) {
    return _lock(orientations);
  }

  void reset() {
    _stack.clear();
    _apply(DeviceOrientation.values);
  }

  OrientationHandle _lock(List<DeviceOrientation> orientations) {
    final request = _OrientationRequest(
      List<DeviceOrientation>.from(orientations),
    );
    _stack.add(request);
    _apply(request.orientations);
    return OrientationHandle._(this, request);
  }

  void _release(_OrientationRequest request) {
    final removed = _stack.remove(request);
    if (!removed) return;
    if (_stack.isEmpty) {
      _apply(DeviceOrientation.values);
    } else {
      _apply(_stack.last.orientations);
    }
  }

  void _apply(List<DeviceOrientation> orientations) {
    if (_current != null && listEquals(_current, orientations)) {
      return;
    }
    _current = List<DeviceOrientation>.from(orientations);
    unawaited(
      SystemChrome.setPreferredOrientations(
        List<DeviceOrientation>.from(orientations),
      ),
    );
  }
}

class _OrientationRequest {
  final List<DeviceOrientation> orientations;
  _OrientationRequest(this.orientations);
}

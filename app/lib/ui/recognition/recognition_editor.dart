import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';

/// 認識結果の修正画面で編集する手牌の 1 枚。
class TileSlot extends Equatable {
  const TileSlot(
    this.label, {
    this.confidence,
    this.box,
    this.alternatives = const [],
  });

  final String label;

  /// 認識の確度 0..1。手で入れた・直した牌は null。
  final double? confidence;

  /// 写真（回転後）の上での位置 0..1。手で入れた牌は null。
  final Rect? box;

  /// 修正候補（確からしい順）。
  final List<String> alternatives;

  bool get isLowConfidence =>
      confidence != null && confidence! < lowConfidenceThreshold;

  @override
  List<Object?> get props => [label, confidence, box, alternatives];
}

/// 修正画面の編集状態。[HandInput] に変換して次の画面へ渡す。
class RecognitionEditorState extends Equatable {
  RecognitionEditorState({
    required Iterable<TileSlot> slots,
    this.tsumoIndex,
    Iterable<MeldInput> melds = const [],
    Iterable<MeldInput> suggestedMelds = const [],
    Iterable<String> doraIndicators = const [],
    this.seatWind = Wind.south,
    this.roundWind = Wind.east,
    this.dealer = false,
    this.turn,
    Iterable<String> visibleTiles = const [],
  }) : slots = List.unmodifiable(slots),
       melds = List.unmodifiable(melds),
       suggestedMelds = List.unmodifiable(suggestedMelds),
       doraIndicators = List.unmodifiable(doraIndicators),
       visibleTiles = List.unmodifiable(visibleTiles);

  /// 手牌（副露を除く）。ツモ牌があれば最後。
  final List<TileSlot> slots;
  final int? tsumoIndex;
  final List<MeldInput> melds;

  /// 認識が見つけた副露の候補（まだ採用していないもの）。
  final List<MeldInput> suggestedMelds;
  final List<String> doraIndicators;
  final Wind seatWind;
  final Wind roundWind;
  final bool dealer;
  final int? turn;
  final List<String> visibleTiles;

  List<String> get labels => [for (final s in slots) s.label];

  HandInput toHandInput() => HandInput(
    tiles: labels,
    tsumoIndex: tsumoIndex,
    melds: melds,
    doraIndicators: doraIndicators,
    seatWind: seatWind,
    roundWind: roundWind,
    dealer: dealer,
    turn: turn,
    visibleTiles: visibleTiles,
  );

  /// 手牌と副露の合計での [label] の枚数（赤5は5として数える）。
  int countOf(String label) {
    final key = normalizeTileLabel(label);
    var n = 0;
    for (final s in slots) {
      if (normalizeTileLabel(s.label) == key) n++;
    }
    for (final m in melds) {
      for (final t in m.tiles) {
        if (normalizeTileLabel(t) == key) n++;
      }
    }
    return n;
  }

  /// 手牌にまだ残っていて採用できる副露候補の添字。
  List<int> get applicableSuggestions => [
    for (var i = 0; i < suggestedMelds.length; i++)
      if (_takeLabels(labels, suggestedMelds[i].tiles) != null) i,
  ];

  RecognitionEditorState copyWith({
    List<TileSlot>? slots,
    Object? tsumoIndex = _keep,
    List<MeldInput>? melds,
    List<MeldInput>? suggestedMelds,
    List<String>? doraIndicators,
    Wind? seatWind,
    Wind? roundWind,
    bool? dealer,
    Object? turn = _keep,
    List<String>? visibleTiles,
  }) {
    return RecognitionEditorState(
      slots: slots ?? this.slots,
      tsumoIndex: identical(tsumoIndex, _keep)
          ? this.tsumoIndex
          : tsumoIndex as int?,
      melds: melds ?? this.melds,
      suggestedMelds: suggestedMelds ?? this.suggestedMelds,
      doraIndicators: doraIndicators ?? this.doraIndicators,
      seatWind: seatWind ?? this.seatWind,
      roundWind: roundWind ?? this.roundWind,
      dealer: dealer ?? this.dealer,
      turn: identical(turn, _keep) ? this.turn : turn as int?,
      visibleTiles: visibleTiles ?? this.visibleTiles,
    );
  }

  static const Object _keep = Object();

  @override
  List<Object?> get props => [
    slots,
    tsumoIndex,
    melds,
    suggestedMelds,
    doraIndicators,
    seatWind,
    roundWind,
    dealer,
    turn,
    visibleTiles,
  ];
}

/// [pool] から [wanted] を 1 枚ずつ取り除いた残り。足りなければ null。
List<String>? _takeLabels(List<String> pool, List<String> wanted) {
  final rest = [...pool];
  for (final label in wanted) {
    final key = normalizeTileLabel(label);
    // 赤5を優先して同じラベルから、なければ通常の5からも取る。
    var index = rest.indexOf(label);
    if (index < 0) {
      index = rest.indexWhere((t) => normalizeTileLabel(t) == key);
    }
    if (index < 0) return null;
    rest.removeAt(index);
  }
  return rest;
}

/// 認識結果の修正画面の編集ロジック（画面から切り離して単体テストできる）。
///
/// 手牌は常に「ツモ牌以外を理牌順 + 末尾にツモ牌」に保つ。変更は [undo] で戻せる。
class RecognitionEditor extends ChangeNotifier {
  RecognitionEditor(RecognitionEditorState initial)
    : _state = _normalize(initial);

  /// 画面の引数から作る。副露の候補は採用せずに候補として持つ。
  factory RecognitionEditor.fromArgs(RecognitionArgs args) {
    final draft = args.draft;
    final base = args.base ?? HandInput.empty;
    final slots = [
      for (var i = 0; i < draft.length; i++)
        TileSlot(
          draft.labels[i],
          confidence: draft.confidences[i],
          box: draft.boxes[i],
          alternatives: draft.alternatives[i],
        ),
    ];
    return RecognitionEditor(
      RecognitionEditorState(
        slots: slots,
        tsumoIndex: draft.tsumoIndex,
        melds: base.melds,
        suggestedMelds: [
          for (final m in draft.melds)
            MeldInput(
              kind: m.kind,
              tiles: [for (final i in m.indices) draft.labels[i]],
            ),
        ],
        doraIndicators: base.doraIndicators,
        seatWind: base.seatWind,
        roundWind: base.roundWind,
        dealer: base.dealer,
        turn: base.turn,
        visibleTiles: base.visibleTiles,
      ),
    );
  }

  static const int _undoLimit = 30;

  RecognitionEditorState _state;
  final List<RecognitionEditorState> _undo = [];
  TileSlot? _lastEdited;

  RecognitionEditorState get state => _state;
  bool get canUndo => _undo.isNotEmpty;

  /// 直前に直した・足した牌の今の添字（強調表示用）。なければ null。
  int? get lastEditedIndex {
    final edited = _lastEdited;
    if (edited == null) return null;
    final index = _state.slots.indexWhere((s) => identical(s, edited));
    return index < 0 ? null : index;
  }

  HandInput get input => _state.toHandInput();

  // --- 手牌 ---------------------------------------------------------------

  /// [index] の牌を [label] に直す。確度は手入力扱い（null）になる。
  void replaceTile(int index, String label) {
    if (index < 0 || index >= _state.slots.length) return;
    final slots = [..._state.slots];
    final edited = TileSlot(label);
    slots[index] = edited;
    _apply(_state.copyWith(slots: slots), edited: edited);
  }

  void removeTile(int index) {
    if (index < 0 || index >= _state.slots.length) return;
    final slots = [..._state.slots]..removeAt(index);
    final tsumo = _state.tsumoIndex;
    _apply(
      _state.copyWith(
        slots: slots,
        tsumoIndex: tsumo == null || tsumo == index
            ? null
            : (tsumo > index ? tsumo - 1 : tsumo),
      ),
    );
  }

  /// 牌を 1 枚足す。ツモ牌があるときは、その手前の理牌順の位置に入る。
  void addTile(String label) {
    final added = TileSlot(label);
    _apply(_state.copyWith(slots: [..._state.slots, added]), edited: added);
  }

  /// [index] の牌をツモ牌にする。すでにツモ牌なら解除する。
  void toggleTsumo(int index) {
    if (index < 0 || index >= _state.slots.length) return;
    _apply(
      _state.copyWith(tsumoIndex: _state.tsumoIndex == index ? null : index),
    );
  }

  // --- 副露 ---------------------------------------------------------------

  /// 副露を足す。手牌に同じ牌があれば、その分を手牌から外す（認識が副露の牌を
  /// 手牌として拾っていた場合に、枚数を合わせるため）。
  void addMeld(MeldInput meld) {
    _apply(_withoutTiles(meld.tiles).copyWith(melds: [..._state.melds, meld]));
  }

  /// 副露の候補 [suggestionIndex] を採用する。
  void applySuggestedMeld(int suggestionIndex) {
    if (suggestionIndex < 0 ||
        suggestionIndex >= _state.suggestedMelds.length) {
      return;
    }
    final meld = _state.suggestedMelds[suggestionIndex];
    if (_takeLabels(_state.labels, meld.tiles) == null) return;
    final suggestions = [..._state.suggestedMelds]..removeAt(suggestionIndex);
    _apply(
      _withoutTiles(
        meld.tiles,
      ).copyWith(melds: [..._state.melds, meld], suggestedMelds: suggestions),
    );
  }

  /// 副露の候補を捨てる。
  void dismissSuggestedMeld(int suggestionIndex) {
    if (suggestionIndex < 0 ||
        suggestionIndex >= _state.suggestedMelds.length) {
      return;
    }
    final suggestions = [..._state.suggestedMelds]..removeAt(suggestionIndex);
    _apply(_state.copyWith(suggestedMelds: suggestions));
  }

  /// 副露をやめて、牌を手牌に戻す。
  void removeMeld(int meldIndex) {
    if (meldIndex < 0 || meldIndex >= _state.melds.length) return;
    final meld = _state.melds[meldIndex];
    final melds = [..._state.melds]..removeAt(meldIndex);
    _apply(
      _state.copyWith(
        melds: melds,
        slots: [..._state.slots, for (final t in meld.tiles) TileSlot(t)],
      ),
    );
  }

  /// 槓の明槓・暗槓を切り替える（見た目では区別できないのでユーザーが選ぶ）。
  void setMeldKind(int meldIndex, MeldKind kind) {
    if (meldIndex < 0 || meldIndex >= _state.melds.length) return;
    final melds = [..._state.melds];
    melds[meldIndex] = MeldInput(kind: kind, tiles: melds[meldIndex].tiles);
    _apply(_state.copyWith(melds: melds));
  }

  // --- 局の条件 -------------------------------------------------------------

  /// 自風。東なら親、それ以外は子にそろえる。
  void setSeatWind(Wind wind) =>
      _apply(_state.copyWith(seatWind: wind, dealer: wind == Wind.east));

  void setRoundWind(Wind wind) => _apply(_state.copyWith(roundWind: wind));

  /// 親・子。親なら自風を東に、子で自風が東なら南にそろえる。
  void setDealer(bool dealer) {
    if (dealer) {
      _apply(_state.copyWith(seatWind: Wind.east, dealer: true));
    } else {
      _apply(
        _state.copyWith(
          seatWind: _state.seatWind == Wind.east ? Wind.south : _state.seatWind,
          dealer: false,
        ),
      );
    }
  }

  /// 巡目（1〜[HandInput.maxTurn]）。null で未指定。
  void setTurn(int? turn) {
    final value = turn?.clamp(1, HandInput.maxTurn);
    _apply(_state.copyWith(turn: value));
  }

  void setDoraIndicators(List<String> indicators) {
    _apply(_state.copyWith(doraIndicators: indicators));
  }

  // --- 戻す -----------------------------------------------------------------

  void undo() {
    if (_undo.isEmpty) return;
    _state = _undo.removeLast();
    _lastEdited = null;
    notifyListeners();
  }

  // --- 内部 -----------------------------------------------------------------

  /// 手牌から [labels] を 1 枚ずつ外した状態。
  RecognitionEditorState _withoutTiles(List<String> labels) {
    final slots = [..._state.slots];
    int? tsumo = _state.tsumoIndex;
    for (final label in labels) {
      var index = slots.indexWhere((s) => s.label == label);
      if (index < 0) {
        index = slots.indexWhere(
          (s) => normalizeTileLabel(s.label) == normalizeTileLabel(label),
        );
      }
      if (index < 0) continue;
      slots.removeAt(index);
      if (tsumo != null) {
        if (tsumo == index) {
          tsumo = null;
        } else if (tsumo > index) {
          tsumo = tsumo - 1;
        }
      }
    }
    return _state.copyWith(slots: slots, tsumoIndex: tsumo);
  }

  void _apply(RecognitionEditorState next, {TileSlot? edited}) {
    final normalized = _normalize(next);
    _lastEdited = edited;
    if (normalized == _state) return;
    _undo.add(_state);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _state = normalized;
    notifyListeners();
  }

  /// ツモ牌以外を理牌順に並べ、ツモ牌を末尾に置く。
  static RecognitionEditorState _normalize(RecognitionEditorState state) {
    final tsumo = state.tsumoIndex;
    final valid = tsumo != null && tsumo >= 0 && tsumo < state.slots.length;
    final rest = <TileSlot>[];
    TileSlot? drawn;
    for (var i = 0; i < state.slots.length; i++) {
      if (valid && i == tsumo) {
        drawn = state.slots[i];
      } else {
        rest.add(state.slots[i]);
      }
    }
    // 同じ牌の並びは元の順を保つ（List.sort は安定ではないので添字で補う）。
    final order = List<int>.generate(rest.length, (i) => i)
      ..sort((a, b) {
        final c = compareTileLabels(rest[a].label, rest[b].label);
        return c != 0 ? c : a.compareTo(b);
      });
    final slots = [for (final i in order) rest[i], ?drawn];
    return state.copyWith(
      slots: slots,
      tsumoIndex: drawn == null ? null : slots.length - 1,
    );
  }
}

/// 修正画面の下部に常時出す、シャンテン数と受け入れのプレビュー（仕様 6.6）。
class HandPreview extends Equatable {
  const HandPreview({
    required this.tileCount,
    required this.shanten,
    required this.type,
    required this.ukeireTotal,
    required this.ukeireKinds,
    this.bestDiscardId,
  });

  /// 13 か 14。
  final int tileCount;

  /// -1 = 和了形、0 = テンパイ、1 = 一向聴 …。14 枚のときは最良の打牌後の値。
  final int shanten;
  final ShantenType type;

  /// 受け入れ（引くとシャンテンが進む牌）の合計枚数と種類数。14 枚のときは最良の打牌後。
  final int ukeireTotal;
  final int ukeireKinds;

  /// 14 枚のときの、速さ軸で最良の打牌（34 種の id）。和了形や 13 枚では null。
  final int? bestDiscardId;

  bool get isComplete => shanten < 0;

  @override
  List<Object?> get props => [
    tileCount,
    shanten,
    type,
    ukeireTotal,
    ukeireKinds,
    bestDiscardId,
  ];
}

/// [input] の簡易プレビュー。解析できない入力（枚数が 13/14 でないなど）は null。
HandPreview? previewHand(HandInput input) {
  if (!input.isAnalyzable) return null;
  final hand = input.toHandState();
  if (hand.tileCount == HandInput.maxTileCount) {
    final whole = shanten(hand);
    if (whole.shanten < 0) {
      return HandPreview(
        tileCount: 14,
        shanten: -1,
        type: whole.type,
        ukeireTotal: 0,
        ukeireKinds: 0,
      );
    }
    final best = rankDiscards(hand).first;
    return HandPreview(
      tileCount: 14,
      shanten: best.shantenAfter,
      type: whole.type,
      ukeireTotal: best.ukeire.total,
      ukeireKinds: best.ukeire.kinds,
      bestDiscardId: best.discardId,
    );
  }
  final result = shanten(hand);
  final draws = result.shanten < 0 ? Ukeire(const {}) : ukeire(hand);
  return HandPreview(
    tileCount: 13,
    shanten: result.shanten,
    type: result.type,
    ukeireTotal: draws.total,
    ukeireKinds: draws.kinds,
  );
}

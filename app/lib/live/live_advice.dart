import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

/// 案内の種類。
enum LiveAdviceKind {
  /// 14 枚: 切る牌の案内。
  discard,

  /// 13 枚: シャンテン・待ち・役なし・リーチ可否。
  thirteen,

  /// 14 枚が和了形（ツモ）。
  win,
}

/// 枠の色分け（仕様 6.3: 面子＝緑、搭子＝青、孤立＝灰）。
enum LiveTileRole { meld, partial, isolated }

/// stable な手の解析結果と、画面に出す案内（設計書 3.3）。
class LiveAdvice {
  LiveAdvice({
    required this.handKey,
    required this.input,
    required this.report,
    this.roles = const [],
  });

  /// [TrackerSnapshot.handKey] と同じ値。手が変わったら案内を出さない。
  final String handKey;
  final HandInput input;
  final AnalysisReport report;

  /// スロットごとの役割（左から。分解できなければ空）。
  final List<LiveTileRole> roles;

  int get handSize => input.tileCount;

  LiveAdviceKind get kind {
    if (handSize == 13) return LiveAdviceKind.thirteen;
    if (report.win != null) return LiveAdviceKind.win;
    return LiveAdviceKind.discard;
  }

  /// [axis] の 1 位の打牌（同順位は牌 id の小さい方）。14 枚以外は null。
  int? discardFor(StrategyAxis axis) {
    final best = report.bestByAxis[axis];
    if (best == null || best.isEmpty) return null;
    return best.first;
  }

  /// 軸ごとの 1 位。
  Map<StrategyAxis, int> get bestPerAxis => {
    for (final axis in StrategyAxis.values)
      if (discardFor(axis) != null) axis: discardFor(axis)!,
  };

  /// 3 軸の 1 位が同じ牌（「一択」）。
  bool get unanimous => bestPerAxis.values.toSet().length <= 1;

  /// [discardId] を 1 位にしている軸（バッジ）。
  List<StrategyAxis> axesFor(int discardId) => [
    for (final e in bestPerAxis.entries)
      if (e.value == discardId) e.key,
  ];

  DiscardCandidate? candidate(int discardId) {
    for (final c in report.candidates) {
      if (c.discardId == discardId) return c;
    }
    return null;
  }

  /// 打牌後のシャンテン数の表示用（14 枚の候補）。
  int? shantenAfter(int discardId) => candidate(discardId)?.shantenAfter;

  /// 狙える役（消えるを除く）を最大 [max] 件。ドラは枚数つきで最後に。
  List<YakuProspect> prospects(int discardId, {int max = 3}) {
    final c = candidate(discardId);
    if (c == null) return const [];
    return [
      for (final y in c.yaku)
        if (y.confidence != YakuConfidence.lost && !y.yaku.isDora) y,
    ].take(max).toList();
  }

  /// 想定打点（門前はリーチ込み）。経路が無ければ null。
  PointRange? points(int discardId) {
    final c = candidate(discardId);
    if (c == null) return null;
    final range = c.riichiPoints ?? c.points;
    return range.max == 0 ? null : range;
  }
}

/// 14 枚の案内の牌が、次に stable になった 13 枚で切られていたか（採用率、設計書 3.3）。
///
/// 13 枚が 14 枚の部分集合（1 枚切っただけ）のときだけ判定する。別の手（誤認識・次の局）は
/// 判定しない。
class AdviceFollowTracker {
  List<int>? _counts;
  int? _discardId;

  bool get hasPending => _discardId != null;
  int? get pendingDiscard => _discardId;

  /// 14 枚の手 [counts14] で [discardId] を案内した（軸を切り替えたら呼び直す）。
  void onDiscardAdvice(List<int> counts14, int discardId) {
    _counts = List.of(counts14);
    _discardId = discardId;
  }

  /// 13 枚が stable になった。判定できれば採用したか、できなければ null。
  bool? onStableThirteen(List<int> counts13) {
    final before = _counts;
    final discard = _discardId;
    if (before == null || discard == null) return null;
    _counts = null;
    _discardId = null;
    var removed = 0;
    for (var i = 0; i < before.length && i < counts13.length; i++) {
      final d = before[i] - counts13[i];
      if (d < 0) return null; // 増えた牌がある = 別の手
      removed += d;
    }
    if (removed != 1) return null;
    return counts13[discard] < before[discard];
  }

  void clear() {
    _counts = null;
    _discardId = null;
  }
}

/// 手牌の牌 id ごとの枚数（長さ 34）。
List<int> countsOfLabels(Iterable<String> labels) {
  final counts = List<int>.filled(kTileKinds, 0);
  for (final label in labels) {
    final id = tileIdFromLabel(label);
    if (id >= 0) counts[id]++;
  }
  return counts;
}

/// 打牌 [discardId] を指すスロット（左からの添字）。同じ牌が複数あるときは、
/// ツモ牌（[tsumoIndex]）→ 赤でない牌 → 右側 の順に選ぶ（赤5は残す方がよい）。
int? slotForDiscard(List<String> labels, int discardId, {int? tsumoIndex}) {
  final slots = [
    for (var i = 0; i < labels.length; i++)
      if (tileIdFromLabel(labels[i]) == discardId) i,
  ];
  if (slots.isEmpty) return null;
  if (tsumoIndex != null && slots.contains(tsumoIndex)) {
    final label = labels[tsumoIndex];
    final otherNormal = slots.any(
      (i) => i != tsumoIndex && !labels[i].startsWith('0'),
    );
    if (!label.startsWith('0') || !otherNormal) return tsumoIndex;
  }
  final normal = slots.where((i) => !labels[i].startsWith('0')).toList();
  return (normal.isNotEmpty ? normal : slots).last;
}

/// ブロック分解（`decomposeBlocks`）から、スロットごとの役割を求める。失敗したら空。
List<LiveTileRole> rolesForSlots(List<String> labels, HandState hand) {
  try {
    final blocks = decomposeBlocks(hand);
    final roles = List<LiveTileRole?>.filled(labels.length, null);
    for (final block in blocks) {
      if (block.declared) continue;
      final role = switch (block.role) {
        BlockRole.meld => LiveTileRole.meld,
        BlockRole.isolated => LiveTileRole.isolated,
        _ => LiveTileRole.partial,
      };
      for (final id in block.tileIds) {
        for (var i = 0; i < labels.length; i++) {
          if (roles[i] == null && tileIdFromLabel(labels[i]) == id) {
            roles[i] = role;
            break;
          }
        }
      }
    }
    return [for (final r in roles) r ?? LiveTileRole.isolated];
  } catch (_) {
    return const [];
  }
}

/// 和了の格（`live_win_detected{rank}`）。切り上げ満貫は数えない（Mリーグ相当）。
/// 段階の判定は mahjong_core の [winHandRank] に寄せる（数え役満も 'yakuman'）。
String winRank({
  required int han,
  required int fu,
  List<Yaku> yaku = const [],
}) {
  final yakuman = yaku.any((y) => yakuIdOf(y)?.isYakuman ?? false);
  final rank = winHandRank(
    han: han,
    fu: fu,
    yakumanMultiplier: yakuman ? 1 : 0,
    ruleset: Rulesets.mLeague(),
  );
  return switch (rank) {
    HandRank.none => 'none',
    HandRank.mangan => 'mangan',
    HandRank.haneman => 'haneman',
    HandRank.baiman => 'baiman',
    HandRank.sanbaiman => 'sanbaiman',
    _ => 'yakuman',
  };
}

/// 役の一覧（日本語名。役牌は「役牌 中」のように）。ドラ類は枚数をまとめる。
List<String> yakuNames(HandScore score) {
  final names = <String>[];
  final dora = <String, int>{};
  for (final y in score.yaku) {
    final id = yakuIdOf(y);
    if (id != null && id.isDora) {
      // ドラは「ドラ」1 件に翻数＝枚数が入っている（ruleset_support.dart の doraYaku）。
      final n = y.hanClosed > 0 ? y.hanClosed : 1;
      dora.update(id.jaName, (v) => v + n, ifAbsent: () => n);
      continue;
    }
    names.add(id?.jaName ?? y.name);
  }
  for (final e in dora.entries) {
    names.add(e.value > 1 ? '${e.key}${e.value}' : e.key);
  }
  return names;
}

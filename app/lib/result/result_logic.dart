import 'package:mahjong_core/mahjong_core.dart';

/// Result・Quiz・CandidateDetail が共有する、解析結果の読み方（仕様 4 章・7.3）。
/// 画面に依存しない純粋な関数だけを置く（テストしやすくするため）。

/// 画面の軸の切り替えボタンの並び（仕様 4.1）。
const List<StrategyAxis> kAxisOrder = [
  StrategyAxis.speed,
  StrategyAxis.points,
  StrategyAxis.balance,
];

/// 既定の軸（仕様 4.1: バランス）。
const StrategyAxis kDefaultAxis = StrategyAxis.balance;

/// 無料で見せる候補の数（仕様 4.2: 選択中の軸で上位 3 件）。
const int kFreeCandidateCount = 3;

/// 候補ごとに見せる役の数（仕様 4.2: 最大 3 つ）。
const int kMaxYakuShown = 3;

/// 軸の 1 位（同順位はすべて、牌 id の昇順）。13 枚なら空。
List<int> bestOf(AnalysisReport report, StrategyAxis axis) =>
    report.bestByAxis[axis] ?? const [];

/// 3 軸の答えの関係（仕様 4.1）。
enum AnswerAgreement {
  /// 3 軸とも同じ 1 枚（「一択」）。
  single,

  /// 3 軸とも同じだが、同点の牌が複数ある。
  sameTie,

  /// 軸によって答えが違う（バッジを付けて並べる）。
  split,

  /// 候補が無い（13 枚）。
  none,
}

AnswerAgreement agreementOf(AnalysisReport report) {
  if (report.candidates.isEmpty) return AnswerAgreement.none;
  final sets = [
    for (final axis in kAxisOrder) bestOf(report, axis).toSet(),
  ];
  final first = sets.first;
  final same = sets.every(
    (s) => s.length == first.length && s.containsAll(first),
  );
  if (!same) return AnswerAgreement.split;
  return first.length == 1 ? AnswerAgreement.single : AnswerAgreement.sameTie;
}

/// [discardId] がどの軸の 1 位か（バッジ「最速」「高打点」「バランス」）。
List<StrategyAxis> bestAxesOf(AnalysisReport report, int discardId) => [
  for (final axis in kAxisOrder)
    if (bestOf(report, axis).contains(discardId)) axis,
];

/// [axis] の順位で並べた候補。打点軸で除外された候補（順位が無い）は後ろに、
/// 速さの順位 → 牌 id の順で並べる。
List<DiscardCandidate> orderedCandidates(
  AnalysisReport report,
  StrategyAxis axis,
) {
  final list = [...report.candidates];
  list.sort((a, b) {
    final ra = a.rankByAxis[axis];
    final rb = b.rankByAxis[axis];
    if (ra != null && rb != null) {
      final c = ra.compareTo(rb);
      if (c != 0) return c;
    } else if (ra != null) {
      return -1;
    } else if (rb != null) {
      return 1;
    }
    final sa = a.rankByAxis[StrategyAxis.speed] ?? 99;
    final sb = b.rankByAxis[StrategyAxis.speed] ?? 99;
    final c = sa.compareTo(sb);
    return c != 0 ? c : a.discardId.compareTo(b.discardId);
  });
  return list;
}

/// 画面に出す候補（無料は上位 [kFreeCandidateCount] 件、Pro は全件。仕様 4.2）。
List<DiscardCandidate> visibleCandidates(
  AnalysisReport report,
  StrategyAxis axis, {
  required bool pro,
}) {
  final ordered = orderedCandidates(report, axis);
  return pro ? ordered : ordered.take(kFreeCandidateCount).toList();
}

/// 候補 [discardId] を探す。無ければ null。
DiscardCandidate? candidateOf(AnalysisReport report, int discardId) =>
    report.candidates.where((c) => c.discardId == discardId).firstOrNull;

/// クイズの判定（仕様 3.4: 選んだ戦略軸の解と一致で正解。別の軸の解と一致したら
/// 「打点重視なら正解」）。
class QuizVerdict {
  const QuizVerdict({
    required this.chosenId,
    required this.axis,
    required this.correct,
    required this.otherCorrectAxes,
    this.rank,
  });

  final int chosenId;

  /// 判定した軸。
  final StrategyAxis axis;

  /// [axis] の 1 位と一致した（同点の 1 位も正解）。
  final bool correct;

  /// [axis] 以外で 1 位と一致した軸（[kAxisOrder] の順）。
  final List<StrategyAxis> otherCorrectAxes;

  /// [axis] での順位（打点軸で除外された・候補に無いときは null）。
  final int? rank;

  /// `quiz_answered{correct_axis}`: 正解なら [axis]、別の軸なら最初のその軸、どれでも
  /// なければ `none`。
  String get correctAxisCode => correct
      ? axis.name
      : (otherCorrectAxes.isEmpty ? 'none' : otherCorrectAxes.first.name);
}

QuizVerdict judgeChoice(
  AnalysisReport report,
  int chosenId,
  StrategyAxis axis,
) {
  final correct = bestOf(report, axis).contains(chosenId);
  return QuizVerdict(
    chosenId: chosenId,
    axis: axis,
    correct: correct,
    otherCorrectAxes: [
      for (final other in kAxisOrder)
        if (other != axis && bestOf(report, other).contains(chosenId)) other,
    ],
    rank: candidateOf(report, chosenId)?.rankByAxis[axis],
  );
}

/// 無料の想定打点の目安（仕様 5 章「安い／普通／高い と代表値」）。
enum PointsLevel { cheap, normal, high }

/// 子は 2,600 点以下が安い・8,000 点（満貫）以上が高い。親は 3,900 点以下・12,000 点以上。
PointsLevel pointsLevelOf(int points, {required bool dealer}) {
  final high = dealer ? 12000 : 8000;
  final cheap = dealer ? 3900 : 2600;
  if (points >= high) return PointsLevel.high;
  if (points <= cheap) return PointsLevel.cheap;
  return PointsLevel.normal;
}

/// 候補ごとに見せる役（最大 [max] 件）。
///
/// 並びは「確定・濃厚・狙える の役 → ドラ → リーチ → 消える役」。消える役（Pro のみ
/// エンジンが返す）があれば 1 枠は残す（仕様 4.6 の「タンヤオ（消える）」）。
/// リーチは門前ならいつも付くので、他の役より後ろにする。
List<YakuProspect> pickYaku(DiscardCandidate c, {int max = kMaxYakuShown}) {
  bool lost(YakuProspect y) => y.confidence == YakuConfidence.lost;
  final real = [
    for (final y in c.yaku)
      if (!lost(y) && !y.yaku.isDora && y.yaku != YakuId.riichi) y,
  ];
  final dora = [
    for (final y in c.yaku)
      if (!lost(y) && y.yaku.isDora) y,
  ];
  final riichi = [
    for (final y in c.yaku)
      if (!lost(y) && y.yaku == YakuId.riichi) y,
  ];
  final lostList = [
    for (final y in c.yaku)
      if (lost(y)) y,
  ];
  final positives = [...real, ...dora, ...riichi];
  final reserve = lostList.isEmpty ? 0 : 1;
  final picked = positives.take(max - reserve).toList();
  picked.addAll(lostList.take(max - picked.length));
  return picked;
}

/// シャンテン数の変化（仕様 4.2「一向聴のまま」「テンパイ」）。
enum ShantenChange {
  /// 打牌後にテンパイ。
  tenpai,

  /// 最良のシャンテン数のまま。
  keep,

  /// 最良より戻る。
  back,
}

ShantenChange shantenChangeOf(AnalysisReport report, DiscardCandidate c) {
  if (c.shantenAfter == 0) return ShantenChange.tenpai;
  final best = report.candidates
      .map((x) => x.shantenAfter)
      .fold<int>(99, (a, b) => a < b ? a : b);
  return c.shantenAfter <= best ? ShantenChange.keep : ShantenChange.back;
}

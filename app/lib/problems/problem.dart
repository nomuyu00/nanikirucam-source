import 'package:equatable/equatable.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/account.dart';

/// 公開問題のデータ型（`app/functions/API.md` 3 章）。Firebase には依存しない。

/// 手牌 [input] の中で、牌 id [tileId] に当たる牌のラベル（なければ null）。
///
/// 手牌に通常の 5 と赤 5 の両方があるときは通常の 5 を返す。サーバーは解のラベルに
/// 5 でも 0 でも受け付ける（API.md 1.2）が、手牌にない牌は `invalid_answer` になる。
String? tileLabelInHand(HandInput input, int tileId) {
  String? red;
  for (final label in input.tiles) {
    if (tileIdFromLabel(label) != tileId) continue;
    if (!label.startsWith('0')) return label;
    red ??= label;
  }
  return red;
}

/// 回答の集計（`problems/{id}.stats` と `POST /api/answer` の `stats`）。
class ProblemStats extends Equatable {
  const ProblemStats({
    this.total = 0,
    this.correct = 0,
    this.byTile = const {},
  });

  factory ProblemStats.fromJson(Object? json) {
    if (json is! Map) return const ProblemStats();
    final byTile = <String, int>{};
    final raw = json['byTile'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is num) byTile[entry.key.toString()] = value.toInt();
      }
    }
    return ProblemStats(
      total: _int(json['total']),
      correct: _int(json['correct']),
      byTile: byTile,
    );
  }

  static const empty = ProblemStats();

  /// 回答した人数。
  final int total;

  /// バランス軸の解と一致した人数。
  final int correct;

  /// 牌ラベルごとの回答数（分布）。
  final Map<String, int> byTile;

  /// 正解率（0〜1）。回答がまだなければ null。
  double? get correctRate => total <= 0 ? null : correct / total;

  /// 正解率の％（四捨五入）。回答がなければ null。
  int? get correctPercent {
    final rate = correctRate;
    return rate == null ? null : (rate * 100).round();
  }

  @override
  List<Object?> get props => [total, correct, byTile];
}

int _int(Object? value) => value is num ? value.toInt() : 0;

/// 問題の正解（`publishProblem` の `answer` と `POST /api/answer` の `answer`、API.md 1.2）。
///
/// アプリのエンジン（[AnalysisReport]）の結果から作る。ラベルは手牌の牌。
class PublishedAnswer extends Equatable {
  PublishedAnswer({
    required Map<StrategyAxis, List<String>> byAxis,
    required this.ukeireKinds,
    required this.ukeireTotal,
    required this.shanten,
    required this.engineVersion,
  }) : byAxis = Map.unmodifiable({
         for (final entry in byAxis.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  /// 14 枚の手の解析結果から作る。13 枚の手（候補なし）は [StateError]。
  factory PublishedAnswer.fromReport(AnalysisReport report, HandInput input) {
    final balance = report.bestByAxis[StrategyAxis.balance];
    if (report.candidates.isEmpty || balance == null || balance.isEmpty) {
      throw StateError('14 枚の手の解析結果が必要です');
    }
    final byAxis = <StrategyAxis, List<String>>{};
    for (final axis in StrategyAxis.values) {
      final labels = <String>[];
      for (final id in report.bestByAxis[axis] ?? const <int>[]) {
        final label = tileLabelInHand(input, id);
        if (label != null && !labels.contains(label)) labels.add(label);
      }
      byAxis[axis] = labels;
    }
    final best = report.candidates.firstWhere(
      (c) => c.discardId == balance.first,
      orElse: () => report.candidates.first,
    );
    return PublishedAnswer(
      byAxis: byAxis,
      ukeireKinds: best.ukeire.kinds.clamp(0, 34),
      ukeireTotal: best.ukeire.total.clamp(0, 136),
      shanten: best.shantenAfter.clamp(-1, 8),
      engineVersion: report.engineVersion,
    );
  }

  factory PublishedAnswer.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('answer がオブジェクトではない');
    }
    final byAxis = <StrategyAxis, List<String>>{};
    final raw = json['byAxis'];
    for (final axis in StrategyAxis.values) {
      final list = raw is Map ? raw[axis.name] : null;
      byAxis[axis] = list is List ? [for (final e in list) e.toString()] : [];
    }
    final ukeire = json['ukeire'];
    return PublishedAnswer(
      byAxis: byAxis,
      ukeireKinds: ukeire is Map ? _int(ukeire['kinds']) : 0,
      ukeireTotal: ukeire is Map ? _int(ukeire['total']) : 0,
      shanten: _int(json['shanten']),
      engineVersion: json['engineVersion']?.toString() ?? '',
    );
  }

  /// 軸ごとの 1 位の牌（同順位は複数）。
  final Map<StrategyAxis, List<String>> byAxis;

  /// バランス軸の解を切った後の受け入れ（種類数・枚数）。
  final int ukeireKinds;
  final int ukeireTotal;

  /// バランス軸の解を切った後のシャンテン数。
  final int shanten;

  final String engineVersion;

  /// 正解（バランス軸の 1 位）。
  List<String> get correctTiles => byAxis[StrategyAxis.balance] ?? const [];

  Map<String, Object?> toJson() => {
    'byAxis': {
      for (final axis in StrategyAxis.values) axis.name: byAxis[axis] ?? [],
    },
    'ukeire': {'kinds': ukeireKinds, 'total': ukeireTotal},
    'shanten': shanten,
    'engineVersion': engineVersion,
  };

  @override
  List<Object?> get props => [
    byAxis,
    ukeireKinds,
    ukeireTotal,
    shanten,
    engineVersion,
  ];
}

/// 公開問題 1 件（`problems/{problemId}`）。正解は含まない（API.md 3.2）。
class Problem extends Equatable {
  const Problem({
    required this.id,
    required this.input,
    this.authorUid = '',
    this.authorNickname = '',
    this.createdAt,
    this.locale = 'ja',
    this.stats = ProblemStats.empty,
    this.hidden = false,
    this.reports = 0,
    this.cardPath,
    this.featuredDaily,
  });

  /// ドキュメントの中身（[normalizeFirestoreMap] を通した形）から作る。
  /// 手牌が読めなければ [FormatException]。
  factory Problem.fromData(String id, Map<String, Object?> data) {
    final input = HandInput.fromJson({
      'tiles': data['tiles'],
      'tsumoIndex': data['tsumoIndex'],
      'melds': data['melds'],
      'dora': data['dora'],
      'seatWind': data['seatWind'],
      'roundWind': data['roundWind'],
      'turn': data['turn'],
    });
    final featured = data['featured'];
    return Problem(
      id: id,
      input: input,
      authorUid: data['authorUid']?.toString() ?? '',
      authorNickname: data['authorNickname']?.toString() ?? '',
      createdAt: parseDateTime(data['createdAt']),
      locale: data['locale']?.toString() ?? 'ja',
      stats: ProblemStats.fromJson(data['stats']),
      hidden: data['hidden'] == true,
      reports: _int(data['reports']),
      cardPath: data['cardPath']?.toString(),
      featuredDaily: featured is Map ? featured['daily']?.toString() : null,
    );
  }

  final String id;

  /// 手（ツモ牌が末尾）。
  final HandInput input;
  final String authorUid;

  /// 出題者名。空なら匿名。
  final String authorNickname;
  final DateTime? createdAt;
  final String locale;
  final ProblemStats stats;

  /// 通報などで非表示になっている（出題者本人にだけ見える）。
  final bool hidden;
  final int reports;
  final String? cardPath;
  final String? featuredDaily;

  bool isAuthoredBy(String? uid) =>
      uid != null && uid.isNotEmpty && authorUid == uid;

  @override
  List<Object?> get props => [
    id,
    input,
    authorUid,
    authorNickname,
    createdAt,
    locale,
    stats,
    hidden,
    reports,
    cardPath,
    featuredDaily,
  ];
}

/// 今日の問題（`daily/{date}`）。公式 1 問とユーザー投稿 0〜2 問。
class DailyProblems extends Equatable {
  const DailyProblems({
    required this.date,
    this.official,
    this.picks = const [],
  });

  /// 問題がまだない日（`pickDaily` が動く前など）。
  const DailyProblems.empty(this.date) : official = null, picks = const [];

  /// JST の `YYYY-MM-DD`。
  final String date;
  final Problem? official;
  final List<Problem> picks;

  List<Problem> get all => [?official, ...picks];

  bool get isEmpty => official == null && picks.isEmpty;

  @override
  List<Object?> get props => [date, official, picks];
}

/// アプリからの回答（`POST /api/answer`）に対するサーバーの返事（API.md 2.1）。
///
/// Quiz 画面が [ProblemAnswerSubmitter.submit] で受け取り、`ResultArgs.problemOutcome`
/// に入れて Result 画面へ渡す。Result は分布（[stats]）・正解（[answer]）・各軸の正誤
/// （[judgement]）を表示に使える。
class ProblemAnswerOutcome extends Equatable {
  ProblemAnswerOutcome({
    required this.yourTile,
    required this.correct,
    Map<StrategyAxis, bool> judgement = const {},
    required this.stats,
    required this.answer,
    this.alreadyAnswered = false,
  }) : judgement = Map.unmodifiable(judgement);

  factory ProblemAnswerOutcome.fromJson(Map<String, Object?> json) {
    final judgement = <StrategyAxis, bool>{};
    final raw = json['judgement'];
    for (final axis in StrategyAxis.values) {
      if (raw is Map && raw[axis.name] is bool) {
        judgement[axis] = raw[axis.name] as bool;
      }
    }
    return ProblemAnswerOutcome(
      yourTile: json['yourTile']?.toString() ?? '',
      correct: json['correct'] == true,
      judgement: judgement,
      stats: ProblemStats.fromJson(json['stats']),
      answer: PublishedAnswer.fromJson(json['answer']),
      alreadyAnswered: json['alreadyAnswered'] == true,
    );
  }

  /// 選んだ牌（手牌の牌ラベル）。2 回目の回答なら最初の回答。
  final String yourTile;

  /// バランス軸の解と一致したか（`stats.correct` に数える基準）。
  final bool correct;

  /// 各軸の解と一致したか（赤 5 は 5 と同一視）。
  final Map<StrategyAxis, bool> judgement;

  /// この回答を含む集計。
  final ProblemStats stats;

  /// 正解（3 軸の解・受け入れ・シャンテン）。
  final PublishedAnswer answer;

  /// 同じ uid の 2 回目の回答だった（集計は増えない）。
  final bool alreadyAnswered;

  /// 一致した軸（バランスを優先）。どれにも一致しなければ null。
  StrategyAxis? get matchedAxis {
    for (final axis in const [
      StrategyAxis.balance,
      StrategyAxis.speed,
      StrategyAxis.points,
    ]) {
      if (judgement[axis] == true) return axis;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    yourTile,
    correct,
    judgement,
    stats,
    answer,
    alreadyAnswered,
  ];
}

/// 通報の理由（API.md 1.3）。
enum ProblemReportReason {
  spam,
  offensive,
  wrongAnswer,
  other;

  /// サーバーに送る値。
  String get wireValue => switch (this) {
    ProblemReportReason.wrongAnswer => 'wrong_answer',
    _ => name,
  };
}

/// `reportProblem` の結果。
class ProblemReportResult extends Equatable {
  const ProblemReportResult({
    required this.reported,
    this.alreadyReported = false,
    this.hidden = false,
  });

  factory ProblemReportResult.fromJson(Map<String, Object?> json) =>
      ProblemReportResult(
        reported: json['reported'] == true,
        alreadyReported: json['alreadyReported'] == true,
        hidden: json['hidden'] == true,
      );

  final bool reported;
  final bool alreadyReported;
  final bool hidden;

  @override
  List<Object?> get props => [reported, alreadyReported, hidden];
}

/// JST（UTC+9）の `YYYY-MM-DD`（`daily/{date}` のキー）。
String jstDateString(DateTime now) {
  final jst = now.toUtc().add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${jst.year.toString().padLeft(4, '0')}-${two(jst.month)}-${two(jst.day)}';
}

/// `YYYY-MM-DD` の翌日。形式が違えば null。
String? nextDateString(String date) => _shiftDate(date, 1);

/// `YYYY-MM-DD` の前日。形式が違えば null。
String? previousDateString(String date) => _shiftDate(date, -1);

String? _shiftDate(String date, int days) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return null;
  final moved = parsed.add(Duration(days: days));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${moved.year.toString().padLeft(4, '0')}-${two(moved.month)}-${two(moved.day)}';
}

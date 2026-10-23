import 'dart:async';
import 'dart:isolate';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';

/// 端末内で作る「今日の問題」（サーバーなし。`FIREBASE_BACKEND_ENABLED=false` の版）。
///
/// 問題は mahjong_core の [DailyProblemGenerator] が日付（JST）から決定的に作るので、
/// 同じ日ならどの端末でも同じ 3 問（基本・標準・応用）になる。問題 ID は
/// `daily-YYYY-MM-DD-N`（N = 1〜3）で、ID から同じ問題を作り直せる。
/// 公開問題（サーバーの 8 文字の ID）とは ID の形で見分ける（[isLocalDailyProblemId]）。

const String _idPrefix = 'daily-';
final RegExp _idPattern = RegExp(r'^daily-(\d{4}-\d{2}-\d{2})-([1-9])$');

/// 端末内の今日の問題の ID。
String localDailyProblemId(String date, int number) =>
    '$_idPrefix$date-$number';

/// [localDailyProblemId] の逆。形が違う・番号が範囲外なら null。
({String date, int number})? parseLocalDailyProblemId(String id) {
  final match = _idPattern.firstMatch(id);
  if (match == null) return null;
  final number = int.parse(match.group(2)!);
  if (number > kDailyProblemCount) return null;
  return (date: match.group(1)!, number: number);
}

/// 端末内の今日の問題か（通報・回答の送信・共有の QR などオンライン専用の機能を出さない）。
bool isLocalDailyProblemId(String? id) =>
    id != null && parseLocalDailyProblemId(id) != null;

/// 端末内の今日の問題の難易度。端末内の問題でなければ null。
DailyLevel? localDailyLevelOf(String id) {
  final parsed = parseLocalDailyProblemId(id);
  return parsed == null ? null : DailyLevel.ofNumber(parsed.number);
}

/// 生成した手を [Problem]（出題者なし・集計なし）にする。
Problem problemFromDailyHand(DailyHand hand) => Problem(
  id: localDailyProblemId(hand.date, hand.number),
  input: HandInput(
    tiles: hand.tiles,
    tsumoIndex: hand.tsumoIndex,
    doraIndicators: [hand.doraIndicator],
    seatWind: hand.seatWind,
    roundWind: hand.roundWind,
    dealer: hand.dealer,
    turn: hand.turn,
  ),
);

/// 日付の 3 問を作る（重いので既定では別 Isolate）。
typedef DailyHandsGenerator = Future<List<DailyHand>> Function(String date);

Future<List<DailyHand>> _generateInIsolate(String date) =>
    Isolate.run(() => DailyProblemGenerator().generate(date));

/// 端末内の [ProblemRepository]。今日の問題（[fetchDaily]・[fetchProblem]）だけを出す。
///
/// [available] は「オンライン機能（公開・回答の集計・通報・人気）」の意味のまま false。
/// 今日の問題は出せるので [supportsDaily] は true。
class LocalDailyProblemRepository implements ProblemRepository {
  LocalDailyProblemRepository({DailyHandsGenerator? generate})
    : _generate = generate ?? _generateInIsolate;

  final DailyHandsGenerator _generate;

  /// 作った日の 3 問（新しく使った順に [_cacheLimit] 日分）。Pro が日付を行き来しても
  /// 作り直さない。失敗したものは残さない。
  final Map<String, Future<List<DailyHand>>> _cache = {};
  static const _cacheLimit = 8;

  static const _error = BackendException(
    code: 'unavailable',
    reason: 'firebase_disabled',
  );

  @override
  bool get available => false;

  @override
  bool get supportsDaily => true;

  Future<List<DailyHand>> _hands(String date) {
    final cached = _cache.remove(date);
    if (cached != null) {
      _cache[date] = cached;
      return cached;
    }
    final future = _generate(date);
    _cache[date] = future;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_cache[date], future)) _cache.remove(date);
        },
      ),
    );
    return future;
  }

  @override
  Future<DailyProblems> fetchDaily(String date) async {
    final hands = await _hands(date);
    final problems = [for (final hand in hands) problemFromDailyHand(hand)];
    if (problems.isEmpty) return DailyProblems.empty(date);
    return DailyProblems(
      date: date,
      official: problems.first,
      picks: problems.skip(1).toList(),
    );
  }

  /// 端末内の問題の ID なら作り直して返す。公開問題の ID はサーバーが無いので
  /// 従来どおり `unavailable`（読み込めない）。
  @override
  Future<Problem?> fetchProblem(String id) async {
    final parsed = parseLocalDailyProblemId(id);
    if (parsed == null) throw _error;
    final hands = await _hands(parsed.date);
    for (final hand in hands) {
      if (hand.number == parsed.number) return problemFromDailyHand(hand);
    }
    return null;
  }

  @override
  Future<List<Problem>> fetchMyProblems(String uid, {int limit = 50}) async =>
      const [];

  @override
  Future<List<Problem>> fetchPopular({int limit = 20}) async => const [];

  @override
  Future<ProblemAnswerOutcome> answer({
    required String problemId,
    required String tile,
    int? selfRank,
  }) => Future.error(_error);

  @override
  Future<ProblemReportResult> report(
    String problemId,
    ProblemReportReason reason,
  ) => Future.error(_error);
}

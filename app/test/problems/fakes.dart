// 共有と成長（share/・problems/・core/account）のテスト用の偽物と見本の手。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:nanikiru_cam/share/share_service.dart';
import 'package:share_plus/share_plus.dart';

/// 画面のテストで MaterialApp に渡す（ja / en を `Localizations` で解決できるようにする）。
const testLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// API.md 1.2 の例の手。エンジンの答えは 3 軸で割れる: 速さ = 9p（テンパイ）、
/// 打点・バランス = 5m（一向聴で受け入れ 31 枚）。
HandInput sampleHand({int? turn = 6}) => HandInput(
  tiles: const [
    '1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', //
    '2z', '9p',
  ],
  tsumoIndex: 13,
  doraIndicators: const ['3z'],
  seatWind: Wind.south,
  roundWind: Wind.east,
  turn: turn,
);

/// 副露つき（ポン）の手。
HandInput meldHand() => HandInput(
  tiles: const [
    '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '9p', //
  ],
  tsumoIndex: 10,
  melds: [
    MeldInput(kind: MeldKind.pon, tiles: const ['5z', '5z', '5z']),
  ],
  doraIndicators: const ['3z', '1p'],
);

final _engine = DefaultNanikiruEngine();

AnalysisReport analyzeHand(HandInput input) =>
    _engine.analyze(input.toHandState(), deep: false);

/// メイン Isolate で同期的に解析する [AnalysisService]（テスト用）。
AnalysisService fakeAnalysisService() => AnalysisService(
  runner: (hand, deep) async => _engine.analyze(hand, deep: deep),
);

/// ドキュメントの形（API.md 3.2）で問題を作る。
Problem sampleProblem({
  String id = 'AbC12345',
  String nickname = 'まじゃおう',
  String authorUid = 'author-1',
  ProblemStats stats = const ProblemStats(
    total: 12,
    correct: 7,
    byTile: {'9p': 7, '5m': 5},
  ),
  bool hidden = false,
  DateTime? createdAt,
  HandInput? input,
}) => Problem(
  id: id,
  input: (input ?? sampleHand()).normalized(),
  authorUid: authorUid,
  authorNickname: nickname,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 21, 3, 4),
  stats: stats,
  hidden: hidden,
);

// --- アカウント ---------------------------------------------------------------

class FakeAccountService implements AccountService {
  FakeAccountService({this.uid, this.profile, this.token});

  String? uid;
  UserProfile? profile;
  String? token;
  int signInCalls = 0;
  int ensureCalls = 0;
  final StreamController<UserProfile?> controller =
      StreamController<UserProfile?>.broadcast();

  @override
  bool get available => true;

  @override
  Future<String?> signIn() async {
    signInCalls++;
    return uid;
  }

  @override
  Future<UserProfile?> ensureReady({String? locale}) async {
    ensureCalls++;
    return uid == null ? null : profile;
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) => controller.stream;

  @override
  Future<String?> idToken() async => token;
}

typedef BackendHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> data);

class FakeBackendClient implements BackendClient {
  FakeBackendClient({this.isAvailable = true});

  bool isAvailable;
  final Map<String, BackendHandler> handlers = {};
  final List<(String, Map<String, Object?>)> calls = [];

  @override
  bool get available => isAvailable;

  @override
  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    calls.add((name, data));
    final handler = handlers[name];
    if (handler == null) {
      throw BackendException(code: 'not-found', reason: 'no_handler:$name');
    }
    return handler(data);
  }
}

// --- 問題 ---------------------------------------------------------------------

class FakeProblemRepository implements ProblemRepository {
  FakeProblemRepository({this.isAvailable = true});

  bool isAvailable;
  final Map<String, Problem> problems = {};
  final Map<String, DailyProblems> daily = {};
  List<Problem> mine = [];
  List<Problem> popular = [];
  Object? error;
  ProblemAnswerOutcome? answerOutcome;
  final List<String> fetchedProblemIds = [];
  final List<String> fetchedDates = [];
  final List<(String, ProblemReportReason)> reports = [];
  final List<(String, String, int?)> answers = [];

  /// null なら [isAvailable] と同じ（[ProblemRepository.supportsDaily] の既定）。
  bool? dailySupported;

  @override
  bool get available => isAvailable;

  @override
  bool get supportsDaily => dailySupported ?? isAvailable;

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<Problem?> fetchProblem(String id) async {
    fetchedProblemIds.add(id);
    _maybeThrow();
    return problems[id];
  }

  @override
  Future<DailyProblems> fetchDaily(String date) async {
    fetchedDates.add(date);
    _maybeThrow();
    return daily[date] ?? DailyProblems.empty(date);
  }

  @override
  Future<List<Problem>> fetchMyProblems(String uid, {int limit = 50}) async {
    _maybeThrow();
    return mine;
  }

  @override
  Future<List<Problem>> fetchPopular({int limit = 20}) async {
    _maybeThrow();
    return popular;
  }

  @override
  Future<ProblemAnswerOutcome> answer({
    required String problemId,
    required String tile,
    int? selfRank,
  }) async {
    answers.add((problemId, tile, selfRank));
    _maybeThrow();
    return answerOutcome ??
        (throw const BackendException(code: 'not-found', reason: 'not_found'));
  }

  @override
  Future<ProblemReportResult> report(
    String problemId,
    ProblemReportReason reason,
  ) async {
    reports.add((problemId, reason));
    _maybeThrow();
    return const ProblemReportResult(reported: true);
  }
}

class FakeJsonHttpClient implements JsonHttpClient {
  FakeJsonHttpClient(this.respond);

  final JsonHttpResponse Function(Uri url, Map<String, Object?> body) respond;
  final List<(Uri, Map<String, Object?>, Map<String, String>)> requests = [];

  @override
  Future<JsonHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    requests.add((url, body, headers));
    return respond(url, body);
  }
}

// --- 公開 ---------------------------------------------------------------------

class FakeCardUploader implements CardUploader {
  final List<(String, Uint8List)> uploads = [];
  Object? error;

  @override
  Future<void> upload(String path, Uint8List png) async {
    final e = error;
    if (e != null) throw e;
    uploads.add((path, png));
  }
}

class MemoryQueueStore implements PublishQueueStore {
  List<PublishJob> jobs = [];

  @override
  Future<List<PublishJob>> load() async => List.of(jobs);

  @override
  Future<void> save(List<PublishJob> next) async => jobs = List.of(next);
}

class MemoryCardFiles implements CardFileStore {
  final Map<String, Uint8List> files = {};

  @override
  Future<String> write(String id, Uint8List png) async {
    final path = '/cards/$id.png';
    files[path] = png;
    return path;
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<void> delete(String path) async => files.remove(path);
}

/// `publishProblem` の正常な返事。
Map<String, Object?> publishResponse({
  String id = 'AbC12345',
  bool existing = false,
  String? cardUploadPath = 'cards/AbC12345/1x1.png',
}) => {
  'problemId': id,
  'existing': existing,
  'url': 'https://nanikiru-cam.web.app/p/$id',
  'cardUploadPath': cardUploadPath,
};

/// API.md 2.1 の返事の例。
Map<String, Object?> answerResponseJson({bool correct = true}) => {
  'ok': true,
  'alreadyAnswered': false,
  'yourTile': '9p',
  'correct': correct,
  'judgement': {'speed': true, 'points': false, 'balance': correct},
  'stats': {
    'total': 12,
    'correct': 7,
    'byTile': {'9p': 7, '5m': 5},
  },
  'answer': {
    'byAxis': {
      'speed': ['9p'],
      'points': ['9p', '5m'],
      'balance': ['9p'],
    },
    'ukeire': {'kinds': 8, 'total': 24},
    'shanten': 0,
    'engineVersion': '1.1.0',
  },
};

// --- 共有 ---------------------------------------------------------------------

final _pngHeader = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
]);

class FakeShareService extends ShareService {
  FakeShareService({this.completed = true, this.target = 'x'});

  bool completed;
  String target;
  Object? shareError;

  /// 書き出す瞬間に呼ぶ（そのときの画面の状態を調べるため）。
  void Function()? onCapture;
  final List<double> capturePixelRatios = [];
  final List<({String text, String subject, int files})> shared = [];
  int saved = 0;
  bool saveAllowed = true;

  @override
  Future<Uint8List> capture(GlobalKey key, {required double pixelRatio}) async {
    // 本物と同じく、次のフレーム（setState の反映）を待ってから書き出す。
    await WidgetsBinding.instance.endOfFrame;
    capturePixelRatios.add(pixelRatio);
    onCapture?.call();
    return _pngHeader;
  }

  @override
  Future<Uint8List> captureWithinLimit(
    GlobalKey key, {
    required double pixelRatio,
    int maxBytes = 900 * 1024,
    List<double> scales = const [1.0, 0.85, 0.7, 0.55],
  }) => capture(key, pixelRatio: pixelRatio);

  @override
  Future<XFile> writeTemp(
    Uint8List png, {
    String prefix = 'nanikiru_cam',
  }) async => XFile.fromData(png, mimeType: 'image/png', name: '$prefix.png');

  @override
  Future<ShareOutcome> shareFiles(
    List<XFile> files, {
    required String text,
    required String subject,
    Rect? origin,
  }) async {
    final e = shareError;
    if (e != null) throw e;
    shared.add((text: text, subject: subject, files: files.length));
    return ShareOutcome(completed: completed, target: target);
  }

  @override
  Future<bool> saveToPhotos(Uint8List png, {required String album}) async {
    if (saveAllowed) saved++;
    return saveAllowed;
  }
}

// --- 分析 ---------------------------------------------------------------------

class RecordingBackend implements AnalyticsBackend {
  final events = <String>[];
  final parameters = <Map<String, Object>>[];

  @override
  bool get supported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async {
    events.add(name);
    parameters.add(params);
  }

  @override
  Future<void> logScreen(String name) async {}
}

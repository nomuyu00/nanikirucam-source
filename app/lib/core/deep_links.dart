import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ディープリンク（Universal Links / Android App Links。設計書 7 章、API.md 5 章）。
///
/// - `https://<host>/p/{problemId}?ref={code}` → 問題を開く（[ProblemDeepLink]）
/// - `https://<host>/r/{code}` → 紹介コードを保留する（[ReferralDeepLink]）
///
/// `<host>` は [AppConfig.webBaseUrl] のホスト。紹介コードは [pendingReferralCodeProvider]
/// に保留する（設定画面・課金画面が読んで `applyReferral` に使い、使ったら [clear]）。

/// アプリ全体のナビゲータ。ディープリンクや通知から画面を開くときに使う
/// （`MaterialApp.navigatorKey`）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'appNavigator',
);

sealed class DeepLink {
  const DeepLink();
}

/// `/p/{problemId}`。[referralCode] は `?ref=`（あれば）。
class ProblemDeepLink extends DeepLink {
  const ProblemDeepLink(this.problemId, {this.referralCode});

  final String problemId;
  final String? referralCode;

  @override
  bool operator ==(Object other) =>
      other is ProblemDeepLink &&
      other.problemId == problemId &&
      other.referralCode == referralCode;

  @override
  int get hashCode => Object.hash(problemId, referralCode);

  @override
  String toString() => 'ProblemDeepLink($problemId, ref=$referralCode)';
}

/// `/r/{code}`。
class ReferralDeepLink extends DeepLink {
  const ReferralDeepLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) =>
      other is ReferralDeepLink && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'ReferralDeepLink($code)';
}

final _problemIdPattern = RegExp(r'^[A-Za-z0-9]{8}$');
// サーバーの紹介コード: 8 文字、I O 0 1 を除く英数字（API.md 3.1）。
final _referralCodePattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

/// 紹介コードを整える（大文字にし、空白・ハイフンを除く。API.md 1.4）。形式が違えば null。
String? normalizeReferralCode(String? raw) {
  if (raw == null) return null;
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  return _referralCodePattern.hasMatch(code) ? code : null;
}

/// 問題 ID の形式（8 文字の base62）。
bool isValidProblemId(String? id) =>
    id != null && _problemIdPattern.hasMatch(id);

/// [uri] をディープリンクとして読む。アプリのリンクでなければ null。
///
/// ホストが [host]（既定は [AppConfig.webBaseUrl] のホスト。`www.` 付きも受ける）と違う、
/// 経路が `/p/{id}` `/r/{code}` でない、ID・コードの形式が違うものは null。
DeepLink? parseDeepLink(Uri uri, {String? host}) {
  final expected = (host ?? Uri.parse(AppConfig.webBaseUrl).host).toLowerCase();
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final actual = uri.host.toLowerCase();
  if (actual != expected && actual != 'www.$expected') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 2) return null;
  switch (segments[0]) {
    case 'p':
      final id = segments[1];
      if (!isValidProblemId(id)) return null;
      return ProblemDeepLink(
        id,
        referralCode: normalizeReferralCode(uri.queryParameters['ref']),
      );
    case 'r':
      final code = normalizeReferralCode(segments[1]);
      return code == null ? null : ReferralDeepLink(code);
  }
  return null;
}

/// Google Play の Install Referrer 文字列
/// （`utm_source=share&utm_campaign=problem&pid=...&ref=...`、API.md 5 章）から
/// 問題 ID と紹介コードを読む。どちらも無ければ null。
({String? problemId, String? referralCode})? parseInstallReferrer(
  String referrer,
) {
  Map<String, String> params;
  try {
    params = Uri.splitQueryString(referrer);
  } catch (_) {
    return null;
  }
  final pid = params['pid'];
  final problemId = isValidProblemId(pid) ? pid : null;
  final referralCode = normalizeReferralCode(params['ref']);
  if (problemId == null && referralCode == null) return null;
  return (problemId: problemId, referralCode: referralCode);
}

// --- 受け口 ----------------------------------------------------------------

/// リンクの流れ。テストでは偽物に差し替える。
abstract class DeepLinkSource {
  /// 起動時のリンク（あれば）と、その後に届くリンク。
  Stream<Uri> get links;
}

class AppLinksSource implements DeepLinkSource {
  const AppLinksSource();

  // app_links 6 系は uriLinkStream が起動時のリンクも流す。
  @override
  Stream<Uri> get links => AppLinks().uriLinkStream;
}

/// Google Play の Install Referrer を読む窓口。
///
/// Install Referrer を読むプラグイン（例: `play_install_referrer`）を `pubspec.yaml` に入れたら
/// この抽象を実装して [installReferrerSourceProvider] を差し替える。入れるまでは何も読まない
/// （iOS は遅延ディープリンクを持たない。設計書 7 章）。
abstract class InstallReferrerSource {
  /// 初回起動で 1 回だけ読む。Android 以外・取得できないときは null。
  Future<String?> readReferrer();
}

class NoInstallReferrerSource implements InstallReferrerSource {
  const NoInstallReferrerSource();

  @override
  Future<String?> readReferrer() async => null;
}

/// 何も流さないリンクの流れ（テスト・プラグインのない環境）。
class EmptyDeepLinkSource implements DeepLinkSource {
  const EmptyDeepLinkSource();

  @override
  Stream<Uri> get links => const Stream<Uri>.empty();
}

final deepLinkSourceProvider = Provider<DeepLinkSource>((ref) {
  // flutter test にはプラグインがなく、EventChannel の購読失敗が FlutterError としてテストを
  // 落とすため、何も流さない（リンクを試すテストは provider を差し替える）。
  if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
    return const EmptyDeepLinkSource();
  }
  return const AppLinksSource();
});

final installReferrerSourceProvider = Provider<InstallReferrerSource>(
  (ref) => const NoInstallReferrerSource(),
);

/// リンクを読んで、問題を開く・紹介コードを保留する処理に振り分ける。
class DeepLinkRouter {
  DeepLinkRouter({
    required this.source,
    required this.onProblem,
    required this.onReferral,
    this.host,
  });

  final DeepLinkSource source;

  /// `/p/{id}` のとき。[ProblemDeepLink.referralCode] は先に [onReferral] へ渡してある。
  final Future<void> Function(ProblemDeepLink link) onProblem;

  /// 紹介コードを保留する（形式検査済み）。
  final void Function(String code) onReferral;

  final String? host;
  StreamSubscription<Uri>? _subscription;

  /// 購読を始める。2 回呼んでも 1 回だけ。
  void start() {
    _subscription ??= source.links.listen(
      (uri) => unawaited(handleUri(uri)),
      onError: (Object _) {},
    );
  }

  Future<void> handleUri(Uri uri) async {
    final link = parseDeepLink(uri, host: host);
    if (link != null) await handle(link);
  }

  Future<void> handle(DeepLink link) async {
    switch (link) {
      case ProblemDeepLink():
        final code = link.referralCode;
        if (code != null) onReferral(code);
        await onProblem(link);
      case ReferralDeepLink():
        onReferral(link.code);
    }
  }

  /// Install Referrer の文字列を同じ流れで処理する。
  Future<void> handleInstallReferrer(String referrer) async {
    final parsed = parseInstallReferrer(referrer);
    if (parsed == null) return;
    final pid = parsed.problemId;
    if (pid != null) {
      await handle(ProblemDeepLink(pid, referralCode: parsed.referralCode));
    } else if (parsed.referralCode != null) {
      onReferral(parsed.referralCode!);
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}

// --- 保留中の紹介コード --------------------------------------------------------

/// `/r/{code}` や `/p/{id}?ref=`、Install Referrer から届いた紹介コードの置き場
/// （整形済みの 8 文字。無ければ null）。
///
/// 端末に保存されるので、アプリを閉じても残る。設定画面・課金画面は
/// `ref.watch(pendingReferralCodeProvider)` で読み、`applyReferral` を呼んだら
/// `ref.read(pendingReferralCodeProvider.notifier).clear()` で消す。
final pendingReferralCodeProvider =
    NotifierProvider<PendingReferralCode, String?>(PendingReferralCode.new);

class PendingReferralCode extends Notifier<String?> {
  static const preferenceKey = 'pending_referral_code_v1';
  bool _disposed = false;

  @override
  String? build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = normalizeReferralCode(prefs.getString(preferenceKey));
      // 読み込み前に新しいコードが届いていればそちらを優先する。
      if (saved != null && state == null && !_disposed) state = saved;
    } catch (_) {}
  }

  /// [code] を保留する（形式が違えば何もしない）。後から届いたコードで置き換える。
  void set(String code) {
    final normalized = normalizeReferralCode(code);
    if (normalized == null) return;
    state = normalized;
    unawaited(_save(normalized));
  }

  /// 使い終わった（または不要になった）ら消す。
  void clear() {
    state = null;
    unawaited(_save(null));
  }

  Future<void> _save(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(preferenceKey);
      } else {
        await prefs.setString(preferenceKey, value);
      }
    } catch (_) {}
  }
}

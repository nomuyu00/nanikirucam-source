import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements DeepLinkSource {
  final controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get links => controller.stream;
}

void main() {
  const host = 'nanikiru-cam.web.app';

  group('parseDeepLink', () {
    test('/p/{id} は問題。?ref= は整えて持つ', () {
      expect(
        parseDeepLink(Uri.parse('https://$host/p/AbC12345')),
        const ProblemDeepLink('AbC12345'),
      );
      expect(
        parseDeepLink(Uri.parse('https://$host/p/AbC12345?ref=abcd-2345')),
        const ProblemDeepLink('AbC12345', referralCode: 'ABCD2345'),
      );
      // 形式が違う紹介コードは捨てる（問題は開く）。
      expect(
        parseDeepLink(Uri.parse('https://$host/p/AbC12345?ref=oooo1111')),
        const ProblemDeepLink('AbC12345'),
      );
    });

    test('/r/{code} は紹介コード（大文字小文字・ハイフン・空白は問わない）', () {
      expect(
        parseDeepLink(Uri.parse('https://$host/r/ABCD2345')),
        const ReferralDeepLink('ABCD2345'),
      );
      expect(
        parseDeepLink(Uri.parse('https://$host/r/abcd-2345')),
        const ReferralDeepLink('ABCD2345'),
      );
      expect(
        parseDeepLink(Uri.parse('https://$host/r/abcd%202345')),
        const ReferralDeepLink('ABCD2345'),
      );
    });

    test('末尾のスラッシュや www. は許し、別のホスト・経路・形式は読まない', () {
      expect(
        parseDeepLink(Uri.parse('https://$host/p/AbC12345/')),
        const ProblemDeepLink('AbC12345'),
      );
      expect(
        parseDeepLink(Uri.parse('https://www.$host/p/AbC12345')),
        const ProblemDeepLink('AbC12345'),
      );
      for (final url in const [
        'https://example.com/p/AbC12345',
        'https://$host/p/AbC1234', // 7 文字
        'https://$host/p/AbC123456', // 9 文字
        'https://$host/p/AbC1234!',
        'https://$host/r/ABCD234', // 7 文字
        'https://$host/r/ABCD2341', // 1 は使わない文字
        'https://$host/x/AbC12345',
        'https://$host/p',
        'https://$host/p/AbC12345/extra',
        'https://$host/',
        'ftp://$host/p/AbC12345',
        'nanikiru://p/AbC12345',
      ]) {
        expect(parseDeepLink(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('host を指定できる（独自ドメインに替えたとき）', () {
      expect(
        parseDeepLink(
          Uri.parse('https://nanikiru.example/p/AbC12345'),
          host: 'nanikiru.example',
        ),
        const ProblemDeepLink('AbC12345'),
      );
      expect(
        parseDeepLink(
          Uri.parse('https://$host/p/AbC12345'),
          host: 'nanikiru.example',
        ),
        isNull,
      );
    });
  });

  group('parseInstallReferrer', () {
    test('Google Play の referrer から pid と ref を読む', () {
      final parsed = parseInstallReferrer(
        'utm_source=share&utm_campaign=problem&pid=AbC12345&ref=ABCD2345',
      );
      expect(parsed?.problemId, 'AbC12345');
      expect(parsed?.referralCode, 'ABCD2345');
    });

    test('pid か ref のどちらかだけでもよい。どちらも無い・形式違いは null', () {
      expect(parseInstallReferrer('pid=AbC12345')?.referralCode, isNull);
      expect(parseInstallReferrer('ref=abcd2345')?.problemId, isNull);
      expect(
        parseInstallReferrer('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
      expect(parseInstallReferrer('pid=short&ref=bad'), isNull);
      expect(parseInstallReferrer(''), isNull);
    });
  });

  group('DeepLinkRouter', () {
    late _Source source;
    late List<ProblemDeepLink> problems;
    late List<String> referrals;
    late DeepLinkRouter router;

    setUp(() {
      source = _Source();
      problems = [];
      referrals = [];
      router = DeepLinkRouter(
        source: source,
        host: host,
        onProblem: (link) async => problems.add(link),
        onReferral: referrals.add,
      )..start();
    });

    tearDown(() async {
      router.dispose();
      await source.controller.close();
    });

    test('/p/ は問題を開き、?ref= は先に保留する', () async {
      source.controller.add(Uri.parse('https://$host/p/AbC12345?ref=ABCD2345'));
      await Future<void>.delayed(Duration.zero);
      expect(problems, [
        const ProblemDeepLink('AbC12345', referralCode: 'ABCD2345'),
      ]);
      expect(referrals, ['ABCD2345']);
    });

    test('/r/ は紹介コードを保留するだけで、問題は開かない', () async {
      source.controller.add(Uri.parse('https://$host/r/ABCD2345'));
      await Future<void>.delayed(Duration.zero);
      expect(referrals, ['ABCD2345']);
      expect(problems, isEmpty);
    });

    test('アプリのリンクでないものは無視する', () async {
      source.controller.add(Uri.parse('https://example.com/p/AbC12345'));
      await Future<void>.delayed(Duration.zero);
      expect(problems, isEmpty);
      expect(referrals, isEmpty);
    });

    test('start を 2 回呼んでも 1 回しか受けない', () async {
      router.start();
      source.controller.add(Uri.parse('https://$host/p/AbC12345'));
      await Future<void>.delayed(Duration.zero);
      expect(problems, hasLength(1));
    });

    test('Install Referrer の pid / ref も同じ流れで処理する', () async {
      await router.handleInstallReferrer(
        'utm_source=share&pid=AbC12345&ref=ABCD2345',
      );
      expect(problems, [
        const ProblemDeepLink('AbC12345', referralCode: 'ABCD2345'),
      ]);
      expect(referrals, ['ABCD2345']);

      problems.clear();
      referrals.clear();
      await router.handleInstallReferrer('ref=WXYZ2345');
      expect(problems, isEmpty);
      expect(referrals, ['WXYZ2345']);

      await router.handleInstallReferrer('utm_source=other');
      expect(referrals, ['WXYZ2345']);
    });
  });

  group('pendingReferralCodeProvider', () {
    test('保留した紹介コードを端末に残し、clear で消す', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingReferralCodeProvider.notifier);
      expect(container.read(pendingReferralCodeProvider), isNull);

      notifier.set('abcd-2345');
      expect(container.read(pendingReferralCodeProvider), 'ABCD2345');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PendingReferralCode.preferenceKey), 'ABCD2345');

      notifier.set('not a code');
      expect(container.read(pendingReferralCodeProvider), 'ABCD2345');

      notifier.clear();
      expect(container.read(pendingReferralCodeProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(PendingReferralCode.preferenceKey), isNull);
    });

    test('保存済みのコードは次に起動したとき読み込む', () async {
      SharedPreferences.setMockInitialValues({
        PendingReferralCode.preferenceKey: 'WXYZ2345',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pendingReferralCodeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(pendingReferralCodeProvider), 'WXYZ2345');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  const key = BlockedAuthorsNotifier.preferenceKey;

  Future<ProviderContainer> open([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(blockedAuthorsProvider);
    await container.read(blockedAuthorsProvider.notifier).ensureLoaded();
    return container;
  }

  BlockedAuthorsNotifier notifier(ProviderContainer c) =>
      c.read(blockedAuthorsProvider.notifier);

  test('保存のキーは blocked_authors_v1', () {
    expect(key, 'blocked_authors_v1');
  });

  test('読み込む前は未読み込み（一覧を出さない）。読み終えたら loaded', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(blockedAuthorsProvider).loaded, isFalse);
    await container.read(blockedAuthorsProvider.notifier).ensureLoaded();
    expect(container.read(blockedAuthorsProvider).loaded, isTrue);
    expect(container.read(blockedAuthorsProvider).authors, isEmpty);
  });

  test('ブロックすると端末に保存され、新しい順に並ぶ。解除すると消える', () async {
    final container = await open();
    expect(
      await notifier(container).block('bad-1', nickname: ' 迷惑さん '),
      isTrue,
    );
    expect(await notifier(container).block('bad-2'), isTrue);

    final state = container.read(blockedAuthorsProvider);
    expect(state.authors.map((a) => a.uid), ['bad-2', 'bad-1']);
    expect(state.authors.last.nickname, '迷惑さん', reason: '前後の空白を除く');
    expect(state.isBlocked('bad-1'), isTrue);
    expect(state.isBlocked('good'), isFalse);
    expect(state.isBlocked(null), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), allOf(contains('bad-1'), contains('bad-2')));

    await notifier(container).unblock('bad-1');
    expect(container.read(blockedAuthorsProvider).isBlocked('bad-1'), isFalse);
    expect(prefs.getString(key), isNot(contains('bad-1')));

    await notifier(container).unblock('bad-2');
    expect(container.read(blockedAuthorsProvider).authors, isEmpty);
    expect(prefs.getString(key), isNull, reason: '空になったらキーごと消す');
  });

  test('同じ出題者を 2 回ブロックしても 1 件。ブロックできない uid は false', () async {
    final container = await open();
    await notifier(container).block('bad-1', nickname: 'A');
    expect(await notifier(container).block('bad-1', nickname: 'B'), isTrue);
    expect(container.read(blockedAuthorsProvider).authors, hasLength(1));
    expect(container.read(blockedAuthorsProvider).authors.single.nickname, 'A');

    expect(await notifier(container).block(''), isFalse);
    expect(await notifier(container).block('deleted'), isFalse);
    expect(isBlockableAuthor('deleted'), isFalse);
    expect(isBlockableAuthor(null), isFalse);
    expect(container.read(blockedAuthorsProvider).authors, hasLength(1));
  });

  test('次に起動したとき保存内容を読み込む。壊れた 1 件は捨てる', () async {
    final container = await open({
      key:
          '[{"uid":"bad-1","nickname":"迷惑さん","blockedAt":"2026-10-20T03:00:00.000Z"},'
          '{"nickname":"uid なし"},"not a map",'
          '{"uid":"bad-2","blockedAt":"x"}]',
    });
    final state = container.read(blockedAuthorsProvider);
    expect(state.loaded, isTrue);
    expect(state.authors.map((a) => a.uid), ['bad-1', 'bad-2']);
    expect(state.authors.first.nickname, '迷惑さん');
    expect(state.authors.first.blockedAt, DateTime.utc(2026, 10, 20, 3));
  });

  test('保存内容が壊れていても空として動く', () async {
    final container = await open({key: '{not json'});
    expect(container.read(blockedAuthorsProvider).loaded, isTrue);
    expect(container.read(blockedAuthorsProvider).authors, isEmpty);
  });

  test('読み込み前に block しても、保存済みの分を失わない', () async {
    SharedPreferences.setMockInitialValues({
      key:
          '[{"uid":"old","nickname":"","blockedAt":"2026-10-20T03:00:00.000Z"}]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(blockedAuthorsProvider.notifier).block('new');
    expect(container.read(blockedAuthorsProvider).authors.map((a) => a.uid), [
      'new',
      'old',
    ]);
  });

  test('invalidate（データ削除のあと）で最初から読み直す', () async {
    final container = await open({
      key:
          '[{"uid":"bad-1","nickname":"","blockedAt":"2026-10-20T03:00:00.000Z"}]',
    });
    expect(container.read(blockedAuthorsProvider).authors, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    container.invalidate(blockedAuthorsProvider);
    await container.read(blockedAuthorsProvider.notifier).ensureLoaded();
    expect(container.read(blockedAuthorsProvider).loaded, isTrue);
    expect(container.read(blockedAuthorsProvider).authors, isEmpty);
  });

  test('withoutBlockedAuthors はブロック中の出題者の問題を除く', () async {
    final container = await open();
    await notifier(container).block('bad-1');
    final problems = [
      sampleProblem(id: 'AAAAAAAA', authorUid: 'good'),
      sampleProblem(id: 'BBBBBBBB', authorUid: 'bad-1'),
      sampleProblem(id: 'CCCCCCCC', authorUid: 'good-2'),
    ];
    expect(
      withoutBlockedAuthors(
        problems,
        container.read(blockedAuthorsProvider),
      ).map((p) => p.id),
      ['AAAAAAAA', 'CCCCCCCC'],
    );
    expect(
      withoutBlockedAuthors(problems, const BlockedAuthorsState(loaded: true)),
      hasLength(3),
    );
  });
}

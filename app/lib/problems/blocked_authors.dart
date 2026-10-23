import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ブロック中の出題者（App Store 審査ガイドライン 1.2: ユーザー生成コンテンツ）。
///
/// 迷惑な出題者の問題を、この端末で表示しないようにする。サーバーへは送らない
/// （端末内の非表示で足りる）。今日の問題・人気問題の一覧・ディープリンクで開く問題から
/// 除く。自分の問題の一覧（出題した問題）は対象外。

/// ブロックした出題者 1 人。
class BlockedAuthor extends Equatable {
  const BlockedAuthor({
    required this.uid,
    this.nickname = '',
    required this.blockedAt,
  });

  factory BlockedAuthor.fromJson(Map<String, Object?> json) {
    final uid = json['uid'];
    if (uid is! String || uid.isEmpty) {
      throw const FormatException('BlockedAuthor: uid がない');
    }
    final nickname = json['nickname'];
    return BlockedAuthor(
      uid: uid,
      nickname: nickname is String ? nickname : '',
      blockedAt:
          DateTime.tryParse(json['blockedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 出題者の uid（`problems/{id}.authorUid`）。
  final String uid;

  /// ブロックしたときの出題者名（設定の一覧に出す。空なら匿名）。
  final String nickname;
  final DateTime blockedAt;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'nickname': nickname,
    'blockedAt': blockedAt.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [uid, nickname, blockedAt];
}

class BlockedAuthorsState extends Equatable {
  const BlockedAuthorsState({this.loaded = false, this.authors = const []});

  /// 端末の保存内容を読み終えたか。読み終えるまでは一覧を出さない（ブロック中の問題が一瞬
  /// 見えるのを防ぐ）。
  final bool loaded;

  /// 新しくブロックした順（先頭が最新）。
  final List<BlockedAuthor> authors;

  bool isBlocked(String? uid) =>
      uid != null && authors.any((author) => author.uid == uid);

  @override
  List<Object?> get props => [loaded, authors];
}

/// ブロックできない uid（空、削除済みユーザーの印）。
bool isBlockableAuthor(String? uid) =>
    uid != null && uid.isNotEmpty && uid != 'deleted';

/// [problems] からブロック中の出題者の問題を除く。
List<Problem> withoutBlockedAuthors(
  Iterable<Problem> problems,
  BlockedAuthorsState blocked,
) => [
  for (final problem in problems)
    if (!blocked.isBlocked(problem.authorUid)) problem,
];

class BlockedAuthorsNotifier extends Notifier<BlockedAuthorsState> {
  /// 端末に保存するキー（JSON の配列）。データ削除（設定）で全キーと一緒に消える。
  static const preferenceKey = 'blocked_authors_v1';

  Future<void>? _loading;
  bool _disposed = false;

  @override
  BlockedAuthorsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loading = _load();
    return const BlockedAuthorsState();
  }

  Future<void> _load() async {
    var authors = <BlockedAuthor>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(preferenceKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            try {
              authors.add(
                BlockedAuthor.fromJson(Map<String, Object?>.from(item)),
              );
            } on FormatException {
              // 壊れた 1 件は捨てる。
            }
          }
        }
      }
    } catch (_) {
      authors = <BlockedAuthor>[];
    }
    if (!_disposed) state = BlockedAuthorsState(loaded: true, authors: authors);
  }

  /// 端末の保存内容を読み終えるまで待つ。
  Future<void> ensureLoaded() => _loading ?? Future.value();

  /// [uid] をブロックする。ブロックできない uid（空・削除済み）は false。
  /// すでにブロック中なら何もせず true。
  Future<bool> block(String uid, {String nickname = ''}) async {
    if (!isBlockableAuthor(uid)) return false;
    await ensureLoaded();
    if (_disposed) return false;
    if (!state.isBlocked(uid)) {
      state = BlockedAuthorsState(
        loaded: true,
        authors: [
          BlockedAuthor(
            uid: uid,
            nickname: nickname.trim(),
            blockedAt: DateTime.now(),
          ),
          ...state.authors,
        ],
      );
      await _save();
    }
    return true;
  }

  /// [uid] のブロックを解除する。
  Future<void> unblock(String uid) async {
    await ensureLoaded();
    if (_disposed || !state.isBlocked(uid)) return;
    state = BlockedAuthorsState(
      loaded: true,
      authors: [
        for (final author in state.authors)
          if (author.uid != uid) author,
      ],
    );
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.authors.isEmpty) {
        await prefs.remove(preferenceKey);
      } else {
        await prefs.setString(
          preferenceKey,
          jsonEncode([for (final a in state.authors) a.toJson()]),
        );
      }
    } catch (_) {
      // 保存できなくても、このセッションでは非表示を続ける。
    }
  }
}

final blockedAuthorsProvider =
    NotifierProvider<BlockedAuthorsNotifier, BlockedAuthorsState>(
      BlockedAuthorsNotifier.new,
    );

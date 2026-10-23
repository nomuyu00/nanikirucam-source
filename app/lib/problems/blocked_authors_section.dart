import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';

/// 設定画面の「ブロック中の出題者」: 一覧と解除（App Store 審査ガイドライン 1.2）。
/// 見出しも含む。ブロックしていなければ、ブロックのしかたを案内する。
class BlockedAuthorsSection extends ConsumerWidget {
  const BlockedAuthorsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.problemsStrings;
    final theme = Theme.of(context);
    final blocked = ref.watch(blockedAuthorsProvider);
    final rows = <Widget>[
      if (blocked.loaded && blocked.authors.isEmpty)
        ListTile(
          key: const ValueKey('settings-blocked-empty'),
          leading: const Icon(Icons.block),
          title: Text(strings.blockedEmpty, style: theme.textTheme.bodyMedium),
        ),
      for (final author in blocked.authors)
        ListTile(
          key: ValueKey('settings-blocked-${author.uid}'),
          leading: const Icon(Icons.block),
          title: Text(strings.authorName(author.nickname)),
          subtitle: Text(strings.blockedOn(author.blockedAt.toLocal())),
          trailing: TextButton(
            key: ValueKey('settings-unblock-${author.uid}'),
            onPressed: () {
              unawaited(
                ref.read(blockedAuthorsProvider.notifier).unblock(author.uid),
              );
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(strings.unblocked)));
            },
            child: Text(strings.unblock),
          ),
        ),
    ];
    return Column(
      key: const ValueKey('settings-blocked-authors'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isEmpty)
          SectionHeader(strings.blockedSection)
        else
          GroupedSection(title: strings.blockedSection, children: rows),
      ],
    );
  }
}

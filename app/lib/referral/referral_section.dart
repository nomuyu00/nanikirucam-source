import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';

/// 設定画面の「招待コード」: 自分のコードの表示・コピー・共有と、友だちのコードの入力
/// （仕様 8 章、設計書 14 章）。コードを使うと両者に Pro 7 日（`applyReferral`）。
class ReferralSection extends ConsumerStatefulWidget {
  const ReferralSection({super.key});

  @override
  ConsumerState<ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends ConsumerState<ReferralSection> {
  final TextEditingController _controller = TextEditingController();
  bool _applying = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    // リンクから届いたコードが残っていれば、入力欄に入れておく（使うかはユーザーが決める）。
    _prefill(ref.read(pendingReferralCodeProvider));
    ref.listenManual(
      pendingReferralCodeProvider,
      (_, next) => _prefill(next),
    );
  }

  void _prefill(String? code) {
    if (code != null && _controller.text.isEmpty) _controller.text = code;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final strings = context.settingsStrings;
    setState(() {
      _applying = true;
      _message = null;
    });
    final result = await ref
        .read(referralProvider.notifier)
        .apply(_controller.text);
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (result.ok) {
        _controller.clear();
        _message = strings.appliedUntil(formatPaywallDate(result.grant!.proUntil));
        _messageIsError = false;
      } else {
        _message = strings.referralFailure(result.failure!);
        _messageIsError = true;
      }
    });
  }

  Future<void> _copy(String code) async {
    final strings = context.settingsStrings;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.copied)));
  }

  Future<void> _share(String code) async {
    final strings = context.settingsStrings;
    final text = strings.shareText(code, AppConfig.referralUrl(code));
    try {
      await ref.read(referralShareProvider)(text);
    } catch (_) {
      // 共有シートを開けなかった。何もしない。
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.settingsStrings;
    final theme = Theme.of(context);
    final myCode = ref.watch(myReferralCodeProvider);
    final applied = ref.watch(referralProvider.select((s) => s.appliedCode));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.referralLead, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(strings.myCode, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (myCode == null)
            Text(
              strings.codeUnavailable,
              key: const ValueKey('referral-code-unavailable'),
              style: theme.textTheme.bodySmall,
            )
          else
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    myCode,
                    key: const ValueKey('referral-code'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('referral-copy'),
                  tooltip: strings.copy,
                  onPressed: () => unawaited(_copy(myCode)),
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  key: const ValueKey('referral-share'),
                  tooltip: strings.share,
                  onPressed: () => unawaited(_share(myCode)),
                  icon: const Icon(Icons.ios_share),
                ),
              ],
            ),
          const SizedBox(height: 16),
          if (applied != null)
            Text(
              strings.alreadyAppliedLocal,
              key: const ValueKey('referral-already-applied'),
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('referral-input'),
                    controller: _controller,
                    enabled: !_applying,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: strings.enterCode,
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_apply()),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(
                    key: const ValueKey('referral-apply'),
                    onPressed: _applying ? null : () => unawaited(_apply()),
                    child: Text(_applying ? strings.applying : strings.applyCode),
                  ),
                ),
              ],
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                key: const ValueKey('referral-message'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

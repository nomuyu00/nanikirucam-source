import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

class ReviewAccessPage extends ConsumerStatefulWidget {
  const ReviewAccessPage({super.key});

  @override
  ConsumerState<ReviewAccessPage> createState() => _ReviewAccessPageState();
}

class _ReviewAccessPageState extends ConsumerState<ReviewAccessPage> {
  final _code = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final strings = context.settingsStrings;
    final input = _code.text;
    _code.clear();
    final result = await ref.read(reviewAccessProvider).activate(input);
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        ReviewAccessResult.activated => strings.reviewActivated,
        ReviewAccessResult.invalid => strings.reviewInvalid,
        ReviewAccessResult.unavailable => strings.reviewUnavailable,
        ReviewAccessResult.failed => strings.reviewFailed,
        ReviewAccessResult.busy => null,
      };
    });
  }

  Future<void> _disable() async {
    final strings = context.settingsStrings;
    final ok = await ref.read(reviewAccessProvider).disable();
    if (mounted) setState(() => _message = ok ? null : strings.reviewFailed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.settingsStrings;
    final review = ref.watch(reviewAccessProvider);
    final waiting = review.loading || review.busy;
    return Scaffold(
      appBar: AppBar(title: Text(strings.reviewAccess)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            Text(strings.reviewAccessBody),
            const SizedBox(height: AppSpacing.lg),
            if (waiting) const LinearProgressIndicator(),
            if (!review.available)
              Text(strings.reviewUnavailable)
            else ...[
              Text(
                strings.planUntil(
                  review.config.expiresAt!.toLocal().toString(),
                ),
                key: const ValueKey('review-expiry'),
              ),
              if (review.active) ...[
                Text(strings.planProReview),
                FilledButton(
                  key: const ValueKey('review-deactivate'),
                  onPressed: waiting ? null : _disable,
                  child: Text(strings.reviewDeactivate),
                ),
              ] else ...[
                TextField(
                  key: const ValueKey('review-code'),
                  controller: _code,
                  enabled: !waiting,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 256,
                  decoration: InputDecoration(labelText: strings.reviewCode),
                  onSubmitted: waiting ? null : (_) => _activate(),
                ),
                FilledButton(
                  key: const ValueKey('review-activate'),
                  onPressed: waiting ? null : _activate,
                  child: Text(strings.reviewActivate),
                ),
              ],
            ],
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ),
      ),
    );
  }
}

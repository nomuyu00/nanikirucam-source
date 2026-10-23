import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:url_launcher/url_launcher.dart';

/// 14 枚が和了形のときの大きな表示（仕様 6.3）。「次の局へ」で消える。
class LiveWinOverlay extends StatelessWidget {
  const LiveWinOverlay({super.key, required this.win, required this.onNext});

  final LiveWinRecord win;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    final rank = strings.rankName(win.rank);
    return Center(
      child: Container(
        key: const ValueKey('live-win'),
        margin: const EdgeInsets.all(AppSpacing.xl),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.livePanel,
          borderRadius: AppRadius.xlAll,
          border: Border.all(
            color: AppColors.liveAccent.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.tsumoWin,
              style: theme.textTheme.displayMedium?.copyWith(
                color: AppColors.liveAccent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              win.yaku.map(strings.yakuName).join('・'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.liveText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                strings.hanFu(win.han, win.fu),
                if (rank.isNotEmpty) rank,
                strings.points(win.points),
              ].join('  '),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.liveText,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(strings.nextHand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 置き方の案内の中身（図と手順、マナーの注意）。
class LiveGuideBody extends StatelessWidget {
  const LiveGuideBody({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StandDiagram(),
        const SizedBox(height: AppSpacing.md),
        for (final (i, step) in strings.guideSteps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.caution.withValues(alpha: 0.09),
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.handshake_outlined,
                size: 20,
                color: AppColors.caution,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  strings.guideConsent,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 置き方の図（スタンドのスマホが斜め上から手牌を写す）。
class _StandDiagram extends StatelessWidget {
  const _StandDiagram();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 104,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
      ),
      child: CustomPaint(painter: _StandPainter(scheme.primary)),
    );
  }
}

class _StandPainter extends CustomPainter {
  _StandPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color.withValues(alpha: 0.18);
    final table = size.height - 12;
    canvas.drawLine(Offset(0, table), Offset(size.width, table), stroke);
    // 手牌。
    for (var i = 0; i < 7; i++) {
      final r = Rect.fromLTWH(size.width * 0.45 + i * 14, table - 18, 12, 18);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
    }
    // スタンドとスマホ（斜め）。
    final base = Offset(size.width * 0.18, table);
    canvas.drawLine(base, base.translate(10, -40), stroke);
    final phone = Path()
      ..moveTo(base.dx + 2, base.dy - 46)
      ..lineTo(base.dx + 30, base.dy - 88)
      ..lineTo(base.dx + 44, base.dy - 78)
      ..lineTo(base.dx + 16, base.dy - 36)
      ..close();
    canvas.drawPath(phone, fill);
    canvas.drawPath(phone, stroke);
    // 視線（30〜45°）。
    final eye = Offset(base.dx + 30, base.dy - 62);
    final dashed = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (final target in [
      Offset(size.width * 0.45, table - 18),
      Offset(size.width * 0.45 + 98, table - 18),
    ]) {
      final d = target - eye;
      for (var t = 0.0; t < 1; t += 0.08) {
        canvas.drawLine(eye + d * t, eye + d * (t + 0.04), dashed);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StandPainter old) => old.color != color;
}

/// 初回の置き方の案内（了解するまでカメラを開かない）。
class LiveGuideOverlay extends StatelessWidget {
  const LiveGuideOverlay({super.key, required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    return ColoredBox(
      color: AppColors.liveScrimStrong,
      child: SafeArea(
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(AppSpacing.lg),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.guideTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  const LiveGuideBody(),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const ValueKey('live-guide-accept'),
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(strings.guideStart),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// カメラ・モデルの失敗（再試行・閉じる。iOS のカメラ拒否は設定を開く）。
class LiveErrorView extends StatelessWidget {
  const LiveErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onClose,
    this.permission = false,
  });

  final String message;
  final bool permission;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final theme = Theme.of(context);
    return ColoredBox(
      color: AppColors.camera,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.liveGlass,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.no_photography_outlined,
                    size: 34,
                    color: AppColors.liveText,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  message,
                  key: const ValueKey('live-error'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.liveText,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (permission &&
                        defaultTargetPlatform == TargetPlatform.iOS)
                      FilledButton.icon(
                        onPressed: () => launchUrl(Uri.parse('app-settings:')),
                        icon: const Icon(Icons.settings),
                        label: Text(common.openSettings),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(common.retry),
                    ),
                    OutlinedButton(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.liveText,
                        side: const BorderSide(color: AppColors.liveHairline),
                      ),
                      child: Text(common.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

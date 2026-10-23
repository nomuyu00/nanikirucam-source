import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_theme.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/notice_card.dart';
import 'package:nanikiru_cam/ui/widgets/primary_button.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/ui/widgets/tile_fan.dart';

/// テーマと共通部品（ui/theme・ui/widgets）。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  group('AppTheme', () {
    test('ブランド色を ColorScheme に割り当てる（ライト固定）', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AppColors.jade);
      expect(theme.colorScheme.tertiary, AppColors.vermilion);
      expect(theme.colorScheme.surface, AppColors.ivory);
      expect(theme.scaffoldBackgroundColor, AppColors.ivory);
      expect(theme.colorScheme.error, AppColors.danger);
    });

    test('文字の階層: 見出しは太く、本文は行間を広めに', () {
      final text = AppTheme.light().textTheme;
      expect(text.headlineMedium!.fontWeight, FontWeight.w800);
      expect(text.titleMedium!.fontWeight, FontWeight.w700);
      expect(text.bodyMedium!.height, greaterThanOrEqualTo(1.5));
      expect(text.bodyLarge!.fontSize! > text.bodyMedium!.fontSize!, isTrue);
    });
  });

  group('PrimaryButton', () {
    testWidgets('押すと呼ばれ、busy の間は押せず輪を出す', (tester) async {
      var taps = 0;
      await pump(
        tester,
        PrimaryButton(
          key: const ValueKey('go'),
          label: '始める',
          icon: Icons.play_arrow,
          onPressed: () => taps++,
        ),
      );
      expect(find.text('始める'), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton)).height, 56);
      await tester.tap(find.byKey(const ValueKey('go')));
      expect(taps, 1);

      await pump(
        tester,
        PrimaryButton(label: '始める', busy: true, onPressed: () => taps++),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('始める'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });

  testWidgets('ProBadge: 文字とゴールドの面', (tester) async {
    await pump(tester, const ProBadge());
    expect(find.text('PRO'), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration! as BoxDecoration).color, AppColors.gold);
  });

  testWidgets('SectionHeader: 見出しと右の操作', (tester) async {
    await pump(
      tester,
      SectionHeader(
        '候補',
        trailing: TextButton(onPressed: () {}, child: const Text('すべて')),
      ),
    );
    expect(find.text('候補'), findsOneWidget);
    expect(find.text('すべて'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.header ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('GroupedSection: 見出し・行の間の区切り線・補足', (tester) async {
    await pump(
      tester,
      const GroupedSection(
        title: '通知',
        footer: '端末が毎朝知らせます',
        children: [
          ListTile(title: Text('A')),
          ListTile(title: Text('B')),
          ListTile(title: Text('C')),
        ],
      ),
    );
    expect(find.text('通知'), findsOneWidget);
    expect(find.text('端末が毎朝知らせます'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('AppCard: タップできる', (tester) async {
    var taps = 0;
    await pump(
      tester,
      AppCard(
        key: const ValueKey('card'),
        onTap: () => taps++,
        child: const Text('中身'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('card')));
    expect(taps, 1);
  });

  testWidgets('EmptyState / LoadingState / NoticeCard', (tester) async {
    await pump(
      tester,
      Column(
        children: [
          EmptyState(
            message: 'まだありません',
            messageKey: const ValueKey('empty'),
            action: TextButton(onPressed: () {}, child: const Text('再試行')),
          ),
          const EmptyState.error(message: '失敗しました'),
          const NoticeCard(
            title: '注意',
            message: '暗いです',
            icon: Icons.warning_amber,
            tone: NoticeTone.caution,
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('empty')), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('注意'), findsOneWidget);
    expect(find.text('暗いです'), findsOneWidget);

    await pump(tester, const LoadingState(message: '作っています'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('作っています'), findsOneWidget);
  });

  testWidgets('TileFan: 牌を並べ、読み上げには出さない', (tester) async {
    await pump(tester, const TileFan(labels: ['1m', '2m', '3m'], highlight: 1));
    expect(find.byType(Image), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

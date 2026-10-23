import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 共有カードのサイズ（仕様 6.10。幅 1080px で書き出す）。
enum ShareCardFormat {
  /// 1:1（X・LINE・フィード）。
  square,

  /// 9:16（ストーリー）。
  story;

  /// カードを描く論理サイズ。書き出しは [pixelRatio] 倍で幅 1080px になる。
  Size get logicalSize => switch (this) {
    ShareCardFormat.square => const Size(360, 360),
    ShareCardFormat.story => const Size(360, 640),
  };

  double get pixelRatio => 1080 / logicalSize.width;

  bool get isStory => this == ShareCardFormat.story;

  /// `share_format` の値（分析用）。
  String get analyticsValue => isStory ? 'story' : 'feed';
}

// ブランドの配色（ui/theme/app_colors.dart）に合わせる。
const kCardGreen = [AppColors.cardBackgroundLight, AppColors.cardBackground];
const kCardGold = AppColors.cardGold;
const kCardInk = AppColors.cardInk;

/// カードの左上に描くアプリのアイコン（pubspec の assets に登録済み）。
const kAppMarkAsset = 'assets/branding/app_mark.png';

/// すべての共有カードの外枠: 背景・ヘッダ（アプリ名）・本文・フッタ（ストア誘導と QR）・
/// 透かし（無料のみ）。
///
/// 画面のスクリーンショットではなく固定レイアウトを描く。文字サイズの端末設定には
/// 左右されない。写真は載せない（仕様 8.4）。
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.format,
    required this.strings,
    required this.qrUrl,
    required this.qrCaption,
    required this.body,
    this.headerTrailing,
    this.footerLead,
    this.storeLead,
    this.watermark = false,
    this.gradient = kCardGreen,
  });

  final ShareCardFormat format;
  final ShareStrings strings;

  /// QR が指す URL（問題カードは問題ページ、ほかはストア）。
  final String qrUrl;

  /// QR の下の説明（「スキャンして答える」など）。
  final String qrCaption;

  final Widget body;

  /// ヘッダ右側の短い説明（「東場 南家」など）。
  final String? headerTrailing;

  /// フッタ左側の補足（「出題: まじゃおう」など）。
  final String? footerLead;

  /// フッタの金色の誘導文。省略時は「解説はアプリで」（[ShareStrings.seeExplanation]）。
  final String? storeLead;

  /// 無料のとき true で透かしを重ねる。
  final bool watermark;

  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final size = format.logicalSize;
    final story = format.isStory;
    final qrSize = story ? 96.0 : 72.0;
    return MediaQuery(
      // 端末の文字サイズ設定に左右されない固定レイアウトにする。
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.25,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, story ? 40 : 14, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        SizedBox(height: story ? 24 : 8),
                        Expanded(child: body),
                        SizedBox(height: story ? 14 : 6),
                        _footer(qrSize),
                      ],
                    ),
                  ),
                  if (watermark) _watermark(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        // アプリのアイコン（角丸）。
        ClipRRect(
          key: const ValueKey('share-card-logo'),
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            kAppMarkAsset,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stack) => const SizedBox.square(
              dimension: 24,
              child: ColoredBox(color: kCardGold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          strings.appName,
          key: const ValueKey('share-card-app-name'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 10),
        if (headerTrailing != null)
          Expanded(
            child: Text(
              headerTrailing!,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }

  Widget _footer(double qrSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (footerLead != null && footerLead!.isNotEmpty) ...[
                Text(
                  footerLead!,
                  key: const ValueKey('share-card-footer-lead'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                storeLead ?? strings.seeExplanation,
                key: const ValueKey('share-card-store-lead'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: kCardGold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strings.storeGuide,
                key: const ValueKey('share-card-store-guide'),
                maxLines: 2,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('share-card-qr'),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: CardQr(url: qrUrl, size: qrSize),
            ),
            const SizedBox(height: 2),
            Text(
              qrCaption,
              key: const ValueKey('share-card-qr-caption'),
              style: const TextStyle(fontSize: 9, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  Widget _watermark() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Transform.rotate(
            angle: -0.45,
            child: Text(
              strings.watermark,
              key: const ValueKey('share-card-watermark'),
              style: TextStyle(
                fontSize: format.isStory ? 56 : 48,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.13),
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 金色の丸い見出しチップ。
class CardChip extends StatelessWidget {
  const CardChip(
    this.text, {
    super.key,
    this.filled = false,
    this.fontSize = 12,
  });

  final String text;
  final bool filled;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? kCardGold : null,
        border: filled
            ? null
            : Border.all(color: kCardGold.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: filled ? FontWeight.w800 : FontWeight.normal,
          color: filled ? kCardInk : Colors.white,
        ),
      ),
    );
  }
}

/// カードの QR コード（[url] を黒地なしの白背景で描く）。
class CardQr extends StatelessWidget {
  const CardQr({super.key, required this.url, required this.size});

  /// QR が指す URL（問題ページ `/p/{id}?ref=…` またはストア）。
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: url,
      size: size,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }
}

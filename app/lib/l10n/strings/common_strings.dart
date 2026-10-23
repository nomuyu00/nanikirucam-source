import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 画面をまたいで使う文言。機能固有の文言は各機能の `*_strings.dart` に置く。
class CommonStrings extends FeatureStrings {
  const CommonStrings(super.lang);

  String get appName => tr('なにきるカム', 'Nanikiru Cam');

  String get ok => 'OK';
  String get cancel => tr('キャンセル', 'Cancel');
  String get close => tr('閉じる', 'Close');
  String get retry => tr('再試行', 'Retry');
  String get done => tr('完了', 'Done');
  String get back => tr('戻る', 'Back');
  String get next => tr('次へ', 'Next');
  String get delete => tr('削除', 'Delete');
  String get undo => tr('元に戻す', 'Undo');
  String get clear => tr('クリア', 'Clear');
  String get loading => tr('読み込み中', 'Loading');
  String get comingSoon => tr('準備中', 'Coming soon');
  String get openSettings => tr('設定を開く', 'Open settings');
  String get maybe => tr('もしかして', 'Maybe');

  /// 牌の名前（`5m` → 「5萬」、`0p` → 「赤5筒」）。
  String tileName(String label) => tileDisplayName(label, english: isEnglish);

  String windName(Wind wind) => switch (wind) {
    Wind.east => tr('東', 'East'),
    Wind.south => tr('南', 'South'),
    Wind.west => tr('西', 'West'),
    Wind.north => tr('北', 'North'),
  };

  String get dealer => tr('親', 'Dealer');
  String get nonDealer => tr('子', 'Non-dealer');

  String tileCount(int n) => tr('$n枚', '$n tiles');

  /// シャンテン数の表示（-1 = 和了、0 = テンパイ、1 = 一向聴 …）。
  String shanten(int value) {
    if (value < 0) return tr('和了', 'Complete');
    if (value == 0) return tr('テンパイ', 'Tenpai');
    const kanji = ['', '一', '二', '三', '四', '五', '六'];
    if (isEnglish) return '$value-shanten';
    return '${value < kanji.length ? kanji[value] : value}向聴';
  }
}

extension CommonStringsContext on BuildContext {
  CommonStrings get commonStrings => CommonStrings(lang);
}

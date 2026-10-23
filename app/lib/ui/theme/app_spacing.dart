import 'package:flutter/widgets.dart';

/// 余白の段階（4 の倍数を基本にする）。画面では数値を直書きせずこれを使う。
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 画面の左右の余白。
  static const double gutter = 16;

  /// セクションどうしの間隔。
  static const double section = 24;

  /// 画面の本文の標準の余白（左右 [gutter]、上下 [md]）。
  static const EdgeInsets page = EdgeInsets.fromLTRB(gutter, md, gutter, xl);

  /// カードの中の標準の余白。
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// 角丸の段階。
abstract final class AppRadius {
  /// 小さなバッジ・タグ。
  static const double xs = 6;

  /// チップ・小さなボタン。
  static const double sm = 10;

  /// ボタン・入力欄。
  static const double md = 14;

  /// カード。
  static const double lg = 18;

  /// ヒーロー・シート・ダイアログ。
  static const double xl = 26;

  /// 丸いピル。
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

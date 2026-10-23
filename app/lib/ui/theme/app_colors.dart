import 'package:flutter/material.dart';

/// なにきるカムのブランド色と、意味のある色（状態・軸・役の確度など）。
///
/// 画面では `Colors.xxx` や `Color(0x..)` を直書きせず、ここの定数か
/// `Theme.of(context).colorScheme` を使う。アプリアイコンの配色と合わせる値は
/// [AppColors.jade]・[AppColors.ivory]・[AppColors.vermilion]・[AppColors.gold]。
///
/// ダークモードは未対応（ライト固定）。
abstract final class AppColors {
  // ---- ブランド ----

  /// 麻雀卓の深いジェイド（primary）。
  static const jade = Color(0xFF0E6B4F);

  /// ジェイドの濃い側（ヒーローのグラデーションの終点・押下時）。
  static const jadeDeep = Color(0xFF07452F);

  /// ジェイドの明るい側（グラデーションの始点）。
  static const jadeBright = Color(0xFF178A66);

  /// ジェイドの淡い面（primaryContainer）。
  static const jadeTint = Color(0xFFD3ECE0);

  /// 牌のアイボリー（背景）。
  static const ivory = Color(0xFFFAF7F0);

  /// 牌の面の暖かい白（カード・シートの面）。
  static const tileFace = Color(0xFFFFFDF8);

  /// アイボリーの濃い側（区切り・面の重なり）。
  static const ivoryDeep = Color(0xFFEFE8D9);

  /// 朱（アクセント。「切る牌」の強調）。
  static const vermilion = Color(0xFFD2452E);

  /// 朱の淡い面。
  static const vermilionTint = Color(0xFFFCE3DC);

  /// ゴールド（Pro・特別感）。面や枠に使う。
  static const gold = Color(0xFFC99A2E);

  /// ゴールドの文字用（白地でも読める濃さ）。
  static const goldDeep = Color(0xFF8A6512);

  /// ゴールドの淡い面。
  static const goldTint = Color(0xFFF7EBCB);

  // ---- 文字・線 ----

  static const ink = Color(0xFF1B1D1A);
  static const inkMuted = Color(0xFF5B5E57);
  static const outline = Color(0xFF8B8C83);
  static const outlineSoft = Color(0xFFE2DCCD);

  // ---- 意味のある色 ----

  /// 正解・成功。
  static const success = Color(0xFF1E7A4C);

  /// 別の軸なら正解・注意。
  static const caution = Color(0xFFB26200);

  /// 不正解・エラー。
  static const danger = Color(0xFFB3261E);

  /// 情報（青系）。
  static const info = Color(0xFF2C5DA8);

  /// 戦略の軸（速さ・打点・バランス）。色だけに頼らず文字も添える。
  static const axisSpeed = Color(0xFF117A80);
  static const axisPoints = Color(0xFFC2481F);
  static const axisBalance = Color(0xFF3F4FA0);

  /// 役の確度（確定・濃厚・狙える・消える。仕様 4.3）。
  static const confidenceCertain = Color(0xFF2E7D32);
  static const confidenceLikely = Color(0xFF1565C0);
  static const confidencePossible = Color(0xFFB25E00);
  static const confidenceLost = Color(0xFFC62828);

  /// ストリークの炎。
  static const streak = Color(0xFFE2622B);

  // ---- ライブ・カメラ（カメラの上に重ねる色。仕様 6.3） ----
  // 値は刷新前のライブ画面と同じ（見た目を変えずに定数化した）。

  /// 面子の枠・状態「確定」。
  static const liveOk = Color(0xFF4CAF50);

  /// 搭子の枠。
  static const liveTaatsu = Color(0xFF42A5F5);

  /// 孤立牌の枠・状態「一時停止」。
  static const liveIdle = Color(0xFF9E9E9E);

  /// おすすめ（切る牌）の枠と矢印。
  static const liveRecommend = Color(0xFFFFD600);

  /// おすすめの文字・案内の強調（黄）。
  static const liveAccent = Color(0xFFFFFF00);

  /// 確度低の枠。
  static const liveError = Color(0xFFFF5252);

  /// 状態「探索中」。
  static const liveSearching = Color(0xFF607D8B);

  /// 状態「手が動いています」・注意。
  static const liveWarn = Color(0xFFFF9800);

  /// 状態「暗い」。
  static const liveDark = Color(0xFF673AB7);

  /// 状態「遠い」。
  static const liveFar = Color(0xFF3F51B5);

  /// 状態「枚数が違う」。
  static const liveMismatch = Color(0xFFF44336);

  /// 案内の帯（鳴いた手は写真解析で、など）。
  static const liveNotice = Color(0xFFEF6C00);

  /// 情報のバッジ（青）。
  static const liveInfo = Color(0xFF1976D2);

  /// 情報のラベルの地（半透明の青）。
  static const liveInfoScrim = Color(0xCC1565C0);

  /// 良い知らせの文字（リーチできます）。
  static const liveGood = Color(0xFFB2FF59);

  /// 注意の文字（役がありません）。
  static const liveCaution = Color(0xFFFFAB40);

  /// リンク・補足の文字（水色）。
  static const liveLink = Color(0xFF40C4FF);

  /// カメラの上の半透明の面（黒 54%）。
  static const liveScrim = Color(0x8A000000);

  /// 濃い半透明の面（黒 87%）。
  static const liveScrimStrong = Color(0xDD000000);

  /// 牌のラベルの地（黒 60%）。
  static const liveLabelScrim = Color(0x99000000);

  /// カメラ画面の地（ほぼ黒）。
  static const camera = Color(0xFF0B0F0D);

  /// ライブの下部パネル・上部の操作の地（ジェイドを含んだ黒のガラス、90%）。
  static const livePanel = Color(0xE60F1713);

  /// ライブの丸いボタン・バッジの地（ジェイドを含んだ黒のガラス、62%）。
  static const liveGlass = Color(0x9E0F1713);

  /// 暗い面の上の文字（白）。
  static const liveText = Color(0xFFFFFFFF);

  /// 暗い面の上の補足の文字（白 70%）。
  static const liveTextMuted = Color(0xB3FFFFFF);

  /// 暗い面の上の注記の文字（白 54%）。
  static const liveTextFaint = Color(0x8AFFFFFF);

  /// 暗い面の上の細い線（白 16%）。
  static const liveHairline = Color(0x29FFFFFF);

  /// 暗い面の上の「切る牌」（朱を明るくして、暗い地でも読める濃さにしたもの）。
  static const liveDiscard = Color(0xFFFF6B4A);

  // ---- 共有カード（share/cards/。画像に焼き込むので固定値） ----

  /// 共有カードの地（グラデーションの終点。ジェイドより深い緑）。
  static const cardBackground = Color(0xFF063B29);

  /// 共有カードの地の明るい側（グラデーションの始点。ブランドのジェイド）。
  static const cardBackgroundLight = Color(0xFF0E6B4F);

  /// 共有カードの金（見出し・枠）。
  static const cardGold = Color(0xFFE9C46A);

  /// 共有カードの金の上の文字。
  static const cardInk = Color(0xFF3A2A00);
}

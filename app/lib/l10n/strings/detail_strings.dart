import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// 候補の詳細・解説（result/candidate_detail_page.dart・explanation_page.dart）の
/// 見出しなど、画面の組み立てに使う文言。解析の中身の文言は result_strings.dart。
class DetailStrings extends FeatureStrings {
  const DetailStrings(super.lang);

  /// 結論のカードの上の小さな見出し。
  String get conclusion => tr('結論', 'Bottom line');

  /// 数字の要約（受け入れ・上がりやすさ・打点・良形率）の見出し。
  String get evidence => tr('数字で見る', 'Key numbers');

  /// 解説の根拠（理由・ブロック分解・3 軸との比較）の見出し。
  String get reasoning => tr('根拠', 'Reasoning');

  /// くわしい内訳の見出し。
  String get details => tr('くわしく', 'In detail');

  /// 数字の要約の受け入れ（見出しが「受け入れ」なので数だけ）。
  String ukeireValue(int kinds, int total) =>
      tr('$kinds種 $total枚', '$total tiles · $kinds kinds');

  /// 比較表で、いま見ている候補の行の見出し。
  String get thisCandidate => tr('この候補', 'This one');

  /// 比較表の注記。
  String get compareNote => tr(
    '受け入れは枚数、打点は想定の中央値、上がりやすさは残り枚数と巡目からの目安',
    'Outs in tiles, points as the expected median, win chance from tiles left and the turn',
  );
}

extension DetailStringsContext on BuildContext {
  DetailStrings get detailStrings => DetailStrings(lang);
}

import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// クイズ（quiz/）の文言。手牌の表示（ドラ表示など）もここに置く。
class QuizStrings extends FeatureStrings {
  const QuizStrings(super.lang);

  String get title => tr('あなたなら何を切る？', 'What would you discard?');
  String get prompt => tr('切る牌をタップして選んでください', 'Tap the tile you would discard');
  String get judgeAxis => tr('どの方針で答える？', 'Judge my answer by');
  String get judgeAxisHelp => tr(
    '選んだ方針の正解と照らし合わせて採点します。迷ったら既定の「バランス」のままで大丈夫です。',
    'Your pick is graded against the best discard for this strategy. Not sure? Keep the default, Balance.',
  );
  String confirm(String tile) => tr('打 $tile で答える', 'Discard $tile');
  String get confirmDisabled => tr('牌を選んでください', 'Pick a tile');
  String get skip => tr('わからない（答えを見る）', 'Not sure — show the answer');
  String secondsLeft(int s) => tr('残り $s 秒', '$s s left');
  String get timeUp => tr('時間切れ', 'Time is up');
  String get tsumoMark => tr('ツモ', 'Drawn');
  String get doraIndicator => tr('ドラ表示', 'Dora indicator');
  String get dora => tr('ドラ', 'Dora');
  String get noHand => tr('問題の手がありません', 'No hand to quiz');
  String get preparing => tr('解析の準備中…', 'Preparing the analysis…');
  String turn(int n) => tr('$n巡目', 'Turn $n');
  String roundSeat(String round, String seat) =>
      tr('$round場 $seat家', '$round round, $seat seat');
}

extension QuizStringsContext on BuildContext {
  QuizStrings get quizStrings => QuizStrings(lang);
}

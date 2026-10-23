import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// 課金画面（purchase/）の文言。
class PaywallStrings extends FeatureStrings {
  const PaywallStrings(super.lang);

  String get title => tr('Pro プラン', 'Pro plan');
  String get proReviewTitle => tr('Pro（審査用アクセス）', 'Pro (review access)');
  String get close => tr('閉じる', 'Close');

  /// トリガー別の見出し（仕様 6.11、10 章）。
  String headline(PaywallTrigger trigger) => switch (trigger) {
    PaywallTrigger.liveTrialEnded => tr(
      '今日のライブ体験は終わりました',
      'Today\'s Live trial is over',
    ),
    PaywallTrigger.quotaExhausted => tr(
      '今日の解析回数を使い切りました',
      'You\'ve used today\'s analyses',
    ),
    PaywallTrigger.candidateLocked => tr(
      'すべての候補と役の確度は Pro で',
      'See every candidate and yaku odds with Pro',
    ),
    PaywallTrigger.explanationLocked => tr(
      '解説の詳細は Pro で',
      'Unlock detailed explanations with Pro',
    ),
    PaywallTrigger.todayLimit => tr(
      '今日の問題は 1 日 3 問までです',
      'Free accounts get 3 daily problems',
    ),
    PaywallTrigger.historyLocked => tr(
      'すべての履歴と弱点分析は Pro で',
      'See your full history and weak spots with Pro',
    ),
    PaywallTrigger.winScore => tr(
      '和了の役と点数は Pro で',
      'Score your winning hands with Pro',
    ),
    PaywallTrigger.home ||
    PaywallTrigger.settings => tr('なにきるカム Pro', 'Nanikiru Cam Pro'),
  };

  /// 見出しの下の説明。
  String subhead(PaywallTrigger trigger) => switch (trigger) {
    PaywallTrigger.liveTrialEnded => tr(
      'Pro なら、ライブナビを時間の制限なく使えます。',
      'With Pro, Live Navi has no time limit.',
    ),
    PaywallTrigger.quotaExhausted => tr(
      'Pro なら、写真解析が無制限になります。',
      'With Pro, photo analysis is unlimited.',
    ),
    PaywallTrigger.winScore => tr(
      '和了の手を撮るだけで、役・符・点数・支払いを計算して、画像で共有できます。',
      'Snap a winning hand to get yaku, fu, points and payments, and share them as an image.',
    ),
    _ => tr(
      'カメラを向けるだけの何切るを、制限なく。',
      'Camera-powered discard advice, without limits.',
    ),
  };

  /// 体験終了時の recap（直前のライブの実績。仕様 10 章）。
  String? liveRecap(int? adviceCount, int? winCount) {
    if (adviceCount == null || adviceCount <= 0) return null;
    final wins = winCount ?? 0;
    return tr(
      'このセッションで$adviceCount回案内、$wins回和了',
      'This session: $adviceCount suggestions, $wins wins',
    );
  }

  // --- 訴求（仕様 10 章の順: ライブナビ → 全候補と役 → 今日の問題 → 役と点数 → 広告なし） ---
  String get benefitLive => tr('ライブナビが無制限', 'Unlimited Live Navi');
  String get benefitLiveSub => tr(
    '実卓にカメラを向けるだけで、切る牌を案内します。',
    'Point the camera at the table and get discard suggestions.',
  );
  String get benefitCandidates =>
      tr('全候補と役の確度', 'All candidates and yaku odds');
  String get benefitCandidatesSub => tr(
    '速さ・打点・バランスの 3 軸で、狙える役と想定打点まで。',
    'Speed, value and balance, with reachable yaku and expected points.',
  );
  String get benefitToday =>
      tr('過去の今日の問題も解ける', 'Solve past daily problems too');
  String get benefitTodaySub => tr(
    '無料はその日の3問。Pro なら前の日の問題にもさかのぼれます。',
    'Free gets that day\'s 3 problems. With Pro you can go back to earlier days.',
  );
  String get benefitWinScore =>
      tr('和了の役と点数を計算・共有', 'Score and share winning hands');
  String get benefitWinScoreSub => tr(
    '撮った和了形から役・翻・符・点数・支払いまで。点数クイズの画像も作れます。',
    'Yaku, han, fu, points and payments from a photo, plus score-quiz images.',
  );
  String get benefitNoAds => tr('広告なし', 'No ads');
  String get benefitNoAdsSub =>
      tr('バナーも全画面広告も表示しません。', 'No banners or full-screen ads.');

  // --- プラン ---
  String get monthly => tr('月額', 'Monthly');
  String get yearly => tr('年額', 'Yearly');
  String perMonth(String price) => tr('$price / 月', '$price / month');
  String perYear(String price) => tr('$price / 年', '$price / year');
  String get bestValue => tr('おすすめ', 'Best value');
  String trialBadge(int days) => tr('$days日間無料', '$days-day free trial');
  String yearlyPerMonth(String perMonth) =>
      tr('月あたり $perMonth', '$perMonth / month');

  String ctaTrial(int days) => tr('$days日間無料で試す', 'Try free for $days days');
  String get ctaSubscribe => tr('Pro を始める', 'Start Pro');

  /// 自動更新・トライアルの注記（ストアの審査で必須の表示）。
  String disclosure(String price, {required bool yearly, int? trialDays}) {
    if (yearly) {
      return tr(
        '$price が 1 年ごとに自動更新されます。',
        '$price is charged every year and renews automatically.',
      );
    }
    if (trialDays != null) {
      return tr(
        '$trialDays日間無料のあと、$price / 月が自動で課金されます。'
            'トライアル終了の 24 時間前までに解約しないと自動更新されます。',
        'After the $trialDays-day free trial, $price / month is charged automatically. '
            'It renews unless you cancel at least 24 hours before the trial ends.',
      );
    }
    return tr(
      '$price が 1 か月ごとに自動更新されます。',
      '$price is charged every month and renews automatically.',
    );
  }

  String get cancelInfo => cancelInfoFor(defaultTargetPlatform);

  String cancelInfoFor(TargetPlatform platform) {
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final ja = apple ? '設定 > Apple Account > サブスクリプション' : 'Google Play > 定期購入';
    final en = apple
        ? 'Settings > Apple Account > Subscriptions'
        : 'Google Play > Subscriptions';
    return tr(
      'いつでも解約できます。$ja から解約してください。解約しても期間の終わりまで Pro を使えます。',
      'Cancel anytime in $en. You keep Pro until the end of the paid period.',
    );
  }

  String get manageSubscription =>
      tr('購読の管理・解約', 'Manage or cancel subscription');
  String get restore => tr('購入を復元', 'Restore purchases');
  String get terms => tr('利用規約', 'Terms of Use');
  String get privacy => tr('プライバシーポリシー', 'Privacy Policy');
  String get tokushoho => tr('購入に関するご案内', 'Purchase information');

  // --- 状態 ---
  String get notReadyTitle => tr('準備中です', 'Coming soon');
  String get notReadyBody =>
      tr('Pro プランは、まもなくご利用いただけます。', 'Pro plans will be available soon.');
  String get loadingPlans => tr('プランを読み込み中', 'Loading plans');
  String get plansFailed => tr(
    'プランを読み込めませんでした。通信状況を確認してください。',
    'Could not load plans. Check your connection.',
  );
  String get retry => tr('再試行', 'Retry');
  String get processing => tr('処理中', 'Working');

  // --- 結果 ---
  String get purchaseSuccess =>
      tr('Pro をご利用いただけます。ありがとうございます！', 'You\'re now on Pro. Thank you!');
  String get purchaseFailed => tr(
    '購入できませんでした。もう一度お試しください。',
    'The purchase could not be completed. Please try again.',
  );
  String get purchasePending => tr(
    '決済の承認待ちです。承認されると Pro が有効になります。',
    'Your payment is pending approval. Pro will start once it is approved.',
  );
  String get unavailable => tr(
    'いま購入できません。時間をおいてお試しください。',
    'Purchases are unavailable right now. Please try again later.',
  );
  String get restored => tr('購入を復元しました。', 'Your purchase has been restored.');
  String get nothingToRestore =>
      tr('復元できる購入が見つかりませんでした。', 'No purchases were found to restore.');
  String get restoreFailed => tr(
    '復元できませんでした。通信状況を確認して、もう一度お試しください。',
    'Could not restore. Check your connection and try again.',
  );

  // --- Pro 利用中 ---
  String get proActiveTitle => tr('Pro をご利用中です', 'You\'re on Pro');
  String get proTrialTitle => tr('Pro（無料トライアル中）', 'Pro (free trial)');
  String get proReferralTitle =>
      tr('紹介特典で Pro を利用中', 'Pro from a referral reward');
  String proUntil(String date) => tr('$date まで', 'Until $date');
}

extension PaywallStringsContext on BuildContext {
  PaywallStrings get paywallStrings => PaywallStrings(lang);
}

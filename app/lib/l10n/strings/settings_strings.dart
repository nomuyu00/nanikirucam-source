import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/referral/referral_failure.dart';

/// 設定（ui/settings/）と招待コード（referral/）の文言。
class SettingsStrings extends FeatureStrings {
  const SettingsStrings(super.lang);

  String get title => tr('設定', 'Settings');

  // --- Pro ---
  String get sectionPlan => tr('プラン', 'Plan');
  String get planFree => tr('無料プラン', 'Free plan');
  String get planPro => tr('Pro プラン', 'Pro plan');
  String get planProTrial => tr('Pro（無料トライアル中）', 'Pro (free trial)');
  String get planProReferral => tr('Pro（紹介特典）', 'Pro (referral reward)');
  String get planProReview => tr('Pro（審査用アクセス）', 'Pro (review access)');
  String get reviewAccess => tr('審査用アクセス', 'Review access');
  String get reviewAccessBody => tr(
    '審査担当者向けの期限付きアクセスです。購入・定期購読は発生しません。解除すると通常の購入状態に戻ります。',
    'Time-limited access for app reviewers. This does not purchase or start a subscription. Deactivate to return to your store entitlement.',
  );
  String get reviewCode => tr('審査用コード', 'Review code');
  String get reviewActivate => tr('有効にする', 'Activate');
  String get reviewDeactivate => tr('審査用アクセスを解除', 'Deactivate review access');
  String get reviewUnavailable => tr(
    'このビルドでは審査用アクセスを利用できないか、有効期限が終了しています。',
    'Review access is unavailable in this build or has expired.',
  );
  String get reviewInvalid => tr('コードを確認してください。', 'Check the review code.');
  String get reviewFailed => tr(
    '端末に保存できませんでした。もう一度お試しください。',
    'Could not save on this device. Please try again.',
  );
  String get reviewActivated =>
      tr('審査用アクセスを有効にしました。', 'Review access activated.');
  String get licenses => tr('ライセンス・出典', 'Licenses & credits');
  String get datasetCredit => tr(
    '学習データ: master v7 (2023-09-20 9:29pm) / majmaster\n'
        'https://universe.roboflow.com/majmaster/master-oez61/dataset/7\n'
        'CC BY 4.0: https://creativecommons.org/licenses/by/4.0/\n'
        '画像のリサイズ・拡張と独自の分割を行い、牌認識モデルの学習に使用しています。データセットの画像自体は同梱していません。提供者による本アプリの推奨を意味しません。',
    'Training data: master v7 (2023-09-20 9:29pm) / majmaster\n'
        'https://universe.roboflow.com/majmaster/master-oez61/dataset/7\n'
        'CC BY 4.0: https://creativecommons.org/licenses/by/4.0/\n'
        'Used to train tile recognition models with resizing, augmentation and custom splits. Dataset images are not bundled. The provider does not endorse this app.',
  );
  String get planUpgrade => tr(
    'Pro でライブ無制限・全候補・広告なし',
    'Go Pro: unlimited Live, all candidates, no ads',
  );
  String planUntil(String date) => tr('$date まで', 'Until $date');
  String get seePro => tr('Pro プランを見る', 'See Pro plan');
  String get restorePurchases => tr('購入を復元', 'Restore purchases');
  String get manageSubscription =>
      tr('購読の管理・解約', 'Manage or cancel subscription');
  String get restoring => tr('復元しています', 'Restoring');
  String get restored => tr('購入を復元しました。', 'Your purchase has been restored.');
  String get nothingToRestore =>
      tr('復元できる購入が見つかりませんでした。', 'No purchases were found to restore.');
  String get restoreFailed => tr(
    '復元できませんでした。通信状況を確認してください。',
    'Could not restore. Check your connection.',
  );
  String get storeUnavailable =>
      tr('いま購入の復元はできません。', 'Restoring purchases is unavailable right now.');

  // --- トップの行（サブページへ） ---
  String get sectionPreferences => tr('アプリの設定', 'Preferences');
  String get sectionRulesCamera => tr('ルールと撮影', 'Rules & camera');
  String liveRowSummary(String axis, bool haptics) => tr(
    '最初の軸: $axis・振動${haptics ? 'オン' : 'オフ'}',
    'Starts on $axis · Vibration ${haptics ? 'on' : 'off'}',
  );
  String notificationsRowSummary(int on, int total) => on == 0
      ? tr('すべてオフ', 'All off')
      : on == total
      ? tr('すべてオン', 'All on')
      : tr('$total 件中 $on 件オン', '$on of $total on');
  String rulesRowSummary({
    required bool redFives,
    required bool openTanyao,
    required bool quickCapture,
  }) => [
    tr('赤ドラ${redFives ? 'あり' : 'なし'}', 'Red fives ${redFives ? 'on' : 'off'}'),
    tr(
      '喰いタン${openTanyao ? 'あり' : 'なし'}',
      'Open tanyao ${openTanyao ? 'on' : 'off'}',
    ),
    if (quickCapture) tr('撮るだけモード', 'Quick capture'),
  ].join(tr('・', ' · '));

  // --- サブページの小見出し ---
  String get sectionLiveFeedback => tr('案内の知らせ方', 'When advice appears');
  String get sectionLiveGuide => tr('置き方', 'Setup');
  String get sectionNotificationsProblems =>
      tr('問題と連続回答', 'Problems and streak');

  // --- ルール・ライブ ---
  String get sectionRules => tr('ルール', 'Rules');
  String get redFives => tr('赤ドラあり', 'Red fives');
  String get redFivesSub =>
      tr('各色の 5 を 1 枚ずつ赤にします。', 'One red 5 in each suit.');
  String get openTanyao => tr('喰いタンあり', 'Open tanyao');
  String get openTanyaoSub =>
      tr('副露しても断么九が成立します。', 'Tanyao counts even with open melds.');
  String get sectionCamera => tr('撮影', 'Camera');
  String get quickCapture => tr('撮るだけモード', 'Quick capture');
  String get quickCaptureSub => tr(
    '撮影して認識した手を、解析せずに履歴へ保存します。続けて撮れます。写真は保存しません。履歴から確認・解析できます。',
    'Saves recognized hands to History without analyzing them, so you can keep shooting. Photos are not saved. Review and analyze them from History.',
  );

  // --- ライブ ---
  String get sectionLive => tr('ライブナビ', 'Live Navi');
  String get liveDefaultAxis => tr('最初に表示する軸', 'Default strategy');
  String get liveDefaultAxisSub => tr(
    'ライブを始めたときの「速さ・打点・バランス」の選択です。',
    'The strategy selected when Live starts.',
  );
  String get axisSpeed => tr('速さ', 'Speed');
  String get axisPoints => tr('打点', 'Points');
  String get axisBalance => tr('バランス', 'Balance');
  String get liveHaptics => tr('案内が変わったら振動', 'Vibrate on new advice');
  String get liveHapticsSub =>
      tr('新しい案内が出たときに軽く振動します。', 'A light vibration when new advice appears.');
  String get liveSound => tr('ライブで案内音を鳴らす', 'Sound for Live suggestions');
  String get liveSoundSub =>
      tr('案内が出たときに短い音を鳴らします。', 'Play a short sound when a suggestion appears.');
  String get liveLockBrightness => tr('画面の明るさを固定', 'Keep screen brightness');
  String get liveLockBrightnessSub => tr(
    'ライブ中は始めたときの明るさのままにし、自動調整で暗くなるのを防ぎます。',
    'Keeps the brightness from when Live started so it does not dim.',
  );
  String get liveGuide => tr('置き方の案内をもう一度見る', 'Show the setup guide again');
  String get liveGuideSub => tr(
    '次にライブを始めるときに、スタンドの置き方（斜め 30〜45°）の案内を出します。',
    'The setup guide (stand at 30–45°) appears the next time Live starts.',
  );
  String get liveGuideReset => tr(
    '次にライブを始めるときに案内を出します。',
    'The guide will appear the next time Live starts.',
  );

  // --- 通知 ---
  String get sectionNotifications => tr('通知', 'Notifications');
  String get notifyDaily => tr('今日の問題', 'Problem of the day');
  String get notifyDailySub =>
      tr('毎朝、その日の問題をお知らせします。', 'A daily morning notice.');
  String get notifyWeekly => tr('週間の難問・成績', 'Weekly digest');
  String get notifyWeeklySub => tr('週に 1 回、今週の難問をお知らせします。', 'Once a week.');
  String get notifyAnswers => tr('回答が集まったとき', 'When your problem gets answers');
  String get notifyAnswersSub =>
      tr('出題した問題への回答が増えたときにお知らせします。', 'For problems you published.');
  String get notifyStreak => tr('連続回答のリマインド', 'Streak reminder');
  String get notifyStreakSub => tr(
    '今日まだ解いていないとき、21:00 にお知らせします。',
    'At 21:00 if you haven\'t solved today\'s problem.',
  );
  String get notifyLiveSummary => tr('昨日の対局サマリー', "Yesterday's Live summary");
  String get notifyLiveSummarySub => tr(
    'ライブを使った 24 時間後に、対局の振り返りをお知らせします。',
    '24 hours after you use Live, a recap of the match.',
  );
  String get notificationsDenied => tr(
    '通知が許可されていません。端末の設定から、このアプリの通知を許可してください。',
    'Notifications are off. Allow them for this app in your device settings.',
  );

  // --- 言語 ---
  String get sectionLanguage => tr('言語', 'Language');
  String get languageSystem => tr('端末に従う', 'Device');
  String get languageJapanese => '日本語';
  String get languageEnglish => 'English';

  // --- プライバシー ---
  String get sectionPrivacy => tr('プライバシー', 'Privacy');
  String get adPrivacy => tr('広告のプライバシー設定', 'Ad privacy settings');
  String get adPrivacySub =>
      tr('広告のパーソナライズに関する同意を変更します。', 'Change your ad personalization consent.');

  // --- 招待コード ---
  String get sectionReferral => tr('招待コード', 'Invite code');
  String get referralLead => tr(
    '友だちに招待コードを送ると、使った人とあなたの両方が Pro を 7 日間無料で使えます。',
    'Share your code: you and your friend both get 7 days of Pro.',
  );
  String get myCode => tr('あなたの招待コード', 'Your invite code');
  String get codeUnavailable => tr(
    'コードを準備しています。オンラインのときに表示されます。',
    'Your code appears when you are online.',
  );
  String get copy => tr('コピー', 'Copy');
  String get copied => tr('コピーしました', 'Copied');
  String get share => tr('共有', 'Share');
  String shareText(String code, String url) => tr(
    'なにきるカムで何切るを一緒に解こう！招待コード $code を入力すると、'
        'お互いに Pro が 7 日間無料になります。\n$url',
    'Solve mahjong discard problems with me on Nanikiru Cam! '
        'Enter invite code $code and we both get 7 days of Pro.\n$url',
  );
  String get enterCode => tr('友だちの招待コード', 'A friend\'s invite code');
  String get applyCode => tr('使う', 'Apply');
  String get applying => tr('確認しています', 'Checking');
  String appliedUntil(String date) => tr(
    '招待コードを使いました。Pro が $date まで有効です。',
    'Code applied. You have Pro until $date.',
  );
  String get alreadyAppliedLocal => tr(
    '招待コードは使用済みです（1 人 1 回）。',
    'You have already used an invite code (one per person).',
  );

  /// 招待コードを使えなかった理由（`app/functions/API.md` 1.4）。
  String referralFailure(ReferralFailure failure) => switch (failure) {
    ReferralFailure.invalidCode => tr(
      'コードが正しくありません。8 文字のコードを確認してください。',
      'That code is not valid. Check the 8-character code.',
    ),
    ReferralFailure.alreadyApplied => tr(
      '招待コードは 1 人 1 回までです。すでに使用済みです。',
      'You have already used an invite code.',
    ),
    ReferralFailure.selfReferral => tr(
      'ご自身のコードは使えません。',
      'You can\'t use your own code.',
    ),
    ReferralFailure.noUser => tr(
      'アカウントの準備ができていません。少し待ってからもう一度お試しください。',
      'Your account is not ready yet. Please try again in a moment.',
    ),
    ReferralFailure.network => tr(
      '通信できませんでした。接続を確認してください。',
      'Could not connect. Check your connection.',
    ),
    ReferralFailure.unavailable => tr(
      'このビルドでは招待コードを使えません。',
      'Invite codes are not available in this build.',
    ),
    ReferralFailure.unknown => tr(
      '招待コードを使えませんでした。時間をおいてお試しください。',
      'Could not apply the code. Please try again later.',
    ),
  };

  // --- データ ---
  String get sectionData => tr('データ', 'Data');
  String get deleteData => tr('データを削除', 'Delete my data');
  String get deleteDataSub => tr(
    'サーバー上のデータと、この端末の履歴・設定をすべて消します。',
    'Erase your server data and everything stored on this device.',
  );

  /// サーバーなしの版: サーバーのデータはなく、この端末の中だけを消す。
  String get deleteDataSubLocal => tr(
    'この端末に保存されている履歴・設定・ストリークをすべて消します。',
    'Erase the history, settings and streak stored on this device.',
  );
  String get deleteConfirmTitle => tr('データを削除しますか？', 'Delete all data?');
  String get deleteConfirmBody => tr(
    '出題した問題は非表示になり、履歴・設定・ストリーク・招待コードがすべて消えます。'
        'この操作は取り消せません。\n\n'
        'Pro の購読はストアで管理されているため、このあとも課金は続きます。'
        '解約は「購読の管理・解約」から行ってください。',
    'Your published problems are hidden, and your history, settings, streak and invite code are erased. '
        'This cannot be undone.\n\n'
        'Your Pro subscription is managed by the store and keeps billing. '
        'Cancel it under "Manage or cancel subscription".',
  );
  String get deleteConfirmBodyLocal => tr(
    'この端末に保存されている履歴・設定・ストリークがすべて消えます。'
        'この操作は取り消せません。\n\n'
        'Pro の購読はストアで管理されているため、このあとも課金は続きます。'
        '解約は「購読の管理・解約」から行ってください。',
    'The history, settings and streak stored on this device are erased. '
        'This cannot be undone.\n\n'
        'Your Pro subscription is managed by the store and keeps billing. '
        'Cancel it under "Manage or cancel subscription".',
  );
  String get deleteConfirm => tr('削除する', 'Delete');
  String get deleting => tr('削除しています', 'Deleting');
  String get deleteDone => tr(
    'データを削除しました。アプリを初期状態に戻します。',
    'Your data was deleted. The app will reset.',
  );
  String get deleteFailedLocal =>
      tr('削除できませんでした。もう一度お試しください。', 'Could not delete. Please try again.');
  String get deleteFailed => tr(
    '削除できませんでした。通信状況を確認して、もう一度お試しください。',
    'Could not delete. Check your connection and try again.',
  );

  // --- このアプリについて ---
  String get sectionAbout => tr('このアプリについて', 'About');
  String get terms => tr('利用規約', 'Terms of Use');
  String get privacyPolicy => tr('プライバシーポリシー', 'Privacy Policy');
  String get tokushoho => tr('購入に関するご案内', 'Purchase information');
  String get sourceCode => tr('ソースコード', 'Source code');
  String get version => tr('バージョン', 'Version');
}

extension SettingsStringsContext on BuildContext {
  SettingsStrings get settingsStrings => SettingsStrings(lang);
}

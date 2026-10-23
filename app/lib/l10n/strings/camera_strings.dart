import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// 撮影画面（camera/）の文言。
class CameraStrings extends FeatureStrings {
  const CameraStrings(super.lang);

  String get title => tr('写真で解析', 'Analyze a photo');
  String get topGuide => tr(
    '13枚を枠に合わせ、ツモ牌は少し離して右に',
    'Fit 13 tiles in the frame; set the drawn tile apart on the right',
  );

  /// 点数計算（Pro）から開いたとき。
  String get scoreTitle => tr('点数計算（写真）', 'Score a win (photo)');
  String get scoreTopGuide => tr(
    '和了の14枚を枠に合わせ、和了牌は少し離して右に',
    'Fit the 14 winning tiles; set the winning tile apart on the right',
  );
  String get bottomGuide =>
      tr('画面に他の牌がなるべく入らないようにしてください', 'Keep other tiles out of the frame');
  String get light => tr('ライト', 'Light');
  String get manualInput => tr('手入力', 'Enter by hand');
  String get pickPhoto => tr('写真を選ぶ', 'Pick a photo');
  String get settings => tr('設定', 'Settings');
  String get shutter => tr('撮影', 'Capture');
  String get captureFailed => tr('撮影に失敗しました', 'Capture failed');
  String get pickFailed => tr('写真を読み込めませんでした', 'Could not load the photo');

  // --- 写真解析の無料枠（仕様 3.2・5 章） ------------------------------------

  String quotaRemaining(int n, int limit) =>
      tr('今日の写真解析 残り $n / $limit 回', '$n of $limit photo analyses left today');
  String get quotaUnlimited =>
      tr('Pro: 写真解析は無制限', 'Pro: unlimited photo analysis');
  String quotaExhaustedTitle(int limit) => tr(
    '今日の無料の写真解析（$limit 回）を使い切りました',
    'You have used today\'s $limit free photo analyses',
  );
  String get quotaExhaustedBody => tr(
    '動画広告を見ると今日はあと 3 回使えます。Pro なら回数の制限はありません。手入力はいつでも無料です。',
    'Watch a video for 3 more today, or go Pro for no limit. Entering by hand is always free.',
  );
  String get quotaWatchVideo => tr('動画を見て +3 回', 'Watch a video for +3');
  String get quotaRewardUsed =>
      tr('今日の動画での追加は使い切りました', 'No more video bonuses today');
  String get quotaVideoFailed =>
      tr('動画を最後まで見られませんでした', 'The video did not finish');
  String get quotaGoPro => tr('Pro で無制限にする', 'Go Pro for no limit');
  String get quotaManual => tr('手入力で続ける（無料）', 'Enter by hand (free)');

  /// 撮るだけモード（仕様 6.5「解析せず保存」）で保存したとき。
  String get quickCaptureSaved =>
      tr('保存しました。履歴から確認・解析できます', 'Saved. Check and analyze it from History');

  /// カメラのエラーコード（[CameraException.code]）に対する説明。
  String errorMessage(String code) => switch (code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' => tr(
      'カメラへのアクセスが許可されていません。端末の「設定」で本アプリのカメラを許可してから、再試行してください。',
      'Camera access is not allowed. Allow the camera for this app in Settings, then retry.',
    ),
    'CameraAccessRestricted' => tr(
      'カメラの使用が制限されています。スクリーンタイムや端末の管理設定をご確認ください。',
      'Camera use is restricted. Check Screen Time or device management settings.',
    ),
    'NoCameraAvailable' => tr(
      '端末で利用可能なカメラが見つかりませんでした。',
      'No camera is available on this device.',
    ),
    'NoBackCamera' => tr(
      '背面カメラが見つかりませんでした。端末設定をご確認ください。',
      'No rear camera was found. Check the device settings.',
    ),
    _ => tr(
      'カメラを起動できませんでした。他のアプリでカメラを使用している場合は終了して、再試行してください。',
      'Could not start the camera. Close other apps that use the camera and retry.',
    ),
  };
}

extension CameraStringsContext on BuildContext {
  CameraStrings get cameraStrings => CameraStrings(lang);
}

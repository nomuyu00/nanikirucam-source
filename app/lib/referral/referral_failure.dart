/// 紹介コードを使えなかった理由。
enum ReferralFailure {
  /// 形式が違う、または存在しないコード。
  invalidCode,

  /// すでに別のコードを使っている（1 人 1 回）。
  alreadyApplied,

  /// 自分のコード。
  selfReferral,

  /// アカウントの準備ができていない（起動直後など）。
  noUser,

  /// 通信できない。
  network,

  /// Firebase が無効（オフラインのビルドなど）。
  unavailable,

  unknown,
}

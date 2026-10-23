// 流用元: reference/agari_cam/lib/share/share_target.dart（2026-10-21 時点）
/// 共有シートで選ばれたアプリを、分析用の固定値に丸める。
/// iOS は activityType、Android はパッケージ名が届く。生の値は送らない。
String shareTargetBucket(String raw) {
  final value = raw.toLowerCase();
  if (value.isEmpty) return 'other';
  if (value.contains('tweetie') ||
      value.contains('twitter') ||
      value.startsWith('com.x.')) {
    return 'x';
  }
  if (value.contains('instagram')) return 'instagram';
  if (value.contains('naver.line') || value.contains('linecorp')) {
    return 'line';
  }
  if (value.contains('facebook') || value.contains('katana')) {
    return 'facebook';
  }
  if (value.contains('discord')) return 'discord';
  if (value.contains('savetocameraroll') || value.contains('gallery')) {
    return 'save';
  }
  if (value.contains('copytopasteboard') || value.contains('clipboard')) {
    return 'copy';
  }
  if (value.contains('activity.message') ||
      value.contains('messaging') ||
      value.contains('mms')) {
    return 'messages';
  }
  if (value.contains('activity.mail') || value.contains('android.gm')) {
    return 'mail';
  }
  return 'other';
}

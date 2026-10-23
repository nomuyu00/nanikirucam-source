import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 現在時刻の取得元。日付の切り替え・期限の判定を持つ処理はここを使い、
/// テストでは `clockProvider.overrideWithValue(() => DateTime(...))` で差し替える。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 'YYYY-MM-DD'（端末のローカル日付）。無料枠・ストリークの日付キーと同じ書式。
String localDateKey(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}

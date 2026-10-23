/// mpsz 表記（赤5は 0、例 '123m055p11z'）をラベルの並びにする。'-' は空。
List<String> parseMpsz(String s) {
  if (s == '-' || s.isEmpty) return const [];
  final out = <String>[];
  final digits = <String>[];
  for (final ch in s.split('')) {
    if ('mpsz'.contains(ch)) {
      for (final d in digits) {
        out.add('$d$ch');
      }
      digits.clear();
    } else {
      digits.add(ch);
    }
  }
  if (digits.isNotEmpty) throw FormatException('mpsz の末尾に色がない: $s');
  return out;
}

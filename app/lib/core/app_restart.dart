import 'package:flutter/widgets.dart';

/// 子のツリー（`ProviderScope` を含む）を作り直して、アプリの状態を最初に戻す。
/// データ削除のあとに、メモリ上の状態も初期化するために使う。
///
/// `main.dart` で `runApp(const AppRestart(child: ProviderScope(child: NanikiruCamApp())))` と包む。
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.child});

  final Widget child;

  /// 包まれていれば true。
  static bool isAvailable(BuildContext context) =>
      context.findAncestorStateOfType<_AppRestartState>() != null;

  /// 作り直す。包まれていなければ false。
  static bool restart(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppRestartState>();
    if (state == null) return false;
    state.restart();
    return true;
  }

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

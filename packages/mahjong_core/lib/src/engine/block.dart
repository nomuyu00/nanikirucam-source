import 'package:equatable/equatable.dart';

/// ブロック分解での牌の役割（設計書 4.7）。
///
/// - [meld]: 面子（順子・刻子。副露と暗槓も含む）
/// - [ryanmen] / [kanchan] / [penchan]: 搭子（23 / 24 / 12・89）
/// - [pair]: 雀頭以外の対子（刻子の候補）
/// - [head]: 雀頭（対子のうち 1 つ）
/// - [isolated]: 孤立牌（どのブロックにも入らない 1 枚）
enum BlockRole { meld, ryanmen, kanchan, penchan, pair, head, isolated }

/// ブロック分解の 1 ブロック（設計書 4.7）。作り方は `blocks.dart` の
/// `decomposeBlocks`。
class Block extends Equatable {
  /// ブロックを作る牌 id（昇順）。
  final List<int> tileIds;
  final BlockRole role;

  /// 宣言済みの面子（副露・暗槓）か。手牌から分けたブロックは false。
  final bool declared;

  Block({required List<int> tileIds, required this.role, this.declared = false})
    : tileIds = List.unmodifiable(tileIds);

  @override
  List<Object?> get props => [tileIds, role, declared];

  @override
  String toString() =>
      'Block(${role.name} $tileIds${declared ? ' 副露・暗槓' : ''})';
}

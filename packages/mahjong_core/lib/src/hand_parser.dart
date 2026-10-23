// 流用元: reference/agari_cam/lib/scoring/hand_parser.dart（2026-10-21 時点）
import 'dart:collection';

import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/tile_utils.dart';

class PatternGroup {
  final MeldType type;
  final List<int> tileIds;
  const PatternGroup(this.type, this.tileIds);

  bool get isPair => type == MeldType.pair;
}

class ParsedHandPattern {
  final List<PatternGroup> groups;
  final bool sevenPairs;
  final bool kokushi;
  final List<int>? kokushiTileIds;

  const ParsedHandPattern({
    required this.groups,
    this.sevenPairs = false,
    this.kokushi = false,
    this.kokushiTileIds,
  });

  MaterializedHand? materialize(List<String> labels, {List<bool>? openFlags}) {
    if (kokushi) {
      return _materializeKokushi(labels);
    }
    final buckets = <int, Queue<String>>{};
    for (final label in labels) {
      final id = tileIdFromLabel(label);
      if (id < 0) continue;
      buckets.putIfAbsent(id, () => Queue<String>()).add(label);
    }
    final melds = <Meld>[];
    final labelGroups = <List<String>>[];
    final groupTypes = <MeldType?>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final groupLabels = <String>[];
      final tiles = <Tile>[];
      for (final id in g.tileIds) {
        final bucket = buckets[id];
        if (bucket == null || bucket.isEmpty) {
          return null;
        }
        final lbl = bucket.removeFirst();
        groupLabels.add(lbl);
        tiles.add(tileFromLabel(lbl));
      }
      final open = (openFlags != null && i < openFlags.length)
          ? openFlags[i]
          : false;
      melds.add(Meld(type: g.type, tiles: tiles, open: open));
      labelGroups.add(groupLabels);
      groupTypes.add(g.type);
    }
    return MaterializedHand(
      melds: melds,
      labelGroups: labelGroups,
      groupTypes: groupTypes,
      sevenPairs: sevenPairs,
      kokushi: false,
      kokushiLabels: const [],
    );
  }

  MaterializedHand _materializeKokushi(List<String> labels) {
    final buckets = <int, Queue<String>>{};
    for (final label in labels) {
      final id = tileIdFromLabel(label);
      if (id < 0) continue;
      buckets.putIfAbsent(id, () => Queue<String>()).add(label);
    }
    final orderedIds = kokushiTileIds ?? const <int>[];
    final extracted = <String>[];
    final singles = <String>[];
    for (final id in orderedIds) {
      final bucket = buckets[id];
      if (bucket == null || bucket.isEmpty) {
        continue;
      }
      final lbl = bucket.removeFirst();
      extracted.add(lbl);
    }
    final counts = <int, List<String>>{};
    for (final lbl in extracted) {
      final id = tileIdFromLabel(lbl);
      counts.putIfAbsent(id, () => <String>[]).add(lbl);
    }
    final labelGroups = <List<String>>[];
    final groupTypes = <MeldType?>[];
    counts.forEach((id, list) {
      if (list.length >= 2) {
        labelGroups.add([list[0], list[1]]);
        groupTypes.add(MeldType.pair);
        if (list.length > 2) {
          singles.addAll(list.sublist(2));
        }
      } else {
        singles.addAll(list);
      }
    });
    singles.sort();
    for (final s in singles) {
      labelGroups.add([s]);
      groupTypes.add(null);
    }
    return MaterializedHand(
      melds: const [],
      labelGroups: labelGroups,
      groupTypes: groupTypes,
      sevenPairs: false,
      kokushi: true,
      kokushiLabels: extracted,
    );
  }
}

class MaterializedHand {
  final List<Meld> melds;
  final List<List<String>> labelGroups;
  final List<MeldType?> groupTypes;
  final bool sevenPairs;
  final bool kokushi;
  final List<String> kokushiLabels;

  const MaterializedHand({
    required this.melds,
    required this.labelGroups,
    required this.groupTypes,
    required this.sevenPairs,
    required this.kokushi,
    required this.kokushiLabels,
  });
}

class HandParser {
  List<ParsedHandPattern> parse(List<String> labels) {
    final counts = List<int>.filled(34, 0);
    for (final label in labels) {
      final id = tileIdFromLabel(label);
      if (id >= 0) counts[id] += 1;
    }
    final totalTiles = counts.fold<int>(0, (p, c) => p + c);
    final results = <ParsedHandPattern>[];
    final seen = <String>{};

    if (_isKokushi(counts, totalTiles)) {
      final ids = <int>[];
      for (var i = 0; i < counts.length; i++) {
        for (var k = 0; k < counts[i]; k++) {
          ids.add(i);
        }
      }
      results.add(
        ParsedHandPattern(groups: const [], kokushi: true, kokushiTileIds: ids),
      );
    }

    if (_isSevenPairs(counts, totalTiles)) {
      final groups = <PatternGroup>[];
      for (var i = 0; i < counts.length; i++) {
        final pairs = counts[i] ~/ 2;
        for (var p = 0; p < pairs; p++) {
          groups.add(PatternGroup(MeldType.pair, [i, i]));
        }
      }
      if (groups.length == 7) {
        results.add(ParsedHandPattern(groups: groups, sevenPairs: true));
      }
    }

    final standard = _parseStandardHands(List<int>.from(counts));
    for (final g in standard) {
      final key = _canonicalKey(g);
      if (seen.add(key)) {
        results.add(ParsedHandPattern(groups: g));
      }
    }

    return results;
  }

  List<List<PatternGroup>> _parseStandardHands(List<int> counts) {
    final results = <List<PatternGroup>>[];
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] < 2) continue;
      counts[i] -= 2;
      final path = <PatternGroup>[
        PatternGroup(MeldType.pair, [i, i]),
      ];
      _searchSets(counts, 4, path, results);
      counts[i] += 2;
    }
    return results;
  }

  void _searchSets(
    List<int> counts,
    int remainingSets,
    List<PatternGroup> path,
    List<List<PatternGroup>> results,
  ) {
    if (remainingSets == 0) {
      if (counts.every((c) => c == 0)) {
        results.add(List<PatternGroup>.from(path));
      }
      return;
    }
    final first = _firstNonZero(counts);
    if (first == -1) return;

    if (counts[first] >= 3) {
      counts[first] -= 3;
      path.add(PatternGroup(MeldType.koutsu, [first, first, first]));
      _searchSets(counts, remainingSets - 1, path, results);
      path.removeLast();
      counts[first] += 3;
    }

    if (counts[first] >= 4) {
      counts[first] -= 4;
      path.add(PatternGroup(MeldType.kantsu, [first, first, first, first]));
      _searchSets(counts, remainingSets - 1, path, results);
      path.removeLast();
      counts[first] += 4;
    }

    final pos = first % 9;
    if (first < 27 && pos <= 6) {
      final a = first;
      final b = first + 1;
      final c = first + 2;
      if (counts[b] > 0 && counts[c] > 0) {
        counts[a] -= 1;
        counts[b] -= 1;
        counts[c] -= 1;
        path.add(PatternGroup(MeldType.shuntsu, [a, b, c]));
        _searchSets(counts, remainingSets - 1, path, results);
        path.removeLast();
        counts[a] += 1;
        counts[b] += 1;
        counts[c] += 1;
      }
    }
  }

  int _firstNonZero(List<int> counts) {
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > 0) return i;
    }
    return -1;
  }

  String _canonicalKey(List<PatternGroup> groups) {
    final seq =
        groups.map((g) => '${g.type.index}:${g.tileIds.join(',')}').toList()
          ..sort();
    return seq.join('|');
  }

  bool _isSevenPairs(List<int> counts, int totalTiles) {
    if (totalTiles != 14) return false;
    var pairCount = 0;
    for (final c in counts) {
      if (c == 2) {
        pairCount += 1;
      } else if (c != 0) {
        return false;
      }
    }
    return pairCount == 7;
  }

  bool _isKokushi(List<int> counts, int totalTiles) {
    if (totalTiles != 14) return false;
    const terminals = {0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33};
    var unique = 0;
    var hasPair = false;
    for (var i = 0; i < counts.length; i++) {
      final c = counts[i];
      if (c == 0) continue;
      if (!terminals.contains(i)) return false;
      unique += 1;
      if (c >= 2) hasPair = true;
    }
    return unique == 13 && hasPair;
  }
}

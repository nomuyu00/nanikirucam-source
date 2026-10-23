import 'dart:math' as math;

import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/win_ease.dart';
import 'package:mahjong_core/src/engine/win_ease_table.g.dart';
import 'package:test/test.dart';

double _ease(
  int shanten,
  int ukeire,
  int? turn, [
  ShantenType type = ShantenType.standard,
]) => winEase(shanten: shanten, ukeireTotal: ukeire, turn: turn, type: type);

const _tables = <ShantenType, List<List<List<double>>>>{
  ShantenType.standard: kWinEaseTableStandard,
  ShantenType.sevenPairs: kWinEaseTableSevenPairs,
  ShantenType.kokushi: kWinEaseTableKokushi,
};

/// 他家なしの山は 123 - 巡目 枚から 1 枚ずつ減る。テンパイで受け入れを引き続けるだけの手計算。
double _naiveTenpai(int ukeire, int turn) {
  var miss = 1.0;
  for (var k = 0; k < 18 - turn; k++) {
    miss *= 1 - ukeire / (123 - turn - k);
  }
  return 1 - miss;
}

void main() {
  group('表の形（形ごと）', () {
    test('受け入れ区分の下限は 0 から昇順', () {
      expect(kWinEaseUkeireLowerBounds.first, 0);
      for (var i = 1; i < kWinEaseUkeireLowerBounds.length; i++) {
        expect(
          kWinEaseUkeireLowerBounds[i],
          greaterThan(kWinEaseUkeireLowerBounds[i - 1]),
        );
      }
    });

    for (final entry in _tables.entries) {
      final type = entry.key;
      final table = entry.value;

      test('$type: シャンテン 4 区分 × 受け入れ区分 × 巡目 17 で、値は 0..1', () {
        expect(table, hasLength(4));
        for (final rows in table) {
          expect(rows, hasLength(kWinEaseUkeireLowerBounds.length));
          for (final row in rows) {
            expect(row, hasLength(17));
            for (final v in row) {
              expect(v, inInclusiveRange(0.0, 1.0));
            }
          }
        }
      });

      test('$type: 単調性（受け入れが多いほど・巡目が早いほど・シャンテンが小さいほど高い）', () {
        for (var s = 0; s < 4; s++) {
          for (var b = 0; b < kWinEaseUkeireLowerBounds.length; b++) {
            for (var t = 0; t < 17; t++) {
              final v = table[s][b][t];
              if (b > 0) {
                expect(v, greaterThanOrEqualTo(table[s][b - 1][t]));
              }
              if (t > 0) {
                expect(v, lessThanOrEqualTo(table[s][b][t - 1]));
              }
              if (s > 0) {
                expect(v, lessThanOrEqualTo(table[s - 1][b][t]));
              }
            }
          }
        }
      });
    }
  });

  group('winEase の単調性', () {
    for (final type in ShantenType.values) {
      test('$type: 受け入れが 1 枚増えても下がらない', () {
        for (var s = 0; s <= 5; s++) {
          for (var t = 1; t <= 18; t++) {
            for (var u = 1; u <= 130; u++) {
              expect(
                _ease(s, u, t, type),
                greaterThanOrEqualTo(_ease(s, u - 1, t, type)),
              );
            }
          }
        }
      });

      test('$type: 巡目が進んでも上がらない', () {
        for (var s = 0; s <= 5; s++) {
          for (var u = 0; u <= 130; u++) {
            for (var t = 2; t <= 20; t++) {
              expect(
                _ease(s, u, t, type),
                lessThanOrEqualTo(_ease(s, u, t - 1, type)),
              );
            }
          }
        }
      });

      test('$type: シャンテンが大きくなっても上がらない', () {
        for (var s = 1; s <= 6; s++) {
          for (var t = 1; t <= 18; t++) {
            for (var u = 0; u <= 130; u++) {
              expect(
                _ease(s, u, t, type),
                lessThanOrEqualTo(_ease(s - 1, u, t, type)),
              );
            }
          }
        }
      });
    }
  });

  group('境界', () {
    test('type を省くと一般形の表', () {
      for (final s in [0, 1, 2, 3]) {
        for (final u in [0, 4, 9, 24, 60]) {
          for (final t in [1, 6, 12, 17]) {
            expect(
              winEase(shanten: s, ukeireTotal: u, turn: t),
              _ease(s, u, t, ShantenType.standard),
            );
          }
        }
      }
      expect(
        winEase(shanten: 1, ukeireTotal: 9),
        _ease(1, 9, 6, ShantenType.standard),
      );
    });

    test('形によって値が違う（同じシャンテン・受け入れ・巡目でも）', () {
      expect(
        _ease(1, 9, 6, ShantenType.sevenPairs),
        isNot(_ease(1, 9, 6, ShantenType.standard)),
      );
      expect(
        _ease(2, 12, 6, ShantenType.kokushi),
        isNot(_ease(2, 12, 6, ShantenType.standard)),
      );
    });

    for (final type in ShantenType.values) {
      test('$type: 和了済み（シャンテン -1）は巡目・受け入れによらず 1.0', () {
        expect(_ease(-1, 0, null, type), 1.0);
        expect(_ease(-1, 10, 6, type), 1.0);
        expect(_ease(-1, 10, 18, type), 1.0);
        expect(_ease(-1, 10, 30, type), 1.0);
      });

      test('$type: 巡目が null のときは 6 巡目として扱う', () {
        for (var s = 0; s <= 4; s++) {
          for (final u in [0, 3, 8, 9, 15, 24, 60, 200]) {
            expect(_ease(s, u, null, type), _ease(s, u, 6, type));
          }
        }
      });

      test('$type: 18 巡目以降は残りツモが無いので 0.0', () {
        for (var s = 0; s <= 4; s++) {
          expect(_ease(s, 8, 18, type), 0.0);
          expect(_ease(s, 8, 19, type), 0.0);
          expect(_ease(s, 100, 99, type), 0.0);
        }
      });

      test('$type: 0 以下の巡目は 1 巡目と同じ', () {
        expect(_ease(1, 20, 0, type), _ease(1, 20, 1, type));
        expect(_ease(1, 20, -3, type), _ease(1, 20, 1, type));
      });

      test('$type: シャンテン 3 以上は同じ行、受け入れが範囲外なら端の区分', () {
        expect(_ease(4, 40, 6, type), _ease(3, 40, 6, type));
        expect(_ease(7, 40, 6, type), _ease(3, 40, 6, type));
        expect(_ease(2, -5, 6, type), _ease(2, 0, 6, type));
        final last = kWinEaseUkeireLowerBounds.last;
        expect(_ease(2, last + 500, 6, type), _ease(2, last, 6, type));
      });

      test('$type: 区分の境界で値が切り替わる', () {
        final table = _tables[type]!;
        for (var b = 1; b < kWinEaseUkeireLowerBounds.length; b++) {
          final lower = kWinEaseUkeireLowerBounds[b];
          for (var s = 0; s < 4; s++) {
            expect(_ease(s, lower, 6, type), table[s][b][5]);
            expect(_ease(s, lower - 1, 6, type), table[s][b - 1][5]);
          }
        }
      });
    }

    test('17 巡目は残り 1 ツモなので 0 より大きく、低い', () {
      expect(_ease(0, 8, 17), greaterThan(0.0));
      expect(_ease(0, 8, 17), lessThan(0.2));
    });
  });

  group('構造上の 0', () {
    for (final type in ShantenType.values) {
      test('$type: テンパイで受け入れ 0 枚（待ちが全部見えている）は和了できない', () {
        for (var t = 1; t <= 18; t++) {
          expect(_ease(0, 0, t, type), 0.0);
        }
      });

      test('$type: 残りツモがシャンテン数 + 1 回に満たなければ 0（17 巡目の一向聴など）', () {
        // 表の最後の行は 3 向聴以上をまとめるので、確かめられるのは 3 向聴まで。
        for (var s = 1; s <= 3; s++) {
          // 打牌後の巡目 t の残りツモは 18 - t 回。和了にはシャンテン数 + 1 回以上のツモが要る。
          for (var t = 18 - s; t <= 18; t++) {
            for (final u in [1, 8, 30, 90]) {
              expect(
                _ease(s, u, t, type),
                0.0,
                reason: '$s 向聴 受け入れ $u 枚 $t 巡目',
              );
            }
          }
        }
      });
    }

    test('残りツモが足りていれば 0 より大きい（一般形）', () {
      expect(_ease(0, 8, 17), greaterThan(0.0));
      expect(_ease(1, 30, 16), greaterThan(0.0));
      expect(_ease(2, 60, 15), greaterThan(0.0));
    });
  });

  group('代表値の妥当性（一般形、シミュレーション）', () {
    test('6 巡目の両面テンパイ相当（受け入れ 8 枚）は 0.4〜0.8、手計算（約 0.59）に近い', () {
      final v = _ease(0, 8, 6);
      expect(v, inInclusiveRange(0.4, 0.8));
      expect(v, closeTo(_naiveTenpai(8, 6), 0.05));
      // 残り山を約 100 枚とみなす手計算（1 - (1 - 8/100)^12 ≈ 0.63）より少し低い。
      expect(v, lessThan(1 - math.pow(1 - 8 / 100, 12)));
    });

    test('テンパイ（受け入れ 8 枚以下）は、待ちを引き続ける手計算より下がらない', () {
      // 待ちの改良（嵌張→両面など）の分だけ手計算より高くなるので、下限として使う。
      // 1〜2 巡目のテンパイは標本が少ない（セルあたり数百〜数千件）ので 3 巡目から。
      for (var u = 1; u <= 8; u++) {
        for (var t = 3; t <= 16; t++) {
          expect(
            _ease(0, u, t),
            greaterThanOrEqualTo(_naiveTenpai(u, t) - 0.03),
            reason: '受け入れ $u 枚 $t 巡目',
          );
        }
      }
    });

    test('受け入れ 6・8・10 枚のテンパイは 3〜15 巡目で手計算の ±0.08 以内', () {
      for (final u in [6, 8, 10]) {
        for (var t = 3; t <= 15; t++) {
          expect(
            _ease(0, u, t),
            closeTo(_naiveTenpai(u, t), 0.08),
            reason: '受け入れ $u 枚 $t 巡目',
          );
        }
      }
    });

    test('テンパイは 1 巡目なら高く、終盤は低い', () {
      expect(_ease(0, 8, 1), inInclusiveRange(0.55, 0.8));
      expect(_ease(0, 8, 12), inInclusiveRange(0.25, 0.5));
      expect(_ease(0, 8, 17), lessThan(0.12));
    });

    test('6 巡目: 一向聴・二向聴・三向聴は順に大きく下がる', () {
      final one = _ease(1, 24, 6);
      final two = _ease(2, 30, 6);
      final three = _ease(3, 40, 6);
      expect(one, inInclusiveRange(0.25, 0.45));
      expect(two, inInclusiveRange(0.08, 0.25));
      expect(three, inInclusiveRange(0.02, 0.15));
      expect(_ease(0, 4, 6), greaterThan(one));
      expect(one, greaterThan(two));
      expect(two, greaterThan(three));
    });

    test('段階（高・中・低）が麻雀の感覚に合う', () {
      WinEaseLevel level(int s, int u, int t) => winEaseLevel(_ease(s, u, t));
      expect(level(0, 8, 6), WinEaseLevel.high); // 6 巡目の両面テンパイ
      expect(level(0, 4, 12), WinEaseLevel.medium); // 12 巡目の愚形テンパイ
      expect(level(1, 24, 6), WinEaseLevel.medium); // 6 巡目の好形一向聴
      expect(level(2, 30, 12), WinEaseLevel.low); // 12 巡目の二向聴
      expect(level(0, 8, 17), WinEaseLevel.low); // 17 巡目はテンパイでも低い
      expect(level(3, 40, 6), WinEaseLevel.low);
    });
  });

  group('代表値の妥当性（七対子）', () {
    const type = ShantenType.sevenPairs;

    test('6 巡目の一向聴・受け入れ 9 枚（3 種の浮き牌）は 10% 前後、二向聴・15 枚は 5% 前後', () {
      expect(_ease(1, 9, 6, type), closeTo(0.10, 0.03));
      expect(_ease(2, 15, 6, type), closeTo(0.05, 0.025));
    });

    test('テンパイの単騎待ち（受け入れ 3 枚）は、待ちを引き続ける手計算に近い', () {
      // 七対子のテンパイは待ちを替える余地が小さいので、改良の分が乗らない。
      for (var t = 3; t <= 15; t++) {
        expect(
          _ease(0, 3, t, type),
          closeTo(_naiveTenpai(3, t), 0.04),
          reason: '$t 巡目',
        );
      }
    });

    test('受け入れが 1 枚少ないとき（見えている牌がある）は受け入れに比例して下がる', () {
      for (var t = 1; t <= 12; t++) {
        final full = _ease(1, 9, t, type);
        final less = _ease(1, 8, t, type);
        expect(less, lessThan(full));
        expect(less, greaterThan(full * 0.8));
      }
    });

    test('同じシャンテン・受け入れ・巡目なら一般形より低い（1 向聴 9 枚、2 向聴 15 枚）', () {
      for (var t = 1; t <= 9; t++) {
        expect(
          _ease(1, 9, t, type),
          lessThan(_ease(1, 9, t) - 0.02),
          reason: '1 向聴 9 枚 $t 巡目',
        );
        expect(
          _ease(2, 15, t, type),
          lessThan(_ease(2, 15, t) - 0.015),
          reason: '2 向聴 15 枚 $t 巡目',
        );
      }
      // 10 巡目以降は、どちらも 1% 前後以下で差が丸めの範囲に入るので比べない。
      expect(_ease(1, 9, 10, type), lessThanOrEqualTo(_ease(1, 9, 10)));
    });

    test('段階: 6 巡目の七対子一向聴は低、テンパイは中', () {
      expect(winEaseLevel(_ease(1, 9, 6, type)), WinEaseLevel.low);
      expect(winEaseLevel(_ease(0, 3, 6, type)), WinEaseLevel.medium);
    });
  });

  group('テンパイは形によらず、待ちを引き続ける手計算を下回らない', () {
    for (final type in ShantenType.values) {
      test('$type', () {
        // 表は待ちを引き続ける手計算（下限）に引き上げてある。区分の下限の枚数で数え、
        // 丸めと単調性の補正の分だけ許す。
        for (var u = 1; u <= 40; u++) {
          final lower = kWinEaseUkeireLowerBounds.lastWhere((b) => b <= u);
          for (var t = 1; t <= 16; t++) {
            expect(
              _ease(0, u, t, type),
              greaterThanOrEqualTo(_naiveTenpai(lower, t) - 0.01),
              reason: '受け入れ $u 枚 $t 巡目',
            );
          }
        }
      });
    }
  });

  group('代表値の妥当性（国士）', () {
    const type = ShantenType.kokushi;

    test('テンパイ: 単騎（受け入れ 4 枚）は 3〜5 割、十三面待ち（39 枚）はほぼ確実に近い', () {
      expect(_ease(0, 4, 6, type), inInclusiveRange(0.3, 0.5));
      expect(_ease(0, 39, 6, type), greaterThan(0.9));
      expect(_ease(0, 39, 12, type), greaterThan(0.75));
    });

    test('6 巡目の国士は、同じシャンテン・受け入れの一般形より低い（二向聴以上）', () {
      expect(_ease(2, 12, 6, type), lessThan(_ease(2, 12, 6)));
      expect(_ease(3, 20, 6, type), lessThan(_ease(3, 20, 6)));
    });

    test('国士の三向聴は 12 巡目にはほぼ望めない', () {
      expect(_ease(3, 20, 12, type), lessThan(0.02));
    });
  });

  group('段階', () {
    test('高 0.5 以上、低 0.2 未満、その間が中', () {
      expect(winEaseLevel(1.0), WinEaseLevel.high);
      expect(winEaseLevel(0.5), WinEaseLevel.high);
      expect(winEaseLevel(0.4999), WinEaseLevel.medium);
      expect(winEaseLevel(0.2), WinEaseLevel.medium);
      expect(winEaseLevel(0.1999), WinEaseLevel.low);
      expect(winEaseLevel(0.0), WinEaseLevel.low);
    });
  });
}

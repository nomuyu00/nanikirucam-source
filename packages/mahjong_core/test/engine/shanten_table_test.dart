import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';

// 既知形のシャンテン数表。各行の期待値は手で求め、Python の mahjong==2.0.0
// （Shanten.calculate_shanten_for_regular_hand / _for_chiitoitsu_hand /
// _for_kokushi_hand / calculate_shanten）でも同じ値になることを確かめた。
//
// 列: カテゴリ 手牌 副露 一般形 七対子 国士 総合 型
// - 副露は 'chi:1m'（1m から始まる順子）/'pon:5z'/'kan:1p'（明槓）/'ankan:9s' のカンマ区切り。無ければ '-'
// - 副露ありの行は七対子・国士を対象外（'-'）とする
// - 型は総合の値を出した形（同値なら standard → sevenPairs → kokushi）
// - 「4枚目を考えない式なら…」の注記がある行は、8 − 2m − t − h をそのまま使うと
//   一般形の値が変わる行（手の中に 4 枚ある牌の 5 枚目を待つ形はテンパイと数えない）
const _table = '''
和了形       123m456p789s11122z -                           -1  4  8 -1 standard
和了形       111222333m44455p   -                           -1  3 11 -1 standard
和了形       123456789m11122z   -                           -1  4  8 -1 standard
和了形       11123455678999m    -                           -1  3 10 -1 standard
和了形       22334455667788p    -                           -1 -1 13 -1 standard
和了形       11223344556677s    -                           -1 -1 11 -1 standard
和了形       234m234p23455588s  -                           -1  4 13 -1 standard
和了形       111999m111999p11s  -                           -1  3  7 -1 standard
和了形       11122233344455m    -                           -1  3 11 -1 standard
和了形       11112345678999m    -                           -1  4 10 -1 standard
和了形       345m345p345s66777z -                           -1  4 10 -1 standard
和了形       55566677788899m    -                           -1  3 11 -1 standard
和了形       234567m234567p55s  -                           -1  5 13 -1 standard
和了形       11223344m567p999s  -                           -1  1 10 -1 standard
和了形       22333444m555666z   -                           -1  3 10 -1 standard
和了形       123456789p12344s   -                           -1  5 10 -1 standard
和了形       11112233m456p789s  -                           -1  3 10 -1 standard
和了形       12345678999m111z   -                           -1  4  9 -1 standard
和了形       12399m345p567s777z -                           -1  4  9 -1 standard
和了形       22234m456p666789s  -                           -1  4 12 -1 standard
和了形       11122233344456m    -                           -1  3 11 -1 standard
和了形       11112222333444s    -                           -1  5 11 -1 standard
和了形       123m123p123s11177z -                           -1  4  7 -1 standard
和了形       78999m789p789s111z -                           -1  4  8 -1 standard
和了形       123m555p888s22233z -                           -1  2  9 -1 standard
テンパイ両面 23m456p789s11122z  -                            0  4  9  0 standard
テンパイ両面 456m78p234s55666z  -                            0  4 10  0 standard
テンパイ両面 123m345p3467899s   -                            0  5 10  0 standard
テンパイ両面 567m345p1123s777z  -                            0  4 10  0 standard
テンパイ両面 34m345p345s22555z  -                            0  4 10  0 standard
テンパイ両面 678m67p234999s11z  -                            0  4 10  0 standard
テンパイ両面 23345m345p345s11z  -                            0  4 11  0 standard
テンパイ嵌張 13m456p789s11122z  -                            0  4  8  0 standard
テンパイ嵌張 123m57p23456799s   -                            0  5 10  0 standard
テンパイ嵌張 24m111456p789s33z  -                            0  4  9  0 standard
テンパイ嵌張 123m456p79s22333z  -                            0  4  8  0 standard
テンパイ嵌張 11135m456p789s11z  -                            0  4  9  0 standard
テンパイ嵌張 13456m456p456s22z  -                            0  5 10  0 standard
テンパイ辺張 12m456p789s11122z  -                            0  4  8  0 standard
テンパイ辺張 123m89p456s11777z  -                            0  4  8  0 standard
テンパイ辺張 456m456p12s55666z  -                            0  4  9  0 standard
テンパイ辺張 789m123p1118999s   -                            0  4  8  0 standard
テンパイ双碰 11m456p789s11122z  -                            0  3  8  0 standard
テンパイ双碰 55m88p123456789s   -                            0  4 11  0 standard
テンパイ双碰 99m123456789p11z   -                            0  4  8  0 standard
テンパイ双碰 33m44p234567888s   -                            0  3 13  0 standard
テンパイ双碰 123m123p123s4455z  -                            0  4  7  0 standard
テンパイ単騎 1m456p789s111222z  -                            0  4  8  0 standard
テンパイ単騎 123456789m1112z    -                            0  5  8  0 standard
テンパイ単騎 123m456p111789s5z  -                            0  5  8  0 standard
テンパイ単騎 111m999p111s5556z  -                            0  4  7  0 standard
テンパイ単騎 567m567p567s5557z  -                            0  5 10  0 standard
テンパイ多面 1234m456p789s111z  -                            0  5  9  0 standard
テンパイ多面 34567m456p789s11z  -                            0  5 10  0 standard
テンパイ多面 1112345678999m     -                            0  4 10  0 standard
テンパイ多面 1112345678999p     -                            0  4 10  0 standard
テンパイ多面 2223456m456p789s   -                            0  5 12  0 standard
テンパイ多面 3334555m456p999s   -                            0  3 11  0 standard
テンパイ多面 1113m456p789s111z  -                            0  4  9  0 standard
テンパイ多面 23344m456p789s11z  -                            0  3 10  0 standard
テンパイ多面 12345m456p789s11z  -                            0  5  9  0 standard
テンパイ多面 11122m456p789s11z  -                            0  3  9  0 standard
テンパイ多面 1122334455667m     -                            0  0 11  0 standard
テンパイ多面 2345666777888m     -                            0  3 13  0 standard
清一色       2233445566778m     -                            0  0 13  0 standard
清一色       1223334445556m     -                            0  3 12  0 standard
清一色       1112223334445m     -                            0  4 11  0 standard
清一色       1234445556667m     -                            0  3 12  0 standard
清一色       3344556677889s     -                            0  0 12  0 standard
清一色       1122335577889m     -                            0  0 10  0 standard
清一色       1112233445566p     -                            0  1 11  0 standard
清一色       2223334445678s     -                            0  3 13  0 standard
清一色       1133557799m135p    -                            3  1  9  1 sevenPairs
清一色       11224455778899m    -                            1 -1 10 -1 sevenPairs
清一色       1123456789999m     -                            0  4 10  0 standard
清一色       12345678m123456p   -                            0  6 11  0 standard
七対子       1133557799m24p9s   -                            3  1  9  1 sevenPairs
一向聴       123m456p78s11125z  -                            1  5  8  1 standard
一向聴       23m56p789s111225z  -                            1  4  8  1 standard
一向聴       2345m567p3399s11z  -                            1  3 10  1 standard
一向聴       13m57p23456799s1z  -                            1  5  9  1 standard
一向聴       234m567p344599s1z  -                            1  4 10  1 standard
一向聴       12389m456p78s113z  -                            1  5  8  1 standard
一向聴       11234m456p789s15z  -                            1  5  8  1 standard
一向聴       24m68p3455679s11z  -                            1  4 10  1 standard
一向聴       123m123p12s44556z  -                            1  4  6  1 standard
一向聴       1235m35p456s1122z  -                            1  4  9  1 standard
一向聴       11456m22789p33s1z  -                            1  3  9  1 standard
一向聴       3455m3456p678s11z  -                            1  4 11  1 standard
一向聴       123456m1278p999s   -                            1  5  9  1 standard
一向聴       112m345p67899s55z  -                            1  3  9  1 standard
一向聴       345m345p3467s1155z -                            1  4 10  1 standard
14枚         1123m456p4568s777z -                            0  4 10  0 standard
一向聴       234m2399p4556799s  -                            1  3 10  1 standard
一向聴       13456m456p456s25z  -                            1  6 10  1 standard
一向聴       2469m567p566778s   -                            1  4 12  1 standard
二向聴       1245m3378p66789s   -                            2  4 11  2 standard
二向聴       123m123p123s4567z  -                            2  6  6  2 standard
二向聴       13456m46p79s1122z  -                            2  4  8  2 standard
二向聴       123m46p579s11556z  -                            2  4  7  2 standard
二向聴       1379m2468p123s55z  -                            2  5  8  2 standard
二向聴       24m68p13567s1155z  -                            2  4  9  2 standard
二向聴       1245m78p11456s17z  -                            2  5  8  2 standard
四向聴       135m246p345s1256z  -                            4  6  8  4 standard
二向聴       123m456p1357s123z  -                            2  6  8  2 standard
二向聴       19m15679p566778s   -                            2  4  9  2 standard
三向聴       1357m2468p135s11z  -                            3  5  9  3 standard
三向聴       1256m3478p569s11z  -                            3  5  9  3 standard
三向聴       123m4679p1358s25z  -                            3  6  8  3 standard
三向聴       13m46p12379s1234z  -                            3  6  6  3 standard
三向聴       1234m5678p99s123z  -                            3  5  7  3 standard
三向聴       147m456p789s1123z  -                            3  5  7  3 standard
四向聴       159m24p12368s567z  -                            4  6  7  4 standard
四向聴       12m45p78s1123456z  -                            4  5  5  4 standard
四向聴       1357m2468p13579s   -                            4  6 10  4 standard
四向聴       1256m3478p5689s1z  -                            4  6 10  4 standard
四向聴       13m46p79s1234567z  -                            5  6  4  4 kokushi
五向聴以上   13m47p258s1234567z -                            7  6  5  5 kokushi
五向聴以上   1147m258p369s123z  -                            7  5  7  5 sevenPairs
五向聴以上   147m258p369s1234z  -                            8  6  7  6 sevenPairs
五向聴以上   258m258p258s1234z  -                            8  6  9  6 sevenPairs
五向聴以上   1469m258p1369s15z  -                            6  6  7  6 standard
五向聴以上   147m147p147s1234z  -                            8  6  6  6 sevenPairs
五向聴以上   1478m258p369s123z  -                            7  6  8  6 sevenPairs
七対子       1155m2288p3366s77z -                            3 -1 10 -1 sevenPairs
七対子       1199m1199p1199s11z -                            3 -1  5 -1 sevenPairs
七対子       1155m2288p3366s7z  -                            3  0 10  0 sevenPairs
七対子       1155m2288p3367s7z  -                            3  1 10  1 sevenPairs
七対子       1122m3344p5566s7z  -                            3  0 10  0 sevenPairs
七対子       1111m2288p3366s77z -                            2  1 10  1 sevenPairs
七対子       1155m2288p3678s7z  -                            2  2 10  2 standard
七対子       111m2288p3366s77z  -                            2  1 10  1 sevenPairs
七対子       1155m2288p3366s67z -                            3  0  9  0 sevenPairs
七対子       2233445566778p     -                            0  0 13  0 standard
七対子       1133557799m2468p   -                            3  1 10  1 sevenPairs
七対子       11223344m5555p6z   -                            1  2 10  1 standard
国士         1199m19p19s123456z -                            6  4  0  0 kokushi
七対子       1122334455669m     -                            0  0 10  0 standard
七対子       1188m2299p3377s56z -                            3  0  8  0 sevenPairs
七対子       113355m224466p7z   -                            3  0 10  0 sevenPairs
国士         119m19p19s1234567z -                            7  5 -1 -1 kokushi
国士         19m19p19s12345677z -                            7  5 -1 -1 kokushi
国士         19m19p199s1234567z -                            7  5 -1 -1 kokushi
国士         19m19p19s1234567z  -                            8  6  0  0 kokushi
国士         119m19p19s123456z  -                            7  5  0  0 kokushi
国士         1159m19p19s12345z  -                            7  5  1  1 kokushi
国士         1259m159p19s1234z  -                            7  6  3  3 kokushi
国士         159m159p159s1234z  -                            8  6  3  3 kokushi
国士         159m19p19s1234567z -                            8  6  0  0 kokushi
国士         11999m1p9s123455z  -                            4  3  3  3 sevenPairs
国士         11119m19p19s12345z -                            6  5  1  1 kokushi
国士         19m19p19s1123456z  -                            7  5  0  0 kokushi
国士         1m19p19s12345677z  -                            7  5  0  0 kokushi
国士         19m19p19s1234566z  -                            7  5  0  0 kokushi
国士         15m159p19s1234567z -                            8  6  1  1 kokushi
副露あり     23m456p789s11z     pon:7z                       0  -  -  0 standard
副露あり     23m456p78s115z     pon:7z                       1  -  -  1 standard
副露あり     234m456p789s11z    chi:1m                      -1  -  - -1 standard
副露あり     234m456p78s115z    pon:6z                       0  -  -  0 standard
副露あり     23m456p11z         pon:5z,chi:7s                0  -  -  0 standard
副露あり     25m456p11z         pon:5z,chi:7s                1  -  -  1 standard
副露あり     234m456p11z        pon:5z,chi:7s               -1  -  - -1 standard
副露あり     234m45p116z        pon:5z,chi:7s                0  -  -  0 standard
副露あり     1234m              pon:5z,chi:7s,pon:1p         0  -  -  0 standard
副露あり     11m23p             pon:5z,chi:7s,pon:1p         0  -  -  0 standard
副露あり     15m9p1z            pon:5z,chi:7s,pon:1p         2  -  -  2 standard
副露あり     11m234p            pon:5z,chi:7s,pon:1p        -1  -  - -1 standard
副露あり     13m5p11z           pon:5z,chi:7s,pon:1p         0  -  -  0 standard
副露あり     5z                 pon:5m,chi:7s,pon:1p,chi:2m  0  -  -  0 standard
副露あり     55z                pon:5m,chi:7s,pon:1p,chi:2m -1  -  - -1 standard
副露あり     56z                pon:5m,chi:7s,pon:1p,chi:2m  0  -  -  0 standard
副露あり     1m                 pon:1m,chi:7s,pon:1p,chi:2p  0  -  -  0 standard
副露あり     23m456p789s11z     kan:7z                       0  -  -  0 standard
副露あり     23m456p11z         ankan:1s,pon:5z              0  -  -  0 standard
副露あり     1379m2468p55z      pon:7z                       2  -  -  2 standard
副露あり     12m15z             chi:3m,chi:4p,pon:9s         1  -  -  1 standard
副露あり     11m22p             chi:3m,chi:4p,pon:9s         0  -  -  0 standard
副露あり     13579m             chi:3s,pon:9s,pon:1z         1  -  -  1 standard
副露あり     111999m88p         chi:3s,pon:9s               -1  -  - -1 standard
副露あり     1199m88p5z         chi:3s,pon:9s                1  -  -  1 standard
副露あり     345m66p            chi:1s,pon:7z,kan:2p        -1  -  - -1 standard
副露あり     345m6p             chi:1s,pon:7z,kan:2p         0  -  -  0 standard
副露あり     35m67p             chi:1s,pon:7z,kan:2p         1  -  -  1 standard
副露あり     1112m              ankan:5z,ankan:6z,ankan:7z   0  -  -  0 standard
副露あり     1111m              pon:5z,chi:1p,chi:1s         1  -  -  1 standard  # 4枚目を考えない式なら一般形 0
副露あり     11112m             pon:5z,chi:1p,chi:1s         0  -  -  0 standard
副露あり     1111m2345p         pon:5z,chi:1s                0  -  -  0 standard
同種4枚      1111m234567789p    -                            1  4 10  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      1111m234567789p1z  -                            0  4  9  0 standard
同種4枚      234567789p1111z    -                            1  4 10  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      234567p11112222z   -                            1  4 10  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      1111m2222p3333s5z  -                            2  6 10  2 standard
同種4枚      1111222233334m     -                            0  6 11  0 standard
同種4枚      11112222333344m    -                           -1  5 11 -1 standard
同種4枚      2222m345p678999s1z -                            0  4 10  0 standard
同種4枚      2222m345p678999s   -                            1  4 11  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      1111m234p678999s   -                            1  4 10  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      11112m456p789s111z -                            0  4  9  0 standard
同種4枚      11112m456p789s11z  -                            0  4  9  0 standard
同種4枚      11113m456p789s11z  -                            0  4  9  0 standard
同種4枚      1111m456p789s115z  -                            1  4  8  1 standard
同種4枚      1111m5555p9999s1z  -                            2  6  9  2 standard
同種4枚      1111m5555p9999s77z -                            1  5  9  1 standard
同種4枚      5555m123456789p    -                            1  5 11  1 standard  # 4枚目を考えない式なら一般形 0
同種4枚      4445555m123789p    -                            0  4 11  0 standard
同種4枚      1111234m567789p    -                            0  4 10  0 standard
同種4枚      9999m789p789s1122z -                            0  3  7  0 standard
同種4枚      1111m222233334p    -                            1  6 11  1 standard  # 4枚目を考えない式なら一般形 0
字牌だけ     11122233344455z    -                           -1  3  7 -1 standard
字牌だけ     11122233355577z    -                           -1  3  7 -1 standard
字牌だけ     1112223334445z     -                            0  4  7  0 standard
字牌だけ     1122334455667z     -                            3  0  5  0 sevenPairs
字牌だけ     11223344556677z    -                            3 -1  5 -1 sevenPairs
字牌だけ     1111222233334z     -                            3  6  8  3 standard  # 4枚目を考えない式なら一般形 2
字牌だけ     1111222233344z     -                            2  5  8  2 standard  # 4枚目を考えない式なら一般形 1
字牌だけ     1112223334567z     -                            2  3  5  2 standard
字牌だけ     1112223345667z     -                            2  2  5  2 standard
字牌だけ     11122233344456z    -                            0  3  6  0 standard
字牌だけ     1122334455677z     -                            3  0  5  0 sevenPairs
字牌だけ     1112223344556z     -                            1  2  6  1 standard
14枚         123m456p78s111256z -                            1  5  7  1 standard
14枚         1234567m1234567p   -                            0  6 11  0 standard
14枚         123m456p78s111226z -                            0  4  8  0 standard
14枚         13579m2468p13579s  -                            4  6  9  4 standard
14枚         112233m445566p78s  -                            0  0 11  0 standard
14枚         1112345678999m1z   -                            0  4  9  0 standard
14枚         1357m2468p789s115z -                            2  5  8  2 standard
14枚         123m456p789s1234z  -                            2  6  7  2 standard
14枚         147m258p369s12345z -                            8  6  6  6 sevenPairs
14枚         1122m3344p5566s77z -                            3 -1 10 -1 sevenPairs
四向聴       124578m124578p1z   -                            4  6 10  4 standard
''';

class _Row {
  final String category;
  final String hand;
  final String melds;
  final int standard;
  final int? sevenPairs;
  final int? kokushi;
  final int total;
  final ShantenType type;
  _Row(
    this.category,
    this.hand,
    this.melds,
    this.standard,
    this.sevenPairs,
    this.kokushi,
    this.total,
    this.type,
  );
}

List<_Row> _parseTable() {
  final rows = <_Row>[];
  for (final raw in _table.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final f = line.split(RegExp(r'\s+'));
    if (f.length != 8) throw FormatException('表の行が 8 列でない: $raw');
    int? opt(String v) => v == '-' ? null : int.parse(v);
    rows.add(
      _Row(
        f[0],
        f[1],
        f[2] == '-' ? '' : f[2],
        int.parse(f[3]),
        opt(f[4]),
        opt(f[5]),
        int.parse(f[6]),
        ShantenType.values.byName(f[7]),
      ),
    );
  }
  return rows;
}

void main() {
  final rows = _parseTable();

  test('表は 200 件以上で、どの手も 13/14 枚', () {
    expect(rows.length, greaterThanOrEqualTo(200));
    for (final row in rows) {
      final hand = handFromNotation(row.hand, melds: row.melds);
      expect(hand.tileCount, anyOf(13, 14), reason: row.hand);
      expect(row.melds.isEmpty, row.sevenPairs != null, reason: row.hand);
    }
  });

  for (final row in rows) {
    final label =
        '[${row.category}] ${row.hand}'
        '${row.melds.isEmpty ? '' : ' 副露 ${row.melds}'}';
    test(label, () {
      final hand = handFromNotation(row.hand, melds: row.melds);
      expect(
        standardShanten(hand.counts, hand.meldCount),
        row.standard,
        reason: '一般形',
      );
      if (row.sevenPairs != null) {
        expect(sevenPairsShanten(hand.counts), row.sevenPairs, reason: '七対子');
      }
      if (row.kokushi != null) {
        expect(kokushiShanten(hand.counts), row.kokushi, reason: '国士');
      }
      expect(
        shanten(hand),
        ShantenResult(shanten: row.total, type: row.type),
        reason: '総合',
      );
    });
  }
}

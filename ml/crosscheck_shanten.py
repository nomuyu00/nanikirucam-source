"""何切るエンジン（packages/mahjong_core/lib/src/engine）の突合用フィクスチャを作る。

固定シードで 10,000 手を生成し、Python の `mahjong` ライブラリでシャンテン数
（一般形・七対子・国士・総合）と受け入れ（3n+1 枚の手）を計算して、
packages/mahjong_core/test/fixtures/shanten_crosscheck.txt に書き出す。
Dart 側は test/engine/shanten_crosscheck_test.dart が全件を照合する。

実行方法（Windows、Python 3.12）:
    # 初回だけ（リポジトリ直下で）
    py -3.12 -m venv ml/.venv-engine
    ml/.venv-engine/Scripts/python -m pip install -r ml/requirements-engine.txt
    # 生成（リポジトリ直下からでも ml/ 直下からでもよい。出力先はこのファイルの位置から決める）
    ml/.venv-engine/Scripts/python ml/crosscheck_shanten.py
    # 照合
    cd packages/mahjong_core && dart test test/engine/shanten_crosscheck_test.dart

オプション:
    --seed N    乱数シード（既定 20261021）
    --out PATH  出力先（既定は上記フィクスチャ）

同じシード・同じライブラリなら毎回同じファイルになる。
"""

from __future__ import annotations

import argparse
import random
from collections import Counter
from importlib.metadata import version
from pathlib import Path

from mahjong.shanten import Shanten

DEFAULT_SEED = 20261021
DEFAULT_OUT = (
    Path(__file__).resolve().parent.parent
    / "packages"
    / "mahjong_core"
    / "test"
    / "fixtures"
    / "shanten_crosscheck.txt"
)

# カテゴリと件数（合計 10,000）
CATEGORIES = [
    ("uniform_13", 1200),  # 山から一様に 13 枚
    ("uniform_14", 1200),  # 山から一様に 14 枚
    ("one_suit", 1500),  # 1 色に偏った手（清一色寄り、他色・字牌は 0〜3 枚）
    ("near_agari", 2000),  # 和了形から 0〜3 枚入れ替え（13 枚系は更に 1 枚抜く）
    ("seven_pairs", 900),  # 対子 4〜7 組を含む手
    ("kokushi", 700),  # 么九牌 9〜13 種を含む手
    ("quads", 800),  # 同種 4 枚を 1〜3 組含む手
    ("melded_1_2", 1300),  # 副露 1〜2 個（一般形のみ比較）
    ("melded_3_4", 400),  # 副露 3〜4 個（一般形のみ比較）
]

YAOCHU = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
SUIT_CHARS = "mpsz"


def label(tile_id: int) -> str:
    return f"{tile_id % 9 + 1}{SUIT_CHARS[tile_id // 9]}"


class Wall:
    """残り枚数を持つ山。"""

    def __init__(self, rng: random.Random) -> None:
        self.rng = rng
        self.avail = [4] * 34

    def take(self, tile_id: int, n: int = 1) -> bool:
        if self.avail[tile_id] < n:
            return False
        self.avail[tile_id] -= n
        return True

    def put_back(self, tile_id: int) -> None:
        self.avail[tile_id] += 1

    def draw_random(self, pool: list[int] | None = None) -> int:
        candidates = [t for t in (pool if pool is not None else range(34)) if self.avail[t] > 0]
        weights = [self.avail[t] for t in candidates]
        tile_id = self.rng.choices(candidates, weights=weights)[0]
        self.avail[tile_id] -= 1
        return tile_id


def random_meld_tiles(wall: Wall, suit: int | None = None) -> list[int] | None:
    """順子か刻子を 1 つ山から取る。取れなければ None。"""
    rng = wall.rng
    for _ in range(50):
        if rng.random() < 0.6:
            s = suit if suit is not None and suit < 3 else rng.randrange(3)
            start = s * 9 + rng.randrange(7)
            tiles = [start, start + 1, start + 2]
            if all(wall.avail[t] >= 1 for t in tiles):
                for t in tiles:
                    wall.take(t)
                return tiles
        else:
            if suit is None:
                t = rng.randrange(34)
            elif suit < 3:
                t = suit * 9 + rng.randrange(9)
            else:
                t = 27 + rng.randrange(7)
            if wall.take(t, 3):
                return [t, t, t]
    return None


def complete_closed(wall: Wall, melds_needed: int, one_suit: int | None) -> list[int] | None:
    """melds_needed 面子 + 雀頭の和了形（門前部分）を作る。"""
    tiles: list[int] = []
    for _ in range(melds_needed):
        meld = random_meld_tiles(wall, one_suit)
        if meld is None:
            return None
        tiles += meld
    for _ in range(50):
        if one_suit is None:
            t = wall.rng.randrange(34)
        elif one_suit < 3:
            t = one_suit * 9 + wall.rng.randrange(9)
        else:
            t = 27 + wall.rng.randrange(7)
        if wall.take(t, 2):
            return tiles + [t, t]
    return None


def swap_tiles(wall: Wall, tiles: list[int], swaps: int) -> list[int]:
    """手から swaps 枚を抜き、山から同じ枚数を足す（抜いた牌は山に戻さない）。"""
    rng = wall.rng
    tiles = tiles[:]
    for _ in range(swaps):
        tiles.pop(rng.randrange(len(tiles)))
    for _ in range(swaps):
        tiles.append(wall.draw_random())
    return tiles


def drop_one(wall: Wall, tiles: list[int]) -> list[int]:
    tiles = tiles[:]
    tiles.pop(wall.rng.randrange(len(tiles)))
    return tiles


def near_agari_closed(wall: Wall, melds_needed: int, thirteen: bool, max_swaps: int) -> list[int] | None:
    one_suit = wall.rng.randrange(3) if wall.rng.random() < 0.3 else None
    tiles = complete_closed(wall, melds_needed, one_suit)
    if tiles is None:
        return None
    tiles = swap_tiles(wall, tiles, wall.rng.randint(0, max_swaps))
    if thirteen:
        tiles = drop_one(wall, tiles)
    return tiles


def gen_uniform(wall: Wall, n: int) -> list[int]:
    return [wall.draw_random() for _ in range(n)]


def gen_one_suit(wall: Wall, n: int) -> list[int]:
    rng = wall.rng
    suit = rng.randrange(3)
    pool = list(range(suit * 9, suit * 9 + 9))
    outside = rng.choice([0, 0, 0, 1, 2, 3])
    tiles = [wall.draw_random(pool) for _ in range(n - outside)]
    others = [t for t in range(34) if t not in pool]
    tiles += [wall.draw_random(others) for _ in range(outside)]
    return tiles


def gen_seven_pairs(wall: Wall, n: int) -> list[int]:
    rng = wall.rng
    pairs = rng.randint(4, 7) if n == 14 else rng.randint(4, 6)
    kinds = rng.sample([t for t in range(34) if wall.avail[t] >= 2], pairs)
    tiles: list[int] = []
    for t in kinds:
        wall.take(t, 2)
        tiles += [t, t]
    while len(tiles) < n:
        tiles.append(wall.draw_random())
    return swap_tiles(wall, tiles, rng.choice([0, 0, 1, 2]))


def gen_kokushi(wall: Wall, n: int) -> list[int]:
    rng = wall.rng
    kinds = rng.sample(YAOCHU, rng.randint(9, 13))
    tiles: list[int] = []
    for t in kinds:
        wall.take(t)
        tiles.append(t)
    if rng.random() < 0.6 and len(tiles) < n:
        tiles.append(wall.draw_random(YAOCHU))
    while len(tiles) < n:
        pool = YAOCHU if rng.random() < 0.3 else None
        tiles.append(wall.draw_random(pool))
    return tiles


def gen_quads(wall: Wall, n: int) -> list[int]:
    rng = wall.rng
    quads = rng.choice([1, 1, 1, 2, 2, 3])
    tiles: list[int] = []
    quad_ids = rng.sample(range(34), quads)
    for t in quad_ids:
        wall.take(t, 4)
        tiles += [t] * 4
    mode = rng.random()
    if mode < 0.35:
        # 4 枚の牌の近くに順子・搭子を足す
        for t in quad_ids:
            if t >= 27 or len(tiles) + 3 > n:
                continue
            base = t - t % 9
            start = max(base, min(base + 6, t - rng.randint(0, 2)))
            for u in range(start, start + 3):
                if u != t and len(tiles) < n and wall.take(u):
                    tiles.append(u)
    elif mode < 0.85:
        # 残りを面子で埋めて、テンパイ・一向聴付近で「5 枚目が要る」形を作りやすくする
        suit = quad_ids[0] // 9
        while len(tiles) + 3 <= n:
            meld = random_meld_tiles(wall, suit if rng.random() < 0.5 else None)
            if meld is None:
                break
            tiles += meld
    while len(tiles) < n:
        tiles.append(wall.draw_random())
    return tiles


def gen_melds(wall: Wall, count: int) -> list[tuple[str, int]] | None:
    """副露を山から取る。(種類, 牌 id) のリスト。chi の id は順子の先頭。"""
    rng = wall.rng
    melds: list[tuple[str, int]] = []
    for _ in range(count):
        for _attempt in range(50):
            kind = rng.choices(["chi", "pon", "kan", "ankan"], weights=[5, 4, 1, 1])[0]
            if kind == "chi":
                start = rng.randrange(3) * 9 + rng.randrange(7)
                if all(wall.avail[start + i] >= 1 for i in range(3)):
                    for i in range(3):
                        wall.take(start + i)
                    melds.append((kind, start))
                    break
            else:
                t = rng.randrange(34)
                if wall.take(t, 3 if kind == "pon" else 4):
                    melds.append((kind, t))
                    break
        else:
            return None
    return melds


def gen_melded(wall: Wall, meld_counts: list[int]) -> tuple[list[int], list[tuple[str, int]]] | None:
    rng = wall.rng
    m = rng.choice(meld_counts)
    melds = gen_melds(wall, m)
    if melds is None:
        return None
    thirteen = rng.random() < 0.5
    closed_n = (13 if thirteen else 14) - 3 * m
    if rng.random() < 0.5:
        tiles = near_agari_closed(wall, 4 - m, thirteen, 2)
        if tiles is None:
            return None
    else:
        tiles = gen_uniform(wall, closed_n)
    assert len(tiles) == closed_n
    return tiles, melds


def meld_tile_ids(melds: list[tuple[str, int]]) -> list[int]:
    ids: list[int] = []
    for kind, t in melds:
        if kind == "chi":
            ids += [t, t + 1, t + 2]
        elif kind == "pon":
            ids += [t] * 3
        else:
            ids += [t] * 4
    return ids


def generate(category: str, rng: random.Random) -> tuple[list[int], list[tuple[str, int]]]:
    while True:
        wall = Wall(rng)
        melds: list[tuple[str, int]] = []
        n = 13 if rng.random() < 0.5 else 14
        tiles: list[int] | None
        if category == "uniform_13":
            tiles = gen_uniform(wall, 13)
        elif category == "uniform_14":
            tiles = gen_uniform(wall, 14)
        elif category == "one_suit":
            tiles = gen_one_suit(wall, n)
        elif category == "near_agari":
            tiles = near_agari_closed(wall, 4, n == 13, 3)
        elif category == "seven_pairs":
            tiles = gen_seven_pairs(wall, n)
        elif category == "kokushi":
            tiles = gen_kokushi(wall, n)
        elif category == "quads":
            tiles = gen_quads(wall, n)
        elif category in ("melded_1_2", "melded_3_4"):
            res = gen_melded(wall, [1, 2] if category == "melded_1_2" else [3, 4])
            if res is None:
                continue
            tiles, melds = res
        else:
            raise ValueError(category)
        if tiles is None:
            continue
        counts = [0] * 34
        for t in tiles:
            counts[t] += 1
        if category == "quads" and 4 not in counts:
            continue
        return counts, melds


def evaluate(counts: list[int], melds: list[tuple[str, int]]) -> dict:
    n = sum(counts)
    m = len(melds)
    assert n + 3 * m in (13, 14), (n, m)
    assert (14 - n) // 3 == m  # ライブラリは手牌の枚数から副露数を決める
    used = counts[:]
    for t in meld_tile_ids(melds):
        used[t] += 1
    assert max(used) <= 4

    regular = Shanten.calculate_shanten_for_regular_hand(counts)
    total = Shanten.calculate_shanten(counts)
    if m == 0:
        chiitoi = Shanten.calculate_shanten_for_chiitoitsu_hand(counts)
        kokushi = Shanten.calculate_shanten_for_kokushi_hand(counts)
        assert total == min(regular, chiitoi, kokushi)
    else:
        chiitoi = kokushi = None
        assert total == regular

    ukeire = None
    if (n + 3 * m) == 13:
        ukeire = [0] * 34
        for t in range(34):
            left = 4 - used[t]
            if counts[t] >= 4 or left <= 0:
                continue
            counts[t] += 1
            s = Shanten.calculate_shanten(counts)
            counts[t] -= 1
            if s < total:
                ukeire[t] = left
    return {
        "regular": regular,
        "chiitoi": chiitoi,
        "kokushi": kokushi,
        "total": total,
        "ukeire": ukeire,
    }


def format_melds(melds: list[tuple[str, int]]) -> str:
    if not melds:
        return "-"
    return ",".join(f"{kind}:{label(t)}" for kind, t in melds)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    lines: list[str] = []
    dist: Counter[int] = Counter()
    for category, count in CATEGORIES:
        for _ in range(count):
            counts, melds = generate(category, rng)
            r = evaluate(counts, melds)
            dist[r["total"]] += 1

            def opt(v: int | None) -> str:
                return "-" if v is None else str(v)

            ukeire = "-" if r["ukeire"] is None else "".join(map(str, r["ukeire"]))
            lines.append(
                " ".join(
                    [
                        "".join(map(str, counts)),
                        format_melds(melds),
                        str(r["regular"]),
                        opt(r["chiitoi"]),
                        opt(r["kokushi"]),
                        str(r["total"]),
                        ukeire,
                        category,
                    ]
                )
            )

    header = [
        "# なにきるカム エンジン突合フィクスチャ（ml/crosscheck_shanten.py が生成。手で編集しない）",
        f"# seed={args.seed} library=mahjong=={version('mahjong')}",
        "# 期待値: Shanten.calculate_shanten_for_regular_hand / _for_chiitoitsu_hand /"
        " _for_kokushi_hand / calculate_shanten",
        "# 形式: <counts 34桁> <副露> <一般形> <七対子> <国士> <総合> <受け入れ 34桁> <カテゴリ>",
        "#   counts: 牌 id 0..33（0-8 萬, 9-17 筒, 18-26 索, 27-33 字）ごとの手牌（副露を除く）の枚数",
        "#   副露: '-' か カンマ区切りの chi:<順子の先頭> / pon:<牌> / kan:<牌>（明槓）/ ankan:<牌>",
        "#   七対子・国士: 副露ありは '-'（一般形のみ比較）",
        "#   受け入れ: 3n+1 枚の手のみ。牌 id ごとに、引いて総合シャンテンが下がるなら残り枚数"
        "（4 − 手牌 − 自分の副露。手に 4 枚ある牌と残り 0 の牌は除く）、それ以外は 0。3n+2 枚の手は '-'",
        "# カテゴリ: " + ", ".join(f"{c}={n}" for c, n in CATEGORIES),
        f"# 件数: {len(lines)}",
        "# 総合シャンテンの分布: " + ", ".join(f"{k}={dist[k]}" for k in sorted(dist)),
    ]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(header + lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(lines)} hands to {args.out}")
    print("shanten distribution:", dict(sorted(dist.items())))


if __name__ == "__main__":
    main()

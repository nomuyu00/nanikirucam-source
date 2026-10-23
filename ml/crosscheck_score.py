"""和了の採点（packages/mahjong_core/lib/src/scoring/win_scorer.dart）の突合用フィクスチャを作る。

固定シードでランダムな和了形（一般形・七対子・国士。副露・槓・赤5あり、役の付きやすい偏りと
役満を混ぜる）と文脈（ツモ/ロン、立直・ダブル立直・一発、海底/河底/嶺上/槍槓、天和/地和/人和、
親子・場風・自風、本場・供託、ドラ表示牌・裏ドラ表示牌）を作り、Python の `mahjong` ライブラリ
（HandCalculator.estimate_hand_value）で役・翻・符・点数・支払い（またはエラー）を求めて
packages/mahjong_core/test/fixtures/score_crosscheck.txt に書き出す。
Dart 側は test/scoring/score_crosscheck_test.dart が全件を照合する。

実行方法（Windows、Python 3.12。リポジトリ直下から）:
    ml/.venv-engine/Scripts/python ml/crosscheck_score.py
    # 照合（PowerShell から）
    wsl.exe -d Ubuntu -e bash /mnt/d/ProgramFiles/IdeaProjects/nanikirucam/tool/wsl_flutter.sh score core 'dart test test/scoring/score_crosscheck_test.dart'

オプション:
    --seed N    乱数シード（既定 20261023）
    --out PATH  出力先（既定は上記フィクスチャ）
    --scale X   件数の倍率（既定 1.0。試すときは 0.1 など）

同じシード・同じライブラリなら毎回同じファイルになる。
"""

from __future__ import annotations

import argparse
import random
from collections import Counter
from importlib.metadata import version
from pathlib import Path

from mahjong.constants import EAST
from mahjong.hand_calculating.hand import HandCalculator
from mahjong.hand_calculating.hand_config import HandConfig, HandConstants, OptionalRules
from mahjong.meld import Meld

DEFAULT_SEED = 20261023
DEFAULT_OUT = (
    Path(__file__).resolve().parent.parent
    / "packages"
    / "mahjong_core"
    / "test"
    / "fixtures"
    / "score_crosscheck.txt"
)

SUITS = "mpsz"
RED_IDS = {16, 52, 88}  # 136 形式の赤5（萬・筒・索）
YAOCHU = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
TERMINALS = [0, 8, 9, 17, 18, 26]
HONORS = list(range(27, 34))
WINDS = [27, 28, 29, 30]
DRAGONS = [31, 32, 33]
GREEN = [19, 20, 21, 23, 25, 32]

# ルールの組（Dart 側の Ruleset と 1 対 1）。
PROFILES = {
    # Mリーグ相当 = Rulesets.mLeague()
    "A": dict(
        options=dict(
            has_open_tanyao=True,
            has_aka_dora=True,
            has_double_yakuman=False,
            kazoe_limit=HandConstants.KAZOE_LIMITED,
            kiriage=False,
            fu_for_open_pinfu=True,
            fu_for_pinfu_tsumo=False,
            renhou_as_yakuman=False,
        ),
        renhou=False,
        count=21000,
    ),
    # 喰いタンなし・赤なし・切り上げ満貫あり
    "B": dict(
        options=dict(
            has_open_tanyao=False,
            has_aka_dora=False,
            has_double_yakuman=False,
            kazoe_limit=HandConstants.KAZOE_LIMITED,
            kiriage=True,
            fu_for_open_pinfu=True,
            fu_for_pinfu_tsumo=False,
            renhou_as_yakuman=False,
        ),
        renhou=False,
        count=1500,
    ),
    # ダブル役満あり・数え役満なし（三倍満止まり）・人和は役満
    "C": dict(
        options=dict(
            has_open_tanyao=True,
            has_aka_dora=True,
            has_double_yakuman=True,
            kazoe_limit=HandConstants.KAZOE_SANBAIMAN,
            kiriage=False,
            fu_for_open_pinfu=True,
            fu_for_pinfu_tsumo=False,
            renhou_as_yakuman=True,
        ),
        renhou=True,
        count=1500,
    ),
    # 人和は満貫（5 翻の役として足す）
    "D": dict(
        options=dict(
            has_open_tanyao=True,
            has_aka_dora=True,
            has_double_yakuman=False,
            kazoe_limit=HandConstants.KAZOE_LIMITED,
            kiriage=False,
            fu_for_open_pinfu=True,
            fu_for_pinfu_tsumo=False,
            renhou_as_yakuman=False,
        ),
        renhou=True,
        count=1000,
    ),
}


def label34(t: int) -> str:
    return f"{t % 9 + 1}{SUITS[t // 9]}"


def label136(i: int) -> str:
    t = i // 4
    if i in RED_IDS:
        return f"0{SUITS[t // 9]}"
    return label34(t)


def mpsz(ids136: list[int]) -> str:
    """136 形式の牌を mpsz 表記にする（赤は 0）。並びは牌の順。"""
    if not ids136:
        return "-"
    out = []
    for s in range(4):
        digits = []
        for i in sorted(ids136):
            if i // 36 != s:
                continue
            digits.append(label136(i)[0])
        if digits:
            out.append("".join(digits) + SUITS[s])
    return "".join(out)


class Wall:
    """136 枚の山。赤5は各色 1 枚（copy 0）。"""

    def __init__(self, rng: random.Random) -> None:
        self.rng = rng
        self.left = {t: [t * 4 + c for c in range(4)] for t in range(34)}

    def avail(self, t: int) -> int:
        return len(self.left[t])

    def take(self, t: int, red_prob: float = 0.4) -> int:
        lst = self.left[t]
        red = t * 4
        if red in RED_IDS and red in lst:
            if self.rng.random() < red_prob or len(lst) == 1:
                lst.remove(red)
                return red
            choices = [x for x in lst if x != red]
        else:
            choices = list(lst)
        x = self.rng.choice(choices)
        lst.remove(x)
        return x

    def take_any(self) -> int:
        t = self.rng.choice([t for t in range(34) if self.left[t]])
        return self.take(t)


# --------------------------------------------------------------------------- 手の形

def seq(t: int) -> dict:
    return {"kind": "seq", "tile": t, "call": None}


def trip(t: int) -> dict:
    return {"kind": "trip", "tile": t, "call": None}


def pair(t: int) -> dict:
    return {"kind": "pair", "tile": t, "call": None}


def rand_seq(rng: random.Random, suits=(0, 1, 2), starts=range(7)) -> dict:
    return seq(rng.choice(suits) * 9 + rng.choice(list(starts)))


def rand_set(rng: random.Random, seq_prob: float = 0.6, tiles=None, suits=(0, 1, 2), starts=range(7)) -> dict:
    if rng.random() < seq_prob:
        return rand_seq(rng, suits, starts)
    pool = tiles if tiles is not None else list(range(34))
    return trip(rng.choice(pool))


def style_uniform(rng):
    return [rand_set(rng) for _ in range(4)] + [pair(rng.randrange(34))]


def style_tanyao(rng):
    simples = [s * 9 + v for s in range(3) for v in range(1, 8)]
    return [rand_set(rng, 0.65, simples, starts=range(1, 6)) for _ in range(4)] + [pair(rng.choice(simples))]


def style_honitsu(rng):
    s = rng.randrange(3)
    pool = [s * 9 + v for v in range(9)] + HONORS
    blocks = [rand_set(rng, 0.5, pool, suits=(s,)) for _ in range(4)]
    blocks.append(pair(rng.choice(pool)))
    if not any(b["tile"] >= 27 for b in blocks):
        blocks[-1] = pair(rng.choice(HONORS))
    return blocks


def style_chinitsu(rng):
    s = rng.randrange(3)
    pool = [s * 9 + v for v in range(9)]
    return [rand_set(rng, 0.65, pool, suits=(s,)) for _ in range(4)] + [pair(rng.choice(pool))]


def style_chanta(rng, honors=True):
    pool = YAOCHU if honors else TERMINALS
    blocks = []
    for _ in range(4):
        if rng.random() < 0.55:
            blocks.append(seq(rng.randrange(3) * 9 + rng.choice([0, 6])))
        else:
            blocks.append(trip(rng.choice(pool)))
    blocks.append(pair(rng.choice(pool)))
    if not any(b["kind"] == "seq" for b in blocks):
        blocks[0] = seq(rng.randrange(3) * 9 + rng.choice([0, 6]))
    if honors and not any(b["tile"] >= 27 for b in blocks):
        blocks[-1] = pair(rng.choice(HONORS))
    return blocks


def style_toitoi(rng):
    pool = list(range(34)) + HONORS
    return [trip(rng.choice(pool)) for _ in range(4)] + [pair(rng.randrange(34))]


def style_yakuhai(rng):
    blocks = [trip(rng.choice(DRAGONS + WINDS))]
    if rng.random() < 0.3:
        blocks.append(trip(rng.choice(DRAGONS + WINDS)))
    while len(blocks) < 4:
        blocks.append(rand_set(rng))
    blocks.append(pair(rng.randrange(34)))
    return blocks


def style_sanshoku(rng):
    v = rng.randrange(7)
    blocks = [seq(v), seq(9 + v), seq(18 + v), rand_set(rng), pair(rng.randrange(34))]
    return blocks


def style_ittsu(rng):
    s = rng.randrange(3) * 9
    return [seq(s), seq(s + 3), seq(s + 6), rand_set(rng), pair(rng.randrange(34))]


def style_doukou(rng):
    v = rng.randrange(9)
    return [trip(v), trip(9 + v), trip(18 + v), rand_set(rng), pair(rng.randrange(34))]


def style_peikou(rng):
    a = rand_seq(rng)
    blocks = [a, dict(a)]
    if rng.random() < 0.4:
        b = rand_seq(rng)
        blocks += [b, dict(b)]
    else:
        blocks += [rand_set(rng), rand_set(rng)]
    blocks.append(pair(rng.randrange(34)))
    for b in blocks:
        b["nocall"] = True
    return blocks


def style_pinfu(rng):
    blocks = [rand_seq(rng) for _ in range(4)]
    blocks.append(pair(rng.choice(list(range(27)) + WINDS)))
    for b in blocks:
        b["nocall"] = True
    return blocks


def style_sanankou(rng):
    blocks = [trip(rng.randrange(34)) for _ in range(3)]
    for b in blocks:
        b["nocall"] = True
    blocks += [rand_set(rng), pair(rng.randrange(34))]
    return blocks


def style_shousangen(rng):
    d = rng.sample(DRAGONS, 3)
    return [trip(d[0]), trip(d[1]), rand_set(rng), rand_set(rng), pair(d[2])]


def style_honroutou(rng):
    t = rng.sample(TERMINALS, 2)
    h = rng.sample(HONORS, 3)
    tiles = t + h
    rng.shuffle(tiles)
    return [trip(x) for x in tiles[:4]] + [pair(tiles[4])]


def style_kans(rng):
    n = rng.choice([1, 1, 2, 2, 3, 3, 3])
    blocks = []
    for _ in range(n):
        b = trip(rng.randrange(34))
        b["kan"] = True
        blocks.append(b)
    while len(blocks) < 4:
        blocks.append(rand_set(rng))
    blocks.append(pair(rng.randrange(34)))
    return blocks


def style_daisangen(rng):
    return [trip(31), trip(32), trip(33), rand_set(rng), pair(rng.randrange(34))]


def style_shousuushii(rng):
    w = rng.sample(WINDS, 4)
    return [trip(w[0]), trip(w[1]), trip(w[2]), rand_set(rng), pair(w[3])]


def style_daisuushii(rng):
    return [trip(w) for w in WINDS] + [pair(rng.randrange(34))]


def style_tsuuiisou(rng):
    h = rng.sample(HONORS, 5)
    return [trip(x) for x in h[:4]] + [pair(h[4])]


def style_ryuuiisou(rng):
    blocks = []
    for _ in range(4):
        if rng.random() < 0.35:
            blocks.append(seq(19))  # 234s
        else:
            blocks.append(trip(rng.choice(GREEN)))
    blocks.append(pair(rng.choice(GREEN)))
    return blocks


def style_chinroutou(rng):
    t = rng.sample(TERMINALS, 5)
    return [trip(x) for x in t[:4]] + [pair(t[4])]


def style_suuankou(rng):
    tiles = rng.sample(range(34), 5)
    blocks = [trip(x) for x in tiles[:4]] + [pair(tiles[4])]
    for b in blocks:
        b["nocall"] = True
        if b["kind"] == "trip" and rng.random() < 0.15:
            b["call"] = "ankan"
    return blocks


def style_suukantsu(rng):
    tiles = rng.sample(range(34), 5)
    blocks = [trip(x) for x in tiles[:4]] + [pair(tiles[4])]
    for b in blocks[:4]:
        b["kan"] = True
    return blocks


STYLES = [
    ("uniform", 16, style_uniform),
    ("tanyao", 9, style_tanyao),
    ("honitsu", 8, style_honitsu),
    ("chinitsu", 6, style_chinitsu),
    ("chanta", 4, lambda rng: style_chanta(rng, True)),
    ("junchan", 3, lambda rng: style_chanta(rng, False)),
    ("toitoi", 5, style_toitoi),
    ("yakuhai", 7, style_yakuhai),
    ("sanshoku", 4, style_sanshoku),
    ("ittsu", 4, style_ittsu),
    ("doukou", 2, style_doukou),
    ("peikou", 4, style_peikou),
    ("pinfu", 6, style_pinfu),
    ("sanankou", 4, style_sanankou),
    ("shousangen", 2, style_shousangen),
    ("honroutou", 2, style_honroutou),
    ("kans", 5, style_kans),
    ("daisangen", 1.2, style_daisangen),
    ("shousuushii", 1.0, style_shousuushii),
    ("daisuushii", 0.8, style_daisuushii),
    ("tsuuiisou", 0.8, style_tsuuiisou),
    ("ryuuiisou", 2.0, style_ryuuiisou),
    ("chinroutou", 0.8, style_chinroutou),
    ("suuankou", 2.0, style_suuankou),
    ("suukantsu", 0.8, style_suukantsu),
    # 特殊形（ブロックではなく手牌を直接作る）
    ("chuuren", 0.9, None),
    ("chiitoitsu", 7, None),
    ("kokushi", 1.5, None),
]


class Hand:
    """生成した和了形（136 形式）。"""

    def __init__(self) -> None:
        self.closed: list[int] = []  # 門前部分（和了牌を含む）
        self.melds: list[tuple[str, list[int]]] = []  # (c/p/m/a/k, tiles)
        self.win: int = -1
        self.style = ""

    @property
    def all_tiles(self) -> list[int]:
        return self.closed + [t for _, ts in self.melds for t in ts]

    @property
    def open(self) -> bool:
        return any(k != "a" for k, _ in self.melds)

    @property
    def kans(self) -> int:
        return sum(1 for k, _ in self.melds if k in "mak")


def assign_calls(rng: random.Random, blocks: list[dict]) -> None:
    mode = rng.choices(["none", "light", "heavy"], weights=[48, 32, 20])[0]
    p = {"none": 0.0, "light": 0.3, "heavy": 0.65}[mode]
    for b in blocks:
        if b["kind"] == "pair" or b.get("nocall") or b["call"]:
            continue
        if b.get("kan"):
            b["call"] = rng.choice(["minkan", "ankan", "kakan", "ankan"])
            continue
        if rng.random() < p:
            if b["kind"] == "seq":
                b["call"] = "chi"
            else:
                b["call"] = rng.choices(["pon", "minkan", "kakan", "ankan"], weights=[55, 15, 15, 15])[0]
        elif b["kind"] == "trip" and rng.random() < 0.06:
            b["call"] = "ankan"


def build_from_blocks(rng: random.Random, wall: Wall, blocks: list[dict]) -> Hand | None:
    need = Counter()
    for b in blocks:
        t = b["tile"]
        if b["kind"] == "seq":
            if t >= 27 or t % 9 > 6:
                return None
            for x in (t, t + 1, t + 2):
                need[x] += 1
        elif b["kind"] == "trip":
            need[t] += 4 if b["call"] in ("minkan", "ankan", "kakan") else 3
        else:
            need[t] += 2
    if any(c > 4 for c in need.values()):
        return None
    hand = Hand()
    for b in blocks:
        t = b["tile"]
        if b["kind"] == "seq":
            ids = [wall.take(x) for x in (t, t + 1, t + 2)]
        elif b["kind"] == "trip":
            n = 4 if b["call"] in ("minkan", "ankan", "kakan") else 3
            ids = [wall.take(t) for _ in range(n)]
        else:
            ids = [wall.take(t) for _ in range(2)]
        call = b["call"]
        if call is None:
            hand.closed += ids
        else:
            kind = {"chi": "c", "pon": "p", "minkan": "m", "ankan": "a", "kakan": "k"}[call]
            hand.melds.append((kind, sorted(ids)))
    return hand


def build_special(rng: random.Random, wall: Wall, name: str) -> Hand | None:
    hand = Hand()
    if name == "chuuren":
        s = rng.randrange(3) * 9
        types = [s] * 3 + [s + v for v in range(1, 8)] + [s + 8] * 3 + [s + rng.randrange(9)]
    elif name == "kokushi":
        types = YAOCHU + [rng.choice(YAOCHU)]
    else:  # chiitoitsu
        variant = rng.choices(["uniform", "tanyao", "honitsu", "chinitsu", "honroutou", "tsuuiisou"],
                              weights=[45, 18, 15, 10, 8, 4])[0]
        if variant == "uniform":
            pool = list(range(34))
        elif variant == "tanyao":
            pool = [s * 9 + v for s in range(3) for v in range(1, 8)]
        elif variant == "honitsu":
            s = rng.randrange(3)
            pool = [s * 9 + v for v in range(9)] + HONORS
        elif variant == "chinitsu":
            s = rng.randrange(3)
            pool = [s * 9 + v for v in range(9)]
        elif variant == "honroutou":
            pool = YAOCHU
        else:
            pool = HONORS
        types = [t for t in rng.sample(pool, 7) for _ in range(2)]
    if any(c > 4 for c in Counter(types).values()):
        return None
    hand.closed = [wall.take(t) for t in types]
    return hand


def make_hand(rng: random.Random) -> tuple[Hand, Wall]:
    names = [s[0] for s in STYLES]
    weights = [s[1] for s in STYLES]
    fns = {s[0]: s[2] for s in STYLES}
    while True:
        wall = Wall(rng)
        name = rng.choices(names, weights=weights)[0]
        if fns[name] is None:
            hand = build_special(rng, wall, name)
        else:
            blocks = fns[name](rng)
            rng.shuffle(blocks)
            assign_calls(rng, blocks)
            hand = build_from_blocks(rng, wall, blocks)
        if hand is None:
            continue
        hand.style = name
        hand.win = rng.choice(hand.closed)
        return hand, wall


# --------------------------------------------------------------------------- 文脈

class Ctx:
    def __init__(self) -> None:
        self.tsumo = False
        self.round_wind = 0
        self.seat_wind = 1
        self.honba = 0
        self.kyotaku = 0
        self.flags = set()  # r d i h H n c t j e
        self.dora: list[int] = []
        self.ura: list[int] = []

    def encode(self) -> str:
        order = "rdihHnctje"
        flags = "".join(f for f in order if f in self.flags) or "-"
        return f"{'T' if self.tsumo else 'R'},{self.round_wind + 1},{self.seat_wind + 1},{self.honba},{self.kyotaku},{flags}"


def make_ctx(rng: random.Random, hand: Hand, wall: Wall, renhou_rule: bool) -> Ctx:
    c = Ctx()
    c.tsumo = rng.random() < 0.5
    c.round_wind = rng.choices([0, 1, 2, 3], weights=[60, 30, 7, 3])[0]
    c.seat_wind = rng.randrange(4)
    dealer = c.seat_wind == 0
    closed = not hand.open
    no_meld = not hand.melds
    f = c.flags
    if closed:
        x = rng.random()
        if x < 0.06:
            f.add("d")
        elif x < 0.50:
            f.add("r")
    if f & {"r", "d"} and rng.random() < 0.25:
        f.add("i")
    if c.tsumo:
        if hand.kans and rng.random() < 0.35:
            f.add("n")
            f.discard("i")
        elif rng.random() < 0.04:
            f.add("h")
    else:
        win_type = hand.win // 4
        same = sum(1 for t in hand.all_tiles if t // 4 == win_type)
        if same == 1 and rng.random() < 0.06:
            f.add("c")
        elif rng.random() < 0.04:
            f.add("H")
    if no_meld:
        if c.tsumo and rng.random() < 0.035:
            f.clear()
            f.add("t" if dealer else "j")
        elif renhou_rule and not c.tsumo and not dealer and rng.random() < 0.2:
            f.clear()
            f.add("e")
    c.honba = rng.choices([0, 1, 2, 3, 5, 8], weights=[60, 15, 10, 7, 5, 3])[0]
    c.kyotaku = rng.choices([0, 1, 2, 3, 4], weights=[60, 20, 10, 6, 4])[0]

    n = min(5, 1 + hand.kans + (1 if rng.random() < 0.1 else 0))
    heavy = rng.random() < 0.06  # ドラを手牌の牌に寄せる（数え役満を出すため）
    types_in_hand = sorted({t // 4 for t in hand.all_tiles})

    def indicator() -> int:
        if heavy:
            for _ in range(10):
                t = rng.choice(types_in_hand)
                prev = prev_of(t)
                if wall.avail(prev):
                    return wall.take(prev)
        return wall.take_any()

    if heavy:
        n = rng.randint(max(n, 2), 5)
    c.dora = [indicator() for _ in range(n)]
    if f & {"r", "d"} or rng.random() < 0.05:
        c.ura = [indicator() for _ in range(n)]
    return c


def prev_of(t: int) -> int:
    """ドラが t になる表示牌。"""
    if t < 27:
        return t // 9 * 9 + (t % 9 + 8) % 9
    if t <= 30:
        return 27 + (t - 27 + 3) % 4
    return 31 + (t - 31 + 2) % 3


INVALID_KINDS = [
    "riichi_open", "ippatsu_no_riichi", "chankan_tsumo", "rinshan_ron", "haitei_ron",
    "houtei_tsumo", "haitei_rinshan", "houtei_chankan", "tenhou_child", "tenhou_ron",
    "tenhou_meld", "chiihou_dealer", "chiihou_ron", "chiihou_meld",
]
RENHOU_INVALID_KINDS = ["renhou_dealer", "renhou_tsumo", "renhou_meld"]


def make_invalid(rng: random.Random, hand: Hand, c: Ctx, kind: str) -> bool:
    """文脈を 1 つだけ矛盾させる。作れない手なら False。"""
    f = c.flags
    f.clear()
    c.ura = []
    if kind == "riichi_open":
        if not hand.open:
            return False
        f.add(rng.choice("rd"))
    elif kind == "ippatsu_no_riichi":
        if hand.open:
            return False
        f.add("i")
    elif kind == "chankan_tsumo":
        c.tsumo = True
        f.add("c")
    elif kind == "rinshan_ron":
        if not hand.kans:
            return False
        c.tsumo = False
        f.add("n")
    elif kind == "haitei_ron":
        c.tsumo = False
        f.add("h")
    elif kind == "houtei_tsumo":
        c.tsumo = True
        f.add("H")
    elif kind == "haitei_rinshan":
        if not hand.kans:
            return False
        c.tsumo = True
        f |= {"h", "n"}
    elif kind == "houtei_chankan":
        win_type = hand.win // 4
        if sum(1 for t in hand.all_tiles if t // 4 == win_type) != 1:
            return False
        c.tsumo = False
        f |= {"H", "c"}
    elif kind.startswith(("tenhou", "chiihou", "renhou")):
        base = kind.split("_")[0]
        flag = {"tenhou": "t", "chiihou": "j", "renhou": "e"}[base]
        dealer_ok = base == "tenhou"
        tsumo_ok = base != "renhou"
        c.seat_wind = 0 if dealer_ok else rng.randrange(1, 4)
        c.tsumo = tsumo_ok
        if hand.melds and not kind.endswith("meld"):
            return False
        if kind.endswith("meld"):
            if not hand.melds:
                return False
        elif kind.endswith(("child", "dealer")):
            c.seat_wind = rng.randrange(1, 4) if dealer_ok else 0
        else:  # ron / tsumo
            c.tsumo = not tsumo_ok
        f.add(flag)
    return True


def perturb(rng: random.Random, hand: Hand, wall: Wall) -> None:
    """和了牌以外の門前の牌を 1 枚入れ替える（和了形でなくなることが多い）。"""
    idx = [i for i, t in enumerate(hand.closed) if t != hand.win]
    if not idx:
        return
    i = rng.choice(idx)
    hand.closed[i] = wall.take_any()


# --------------------------------------------------------------------------- 採点

MELD_TYPES = {"c": Meld.CHI, "p": Meld.PON, "m": Meld.KAN, "a": Meld.KAN, "k": Meld.SHOUMINKAN}


def evaluate(hand: Hand, c: Ctx, profile: dict) -> str:
    options = OptionalRules(**profile["options"])
    f = c.flags
    config = HandConfig(
        is_tsumo=c.tsumo,
        is_riichi="r" in f,
        is_daburu_riichi="d" in f,
        is_ippatsu="i" in f,
        is_haitei="h" in f,
        is_houtei="H" in f,
        is_rinshan="n" in f,
        is_chankan="c" in f,
        is_tenhou="t" in f,
        is_chiihou="j" in f,
        is_renhou="e" in f,
        player_wind=EAST + c.seat_wind,
        round_wind=EAST + c.round_wind,
        tsumi_number=c.honba,
        kyoutaku_number=c.kyotaku,
        options=options,
    )
    melds = [Meld(meld_type=MELD_TYPES[k], tiles=ts, opened=(k != "a")) for k, ts in hand.melds]
    res = HandCalculator.estimate_hand_value(
        hand.all_tiles,
        hand.win,
        melds=melds,
        dora_indicators=c.dora,
        ura_dora_indicators=c.ura,
        config=config,
    )
    if res.error:
        return f"E:{res.error}"
    cost = res.cost
    yaku = []
    for y in res.yaku:
        han = y.han_open if (res.is_open_hand and y.han_open) else y.han_closed
        yaku.append(f"{y.yaku_id}:{han}")
    level = (cost["yaku_level"] or "-").replace(" ", "_")
    return ",".join(
        str(x)
        for x in [
            res.han,
            res.fu,
            level,
            cost["main"],
            cost["main_bonus"],
            cost["additional"],
            cost["additional_bonus"],
            cost["kyoutaku_bonus"],
            cost["total"],
            "+".join(yaku),
        ]
    )


def encode_melds(hand: Hand) -> str:
    if not hand.melds:
        return "-"
    return ",".join(k + mpsz(ts) for k, ts in hand.melds)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--scale", type=float, default=1.0)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    lines = []
    yaku_counter: Counter = Counter()
    error_counter: Counter = Counter()
    style_counter: Counter = Counter()
    total = 0
    for pid, profile in PROFILES.items():
        n = int(profile["count"] * args.scale)
        for _ in range(n):
            hand, wall = make_hand(rng)
            r = rng.random()
            if 0.02 <= r < 0.05:
                # 文脈（槍槓の可否など）を手牌から決めるので、入れ替えは文脈より先に行う。
                perturb(rng, hand, wall)
            c = make_ctx(rng, hand, wall, profile["renhou"])
            if r < 0.02:
                kinds = INVALID_KINDS + (RENHOU_INVALID_KINDS if profile["renhou"] else [])
                for _ in range(20):
                    if make_invalid(rng, hand, c, rng.choice(kinds)):
                        break
            expected = evaluate(hand, c, profile)
            style_counter[hand.style] += 1
            if expected.startswith("E:"):
                error_counter[expected[2:]] += 1
            else:
                for item in expected.split(",")[-1].split("+"):
                    if item:
                        yaku_counter[int(item.split(":")[0])] += 1
            lines.append(
                " ".join(
                    [
                        pid,
                        mpsz(hand.closed),
                        encode_melds(hand),
                        label136(hand.win),
                        c.encode(),
                        mpsz(c.dora),
                        mpsz(c.ura),
                        expected,
                    ]
                )
            )
            total += 1

    header = [
        "# なにきるカム 和了採点の突合フィクスチャ（ml/crosscheck_score.py が生成。手で編集しない）",
        f"# seed={args.seed} library=mahjong=={version('mahjong')} count={total}",
        "# 期待値: HandCalculator.estimate_hand_value（HandResponse の han / fu / cost / yaku / error）",
        "# 形式: <ルール> <門前部分> <副露> <和了牌> <文脈> <ドラ表示牌> <裏ドラ表示牌> <期待値>",
        "#   牌は mpsz 表記（赤5は 0）。副露は種類 1 文字＋牌（c=チー p=ポン m=大明槓 a=暗槓 k=加槓）をカンマ区切り。なしは -",
        "#   文脈: <T=ツモ|R=ロン>,<場風 1-4>,<自風 1-4>,<本場>,<供託>,<状況>",
        "#     状況: r=立直 d=ダブル立直 i=一発 h=海底 H=河底 n=嶺上 c=槍槓 t=天和 j=地和 e=人和（なしは -）",
        "#   期待値: E:<エラー> または <翻>,<符>,<yaku_level>,<main>,<main_bonus>,<additional>,"
        "<additional_bonus>,<kyoutaku_bonus>,<total>,<役 id:翻 を + で連結>",
    ]
    for pid, profile in PROFILES.items():
        opts = " ".join(f"{k}={v}" for k, v in profile["options"].items())
        header.append(f"# ルール {pid}: {opts}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(header + lines) + "\n", encoding="utf-8", newline="\n")

    print(f"wrote {total} cases to {args.out}")
    print("errors:", dict(error_counter))
    print("styles:", dict(style_counter))
    print("yaku (by id):")
    for k in sorted(yaku_counter):
        print(f"  {k}: {yaku_counter[k]}")


if __name__ == "__main__":
    main()

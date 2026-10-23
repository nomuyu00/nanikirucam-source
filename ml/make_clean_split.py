"""Build a leakage-free split of master.v7i: every augmented/cropped copy of one
source photo (same Roboflow base name, or identical label layout) stays in one split.

Usage: python -I -B make_clean_split.py <SRC[,SRC2,...]> <DST>
  Each SRC is a YOLO dataset with train/valid/test/{images,labels} (any of the three
  may be missing). Extra data such as frames extracted from videos (extract_frames.py)
  is added as another SRC; name its files "vid<clip>_f<frame>.jpg" (extract_frames.py does)
  so that every frame of one video stays in the same split. A Roboflow re-export that
  appends "_jpg.rf.<hash>" to the name is fine. With a single SRC the result is the
  same as before.
"""
import collections, os, random, re, shutil, sys
SRCS, DST = sys.argv[1].split(','), sys.argv[2]
RED = {1, 2, 3}  # 0m 0p 0s
BACK = 0
CLIP_RE = re.compile(r'^(vid[A-Za-z0-9]+)_f\d+')


def group_of(f):
    m = CLIP_RE.match(f)
    if m:
        return 'clip:' + m.group(1)  # video frame: one clip = one group
    return f.split('.rf.')[0]


recs = []
n_unlabeled = 0
for SRC in SRCS:
    for s in ('train', 'valid', 'test'):
        if not os.path.isdir(f'{SRC}/{s}/images'):
            continue
        for f in sorted(os.listdir(f'{SRC}/{s}/images')):
            if 'Zone.Identifier' in f:
                continue
            stem = f.rsplit('.', 1)[0]
            lab = f'{SRC}/{s}/labels/{stem}.txt'
            rows = []
            if not os.path.exists(lab):
                # unlabeled frames must not become "no tiles" negatives
                n_unlabeled += 1
                continue
            for line in open(lab):
                p = line.split()
                if len(p) >= 5:
                    rows.append((int(p[0]), *map(float, p[1:5])))
            recs.append(dict(src=SRC, origin=SRCS.index(SRC), split=s, file=f, stem=stem, base=group_of(f), rows=rows))

if n_unlabeled:
    print('skipped images without a label file:', n_unlabeled)
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x
def union(a, b):
    parent[find(a)] = find(b)

def sig(rows, rot):
    out = []
    for c, x, y, w, h in rows:
        if rot:
            x, y = 1 - x, 1 - y
        out.append((c, round(x, 2), round(y, 2), round(w, 2), round(h, 2)))
    return tuple(sorted(out))

seen = {}
for r in recs:
    find(r['base'])
    if len(r['rows']) >= 5:
        for rot in (False, True):
            k = sig(r['rows'], rot)
            if k in seen:
                union(r['base'], seen[k])
            else:
                seen[k] = r['base']

groups = collections.defaultdict(list)
for r in recs:
    groups[find(r['base'])].append(r)
print('source groups:', len(groups))

def kind(items):
    hand = any(len(i['rows']) >= 12 for i in items)
    red = any(c in RED for i in items for c, *_ in i['rows'])
    return (hand, red)

# Each SRC is split on its own (own random stream, own stratification), so adding data
# never moves the groups of the SRCs before it between train/valid/test: the held-out
# test of the first SRC stays the same and numbers stay comparable across retrainings.
rngs = {}
by_kind = collections.defaultdict(list)
for g, items in groups.items():
    by_kind[(min(i['origin'] for i in items), *kind(items))].append(g)
assign = {}
for k, gs in sorted(by_kind.items()):
    origin = k[0]
    rng = rngs.setdefault(origin, random.Random(20261021 + origin))
    gs.sort()
    rng.shuffle(gs)
    n = len(gs)
    nt = max(1, round(n * 0.15))
    nv = max(1, round(n * 0.10))
    if n < 3:  # too few groups to hold anything out
        nt = nv = 0
    for i, g in enumerate(gs):
        assign[g] = 'test' if i < nt else ('valid' if i < nt + nv else 'train')
    print('src', origin, 'kind', k[1:], 'groups', n, 'test', nt, 'valid', nv)

if os.path.exists(DST):
    shutil.rmtree(DST)
counts = collections.Counter()
cls = collections.defaultdict(collections.Counter)
for g, items in groups.items():
    s = assign[g]
    for r in items:
        for sub in ('images', 'labels'):
            os.makedirs(f'{DST}/{s}/{sub}', exist_ok=True)
        shutil.copyfile(f"{r['src']}/{r['split']}/images/{r['file']}", f"{DST}/{s}/images/{r['file']}")
        with open(f"{DST}/{s}/labels/{r['stem']}.txt", 'w') as out:
            # keep plain boxes only (polygon rows made copy_paste a silent no-op)
            for c, x, y, w, h in r['rows']:
                out.write(f'{c} {x:.6f} {y:.6f} {w:.6f} {h:.6f}\n')
        counts[s] += 1
        for c, *_ in r['rows']:
            cls[s][c] += 1
print('images per split', dict(counts))
for s in ('train', 'valid', 'test'):
    print(s, 'red fives', {c: cls[s][c] for c in sorted(RED)}, 'backs', cls[s][BACK],
          'hand images', sum(1 for g, items in groups.items() if assign[g] == s for i in items if len(i['rows']) >= 12))

# Oversampled extra copies of rare classes for the improved recipe
extra = f'{DST}/train_extra'
for sub in ('images', 'labels'):
    os.makedirs(f'{extra}/{sub}', exist_ok=True)
n_extra = 0
for g, items in groups.items():
    if assign[g] != 'train':
        continue
    for r in items:
        cs = {c for c, *_ in r['rows']}
        reps = 2 if cs & RED else (1 if BACK in cs else 0)
        for k in range(reps):
            name = f"os{k}_{r['file']}"
            shutil.copyfile(f"{DST}/train/images/{r['file']}", f'{extra}/images/{name}')
            shutil.copyfile(f"{DST}/train/labels/{r['stem']}.txt", f"{extra}/labels/os{k}_{r['stem']}.txt")
            n_extra += 1
print('oversampled extra images', n_extra)
names = "['0b', '0m', '0p', '0s', '1m', '1p', '1s', '1z', '2m', '2p', '2s', '2z', '3m', '3p', '3s', '3z', '4m', '4p', '4s', '4z', '5m', '5p', '5s', '5z', '6m', '6p', '6s', '6z', '7m', '7p', '7s', '7z', '8m', '8p', '8s', '9m', '9p', '9s']"
for name, train in (('data_baseline.yaml', 'train/images'), ('data_improved.yaml', "[train/images, train_extra/images]")):
    with open(f'{DST}/{name}', 'w') as f:
        f.write(f'path: {DST}\ntrain: {train}\nval: valid/images\ntest: test/images\nnc: 38\nnames: {names}\n')

"""Behavior connection graphs and probability charts for the behavior document."""
import sys, json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.offsetbox import OffsetImage, AnnotationBbox
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from PIL import Image

_SHEET = {}
# The document numbers frames the way the original 62-frame art did (walk 4–11, then 62–69 for its second half).
# Those numbers are only labels here; each one is looked up by pose name in the sheet's `animations` table.
_LEGACY_POSES = [("stand", [0]), ("idle", [1, 2, 3]), ("walk", list(range(4, 12)) + list(range(62, 70))),
    ("run", list(range(12, 20))), ("turn", list(range(20, 24))), ("sitDown", [24, 25]), ("sit", [26]),
    ("loafDown", [27, 28]), ("loaf", [29]), ("sleepDown", [30, 31, 32]), ("sleep", [33, 34]),
    ("groom", list(range(35, 39))), ("stretch", list(range(39, 44))), ("yawn", [44, 45]), ("crouch", [46, 47]),
    ("creep", list(range(48, 52))), ("wiggle", [52, 53]), ("pounce", list(range(54, 58))), ("bat", [58, 59]), ("held", [60, 61])]
LEGACY = {n: (pose, step) for pose, ids in _LEGACY_POSES for step, n in enumerate(ids)}
def cell(i, density=None):
    """Metadata-sized cell from the native master or exact baked screen sheet."""
    if "meta" not in _SHEET:
        _SHEET["meta"] = json.load(open(f"{SRC_SHEET}/sheet.json"))
    m = _SHEET["meta"]
    key = "s" if density is None else f"{density}x-2"
    file = "sheet.png" if density is None else f"sheet-{key}.png"
    if key not in _SHEET: _SHEET[key] = Image.open(f"{SRC_SHEET}/{file}").convert("RGBA")
    w,h = (m["cellWidth"],m["cellHeight"]) if density is None else m["variants"][key]
    pose, step = LEGACY[i]
    i = m["animations"][pose][step]  # the sheet's own cell for this pose
    im = _SHEET[key].crop((i % 8*w,i//8*h,i%8*w+w,i//8*h+h))
    return im.resize((384,256),Image.Resampling.NEAREST) if density is None else im



SRC, OUT = sys.argv[1], sys.argv[2]
SRC_SHEET = SRC
font_manager.fontManager.addfont("/System/Library/Fonts/AppleSDGothicNeo.ttc")
plt.rcParams["font.family"] = "Apple SD Gothic Neo"
INK, MUTED, ACCENT, LINE = "#33291f", "#7a6d60", "#b45a14", "#c9b9a6"

# ---- probabilities, straight from Colony.choose
EDGES = [0, .22, .34, .44, .53, .58, .76, .85, .93, 1.01]
NAMES = ["잠", "앉기", "식빵", "그루밍", "기지개", "걷기", "달리기", "사냥", "공놀이"]
COLORS = ["#5b6c8f", "#9aa7b8", "#b8a58a", "#8fb3a0", "#d9b45b", "#e08a3c", "#c4512a", "#7d4e8f", "#3f8f8a"]

def dist(offset=0.0, waking=False):
    u = (np.arange(200000) + 0.5) / 200000
    r = np.clip(u + offset, 0, 0.999)
    out = {n: 0.0 for n in NAMES}
    if waking:
        out["기지개"] += float(np.mean(r < 0.65)); r = r[r >= 0.65]; scale = len(r) / len(u)
    else: scale = 1.0
    for k, n in enumerate(NAMES):
        if len(r): out[n] += float(np.mean((r >= EDGES[k]) & (r < EDGES[k + 1]))) * scale
    return out

def frame(i, height=None):
    im = cell(i)
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox())
    return np.asarray(im)

def thumb(ax, i, xy, zoom=0.22):
    ax.add_artist(AnnotationBbox(OffsetImage(frame(i), zoom=zoom), xy, frameon=False, zorder=3))

def node(ax, xy, title, sub=None, i=None, w=1.7, h=1.25, fill="#faf5ee", edge=LINE, zoom=0.2):
    x, y = xy
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.02,rounding_size=0.15",
                                fc=fill, ec=edge, lw=1.4, zorder=2))
    if i is not None: thumb(ax, i, (x, y + 0.12), zoom)
    ax.text(x, y - h / 2 + 0.2, title, ha="center", va="center", fontsize=10, color=INK, weight="bold", zorder=4)
    if sub: ax.text(x, y - h / 2 - 0.16, sub, ha="center", va="top", fontsize=7.5, color=MUTED, zorder=4)

def arrow(ax, a, b, label=None, style="-", color=ACCENT, rad=0.0, lw=1.6, shrink=34, fs=9, lpos=0.5, loff=(0, 0)):
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=13, lw=lw, color=color, linestyle=style,
                                 connectionstyle=f"arc3,rad={rad}", shrinkA=shrink, shrinkB=shrink, zorder=2.5))
    if label:
        x = a[0] + (b[0] - a[0]) * lpos + loff[0]; y = a[1] + (b[1] - a[1]) * lpos + loff[1]
        ax.text(x, y, label, ha="center", va="center", fontsize=fs, color=color, weight="bold", zorder=5,
                bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="none"))

def canvas(w, h, xlim, ylim):
    fig, ax = plt.subplots(figsize=(w, h), dpi=200)
    ax.set_xlim(*xlim); ax.set_ylim(*ylim); ax.set_aspect("equal"); ax.axis("off")
    return fig, ax

# ---- 1. hub: what comes next in normal mode
base = dist()
fig, ax = canvas(10, 8.6, (-6.2, 6.2), (-5.3, 5.3))
ax.add_patch(plt.Circle((0, 0), 1.25, fc="#fff3e6", ec=ACCENT, lw=2, zorder=2))
ax.text(0, 0.25, "다음 행동\n고르기", ha="center", va="center", fontsize=13, weight="bold", color=ACCENT, zorder=3)
ax.text(0, -0.55, "Normal · Full 기준", ha="center", va="center", fontsize=8, color=MUTED, zorder=3)
icons = {"잠": 33, "앉기": 26, "식빵": 29, "그루밍": 36, "기지개": 41, "걷기": 6, "달리기": 14, "사냥": 49, "공놀이": 58}
subs = {"잠": "18–63초", "앉기": "4–12초", "식빵": "8–20초", "그루밍": "4–9초", "기지개": "3.2초",
        "걷기": "도착까지 ≤14초", "달리기": "도착까지 ≤10초", "사냥": "≤15초", "공놀이": "10–18초"}
for k, n in enumerate(NAMES):
    ang = np.pi / 2 - k * 2 * np.pi / len(NAMES)
    xy = (4.0 * np.cos(ang), 4.0 * np.sin(ang))
    node(ax, xy, n, subs[n], icons[n])
    arrow(ax, (0, 0), xy, f"{base[n] * 100:.0f}%", shrink=40, lpos=0.42)
ax.text(0, -5.15, "가운데에서 화살표 % 확률로 행동을 고른다. 행동이 끝나면 다시 가운데로 돌아온다(예외는 다음 그림).",
        ha="center", fontsize=9, color=MUTED)
fig.savefig(f"{OUT}/graph-hub.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

# ---- 2. special routes that skip the hub
fig, ax = canvas(11, 7.4, (-0.6, 13.2), (-0.9, 8.4))
rows = [
    (7.3, [("잠 / 식빵", 33, None), ("기지개", 41, "65%"), ("다음 행동\n고르기", None, "끝나면")], "깨어날 때"),
    (5.2, [("걷기", 6, None), ("노치 옆 끝", 0, "25%*"), ("노치 건너기", 8, "도착"), ("반대편 걷기", 6, "")], "노치 터널"),
    (3.1, [("걷기", 6, None), ("쫓아가기", 15, "22%*"), ("다음 행동\n고르기", None, "4초")], "쫓아가기"),
    (1.0, [("사냥", 49, None), ("엉덩이 흔들기", 52, "도착"), ("덮치기", 56, "0.7–1.4초"), ("앉기 3–7초", 26, "100%")], "사냥"),
]
for y, chain, title in rows:
    ax.text(-0.5, y + 0.85, title, fontsize=10, weight="bold", color=ACCENT)
    xs = [1.4 + 3.3 * k for k in range(len(chain))]
    for k, (name, icon, label) in enumerate(chain):
        if icon is None:
            ax.add_patch(plt.Circle((xs[k], y), 0.62, fc="#fff3e6", ec=ACCENT, lw=1.5, zorder=2))
            ax.text(xs[k], y, name, ha="center", va="center", fontsize=8.5, weight="bold", color=ACCENT, zorder=3)
        else:
            node(ax, (xs[k], y), name, None, icon, w=2.2, h=1.45, zoom=0.17)
        if k: arrow(ax, (xs[k - 1] + 1.12, y), (xs[k] - 1.12, y), label, shrink=2, fs=8)
ax.text(-0.5, -0.65, "* 걷기로 정해졌을 때 추가로: 쫓아가기는 같은 구역에 걷는 친구가 있을 때, 노치 터널은 노치 바로 옆 구역일 때만.",
        fontsize=8.5, color=MUTED)
fig.savefig(f"{OUT}/graph-special.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

# ---- 3. people and the menu bar interrupt anything
fig, ax = canvas(11, 6.2, (-0.6, 13.2), (-0.6, 7.0))
rows = [
    (6.0, [("아무 행동", 0, None), ("들어 올리기", 60, "마우스 누름"), ("그루밍 2–4초", 36, "놓기")], "마우스"),
    (4.1, [("아무 행동", 0, None), ("집에 가기", 14, "Call home"), ("폴짝 0.55초", 55, "도착"), ("집 안", None, "")], "집으로 부르기"),
    (2.2, [("집 안", None, None), ("폴짝 나오기", 55, "Let out"), ("달리기 6초", 14, ""), ("다음 행동\n고르기", None, "")], "내보내기"),
    (0.3, [("아무 행동", 0, None), ("피하기", 14, "자리를 덮음"), ("앉기 1–3초", 26, "빈자리 도착"), ("공 버튼 →\n공놀이 14–22초", None, "")], "자동 반응"),
]
for y, chain, title in rows:
    ax.text(-0.5, y + 0.85, title, fontsize=10, weight="bold", color=ACCENT)
    xs = [1.4 + 3.3 * k for k in range(len(chain))]
    for k, (name, icon, label) in enumerate(chain):
        if icon is None:
            ax.add_patch(plt.Circle((xs[k], y), 0.66, fc="#fff3e6", ec=ACCENT, lw=1.5, zorder=2))
            ax.text(xs[k], y, name, ha="center", va="center", fontsize=8, weight="bold", color=ACCENT, zorder=3)
        else:
            node(ax, (xs[k], y), name, None, icon, w=2.2, h=1.45, zoom=0.17)
        if k and not (title == "자동 반응" and k == 3): arrow(ax, (xs[k - 1] + 1.12, y), (xs[k] - 1.12, y), label, shrink=2, fs=8)
fig.savefig(f"{OUT}/graph-interrupt.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

# ---- 4. probability bars under each setting
cases = [("보통 (Normal · Full)", 0.0, False), ("깨어날 때 (잠·식빵 뒤)", 0.0, True),
         ("Calm", -0.12, False), ("Playful", 0.12, False),
         ("Mac 한가함 (Full +0.08)", 0.08, False), ("Eco 절전", -0.15, False), ("Low 절전", -0.35, False)]
fig, ax = plt.subplots(figsize=(10, 4.6), dpi=200)
for row, (label, off, wake) in enumerate(cases):
    d = dist(off, wake); left = 0
    for k, n in enumerate(NAMES):
        v = d[n] * 100
        ax.barh(row, v, left=left, color=COLORS[k], edgecolor="white", height=0.7)
        if v >= 4: ax.text(left + v / 2, row, f"{v:.0f}", ha="center", va="center", fontsize=8, color="white", weight="bold")
        left += v
ax.set_yticks(range(len(cases))); ax.set_yticklabels([c[0] for c in cases], fontsize=9)
ax.invert_yaxis(); ax.set_xlim(0, 100); ax.set_xlabel("확률 (%)", fontsize=9)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.legend(handles=[plt.Rectangle((0, 0), 1, 1, color=c) for c in COLORS], labels=NAMES, ncol=9, fontsize=8,
          loc="upper center", bbox_to_anchor=(0.45, 1.13), frameon=False, handlelength=1)
fig.savefig(f"{OUT}/graph-probability.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

# ---- 5. rest ladder with the actual link art
fig, ax = canvas(12, 3.8, (-0.5, 17.1), (-1.6, 4.2))
hubs = [(0.8, 0, "서기", "rank 0"), (5.4, 26, "앉기", "rank 1"), (10.0, 29, "식빵", "rank 2"), (15.8, 33, "잠", "rank 3")]
links = [[24, 25], [27, 28], [30, 31, 32]]
for x, i, name, rank in hubs:
    node(ax, (x, 2.2), name, rank, i, w=1.9, h=1.7, fill="#fff3e6", edge=ACCENT, zoom=0.2)
for k in range(3):
    a, b = hubs[k][0], hubs[k + 1][0]
    n = len(links[k])
    for j, f in enumerate(links[k]):
        thumb(ax, f, (a + (b - a) * (j + 1) / (n + 1), 2.2), 0.13)
        ax.text(a + (b - a) * (j + 1) / (n + 1), 1.45, f"#{f}", ha="center", fontsize=7.5, color=MUTED)
    arrow(ax, (a, 3.15), (b, 3.15), "0.27초", rad=-0.12, shrink=50, lpos=0.5, loff=(0, 0.45))
    arrow(ax, (b, 1.05), (a, 1.05), "거꾸로", rad=-0.12, shrink=50, lpos=0.5, loff=(0, -0.45), color=MUTED)
ax.text(8, -1.35, "연결 그림은 장당 0.09초. 서기에서 잠까지 9장 0.81초, 잠에서 일어날 때는 같은 그림을 거꾸로.",
        ha="center", fontsize=9, color=MUTED)
fig.savefig(f"{OUT}/graph-rest.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

# ---- 6. frame-level links for movement: real link art vs 0.15 s crossfade
fig, ax = canvas(11, 6.4, (-0.6, 14.0), (-1.3, 7.0))
pos = {"서기": (1.2, 5.3, 0), "걷기": (5.6, 5.3, 6), "달리기": (10.0, 5.3, 14), "돌아서기": (5.6, 2.85, 21),
       "웅크림": (1.2, 0.4, 46), "낮게 걷기": (5.0, 0.4, 49), "덮치기": (8.8, 0.4, 56), "앉기": (12.6, 0.4, 26)}
for name, (x, y, i) in pos.items():
    node(ax, (x, y), name, None, i, w=2.0, h=1.5, zoom=0.16)
def P(n): return pos[n][:2]
arrow(ax, P("서기"), P("걷기"), "겹쳐 바꾸기", style="--", rad=0.15, shrink=42, fs=8)
arrow(ax, P("걷기"), P("서기"), "", style="--", rad=0.15, shrink=42)
arrow(ax, P("걷기"), P("달리기"), "겹쳐 바꾸기", style="--", rad=0.15, shrink=42, fs=8)
arrow(ax, P("달리기"), P("걷기"), "", style="--", rad=0.15, shrink=42)
arrow(ax, P("걷기"), P("돌아서기"), "20→23 · 0.36초", rad=0.25, shrink=42, fs=8, loff=(1.0, 0))
arrow(ax, P("돌아서기"), P("걷기"), "", rad=0.25, shrink=42)
arrow(ax, P("서기"), P("웅크림"), "겹쳐 바꾸기", style="--", shrink=42, fs=8)
arrow(ax, P("웅크림"), P("낮게 걷기"), "겹쳐 바꾸기", style="--", shrink=42, fs=8)
arrow(ax, P("낮게 걷기"), P("덮치기"), "겹쳐 바꾸기", style="--", shrink=42, fs=8)
arrow(ax, P("덮치기"), P("앉기"), "24→26 연결", shrink=42, fs=8)
ax.text(6.5, -0.95, "실선 = 전용 연결 그림이 있음   점선 = 연결 그림이 없어서 이전 자세를 0.15초 흐리게 겹침",
        ha="center", fontsize=9, color=MUTED)
fig.savefig(f"{OUT}/graph-motion.png", bbox_inches="tight", facecolor="white"); plt.close(fig)

json.dump({"base": base, "wake": dist(0, True), "cases": {c[0]: dist(c[1], c[2]) for c in cases}},
          open(f"{OUT}/probabilities.json", "w"), ensure_ascii=False, indent=1)
print("ok")

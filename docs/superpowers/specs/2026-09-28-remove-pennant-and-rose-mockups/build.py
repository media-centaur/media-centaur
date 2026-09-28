#!/usr/bin/env python3
"""Builds the round-1 mockups: the title modal with the act capsule.

Glyphs are the real heroicons (deps/heroicons), drawn as CSS masks over
the grade's background exactly as app.css draws `.act-icon`; the metals
and the brush are app.css's. Run from the repo root.
"""
import base64
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent
ICONS = ROOT / "deps/heroicons/optimized/24"

GLYPH = {
    "love": "heart",
    "like": "hand-thumb-up",
    "dislike": "hand-thumb-down",
    "review": "chat-bubble-bottom-center-text",
    "watched": "eye",
    "listing": "bookmark",
}


def mask(flag, weight):
    svg = (ICONS / weight / f"{GLYPH[flag]}.svg").read_bytes()
    return "data:image/svg+xml;base64," + base64.b64encode(svg).decode()


def glyph_css():
    rules = []
    for flag in GLYPH:
        for weight in ("outline", "solid"):
            rules.append(
                f'.g[data-flag="{flag}"][data-w="{weight}"]'
                f'{{-webkit-mask-image:url({mask(flag, weight)});mask-image:url({mask(flag, weight)})}}'
            )
    return "\n".join(rules)


def g(flag, grade, size=None):
    weight = "outline" if grade == "plain" else "solid"
    style = f' style="--glyph:{size}px"' if size else ""
    return f'<span class="g" data-flag="{flag}" data-w="{weight}" data-grade="{grade}"{style}></span>'


def tile(letter, hue, own=False):
    cls = "tile own" if own else "tile"
    return f'<span class="{cls}" style="--hue:{hue}">{letter}</span>'


BRUSH = (
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='128'%3E%3Cfilter id='n' x='0' y='0' width='100%25' height='100%25' color-interpolation-filters='sRGB'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.012 0.9' numOctaves='2' seed='7'/%3E%3CfeColorMatrix type='matrix' values='.33 .33 .33 0 0 .33 .33 .33 0 0 .33 .33 .33 0 0 0 0 0 0 1'/%3E%3CfeComponentTransfer%3E%3CfeFuncR type='linear' slope='0.8' intercept='0.100'/%3E%3CfeFuncG type='linear' slope='0.8' intercept='0.100'/%3E%3CfeFuncB type='linear' slope='0.8' intercept='0.100'/%3E%3C/feComponentTransfer%3E%3C/filter%3E%3Cg transform='rotate(-45 64 64)'%3E%3Crect x='-64' y='-64' width='256' height='256' filter='url(%23n)'/%3E%3C/g%3E%3C/svg%3E\")"
)

CSS = """
:root{--bc:oklch(93% 0.01 264);--p:oklch(62% 0.16 250);--hair:oklch(93% 0.01 264/.08);--person-l:70%;--person-c:.15}
*{box-sizing:border-box}
html,body{margin:0}
body{color:var(--bc);font:14px/1.45 system-ui,sans-serif;background:oklch(9% 0.015 264);padding:40px 0}
.label{width:1000px;margin:0 auto 12px;font-size:15px;color:oklch(93% 0.01 264/.75)}
.label b{color:var(--bc)}
.stage{position:relative;width:1000px;margin:0 auto 64px}
.panel{position:relative;border-radius:12px;overflow:hidden;background:oklch(16% 0.018 264);box-shadow:0 20px 60px oklch(0% 0 0/.6);border:1px solid oklch(90% 0.005 264/.09)}
.hero{position:relative;aspect-ratio:21/9;background:center/cover no-repeat}
.hero::after{content:"";position:absolute;inset:0;background:linear-gradient(to bottom,transparent 45%,oklch(16% 0.018 264) 100%),linear-gradient(to right,oklch(10% 0.02 264/.55),transparent 55%)}
.orient{position:relative;z-index:2;margin-top:-120px;padding:0 24px}
.title{font:700 38px/1.1 Georgia,serif;text-shadow:0 2px 12px oklch(0% 0 0/.7);margin:0}
.tagline{font-style:italic;color:oklch(93% 0.01 264/.75);margin:6px 0 18px}
.meta{display:flex;gap:10px;align-items:center;color:oklch(93% 0.01 264/.75);margin-bottom:14px}
.type{border:1px solid oklch(93% 0.01 264/.35);border-radius:6px;padding:0 8px;font-size:13px}
.actions{display:flex;gap:14px;align-items:center;margin-bottom:14px}
.btn{background:var(--p);color:white;font-weight:600;border-radius:6px;padding:8px 16px}
.ico{width:22px;height:22px;background:oklch(72% 0.14 250);-webkit-mask:center/contain no-repeat;mask:center/contain no-repeat}
.prose{color:oklch(93% 0.01 264/.75);font-size:15px;line-height:1.6;max-width:760px}
.body{padding:18px 24px 28px;margin-top:18px;border-top:1px solid var(--hair);color:oklch(93% 0.01 264/.6)}

/* the act glyph, as app.css draws it */
.g{display:block;width:var(--glyph,22px);height:var(--glyph,22px);background-color:oklch(100% 0 0/.72);
 -webkit-mask-size:100% 100%;mask-size:100% 100%;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat}
.g[data-grade=silver],.g[data-grade=gold]{background-image:BRUSH,var(--metal);background-size:128px 128px,100% 100%;background-position:center;background-repeat:no-repeat;background-blend-mode:overlay,normal}
.g[data-grade=silver]{--metal:linear-gradient(135deg,oklch(91% 0.007 250),oklch(56% 0.018 250) 55%,oklch(80% 0.012 250))}
.g[data-grade=gold]{--metal:linear-gradient(135deg,oklch(84% 0.15 86),oklch(62% 0.13 86) 55%,oklch(78% 0.161 86))}
.g.inline{display:inline-block;vertical-align:-3px;--glyph:17px}

/* the act capsule: ink pill, upper right, below the panel's corner */
.capsule{position:absolute;top:12px;right:12px;z-index:5;display:flex;gap:12px;align-items:center;padding:9px 14px;border-radius:999px;
 background:oklch(12% 0.015 264/.82);box-shadow:inset 0 0 0 1px oklch(100% 0 0/.12),0 4px 16px oklch(0% 0 0/.45);backdrop-filter:blur(12px)}
.capsule .g{--glyph:24px}
.capsule.pressable{cursor:pointer}
.capsule.open{box-shadow:inset 0 0 0 1px oklch(100% 0 0/.22),0 4px 16px oklch(0% 0 0/.45)}
.chev{width:12px;height:12px;margin-left:-4px;background:oklch(100% 0 0/.55);-webkit-mask:center/contain no-repeat;mask:center/contain no-repeat}

/* the reviews panel, anchored under the capsule — the glass menu's surface */
.reviews{position:absolute;top:62px;right:12px;z-index:6;width:420px;max-height:460px;overflow:auto;padding:6px;border-radius:12px;
 background:oklch(15% 0.016 264/.94);box-shadow:inset 0 0 0 1px oklch(100% 0 0/.1),0 12px 40px oklch(0% 0 0/.6);backdrop-filter:blur(16px)}
.rv{display:flex;gap:12px;padding:12px;border-radius:8px}
.rv+.rv{border-top:1px solid var(--hair)}
.rv .who{display:flex;align-items:center;gap:8px;font-size:15px;line-height:22px}
.rv .who b{font-weight:600}
.rv .ago{margin-left:auto;font-size:13px;color:oklch(93% 0.01 264/.6)}
.rv .txt{margin-top:2px;font-size:14px;line-height:21px;color:oklch(93% 0.01 264/.8)}
.rv .main{flex:1;min-width:0}
.acts{padding:10px 12px 8px;border-top:1px solid var(--hair);display:grid;gap:8px}
.acts div{display:flex;align-items:center;gap:10px;font-size:14px;color:oklch(93% 0.01 264/.8)}
.tile{flex:none;width:32px;height:32px;border-radius:99px;display:grid;place-items:center;font-weight:600;font-size:14px;
 background:oklch(var(--person-l) var(--person-c) var(--hue)/.2);color:oklch(var(--person-l) var(--person-c) var(--hue));
 box-shadow:inset 0 0 0 1px oklch(var(--person-l) var(--person-c) var(--hue)/.25)}
.tile.own{background:oklch(var(--person-l) var(--person-c) var(--hue));color:oklch(97% 0.01 var(--hue))}

/* the lead review: opened from a review, its words lead the prose */
.lead{display:flex;gap:10px;align-items:flex-start;margin-bottom:10px;max-width:760px}
.lead .tile{width:28px;height:28px;font-size:13px;margin-top:1px}
.lead p{margin:0;font-size:15px;line-height:1.55;color:oklch(93% 0.01 264/.85)}
.lead b{font-weight:600;color:var(--bc)}
""".replace("BRUSH", BRUSH)


def icon(name, weight="outline", cls="ico"):
    svg = (ICONS / weight / f"{name}.svg").read_bytes()
    uri = "data:image/svg+xml;base64," + base64.b64encode(svg).decode()
    return f'<span class="{cls}" style="-webkit-mask-image:url({uri});mask-image:url({uri})"></span>'


def modal(capsule, overlay="", lead=""):
    return f"""
<div class="stage">
  {capsule}
  {overlay}
  <div class="panel">
    <div class="hero" style="background-image:url(art/charade-backdrop.jpg)"></div>
    <div class="orient">
      <h2 class="title">Charade</h2>
      <div class="tagline">A comedy thriller with a twist.</div>
      <div class="meta"><span class="type">Movie</span>1963 · 1h 53m</div>
      <div class="actions"><span class="btn">Download ▾</span>{icon("link")}{icon("bookmark", "solid")}{icon("pencil-square")}</div>
      {lead}
      <div class="prose">After her husband is murdered for a fortune he stole, a widow is pursued across Paris by his former partners — and by a charming stranger whose name keeps changing.</div>
    </div>
    <div class="body">Tracking card · Refresh from TMDB</div>
  </div>
</div>"""


def capsule(flags, pressable=False, open_=False):
    cls = "capsule" + (" pressable" if pressable else "") + (" open" if open_ else "")
    chev = icon("chevron-up" if open_ else "chevron-down", "outline", "chev") if pressable else ""
    return f'<div class="{cls}">{"".join(g(f, gr) for f, gr in flags)}{chev}</div>'


FLAGS = [("love", "silver"), ("like", "plain"), ("watched", "gold"), ("listing", "plain")]

REVIEWS = f"""
<div class="reviews">
  <div class="rv">{tile("N", 30)}<div class="main"><div class="who"><b>Nick</b>{g("love", "silver", 17)}<span class="ago">2d ago</span></div>
    <div class="txt">Watch it before anyone spoils the ending. The staircase scene alone is worth it.</div></div></div>
  <div class="rv">{tile("Y", 250, own=True)}<div class="main"><div class="who"><b>You</b>{g("love", "silver", 17)}<span class="ago">1w ago</span></div>
    <div class="txt">Best thing Hepburn and Grant did together.</div></div></div>
  <div class="rv">{tile("S", 150)}<div class="main"><div class="who"><b>Sam</b>{g("like", "plain", 17)}<span class="ago">3w ago</span></div></div></div>
  ACTS
</div>"""

ACTS = f"""<div class="acts">
    <div>{g("watched", "gold", 17)}<span>Nick, Sam and you watched this</span></div>
    <div>{g("listing", "plain", 17)}<span>Cleo wants to watch this</span></div>
  </div>"""

LEAD = f"""<div class="lead">{tile("N", 30)}<p><b>Nick</b> {g("love", "silver", 17).replace('class="g"', 'class="g inline"')} Watch it before anyone spoils the ending. The staircase scene alone is worth it.</p></div>"""

PAGES = {
    "1-at-rest": [
        ("<b>1 · At rest</b>, opened from Library. The capsule is the title's act group at its grades: love silver (two), like plain (one), watched gold (three), listing plain. Pressable because reviews carry text (the chevron says it opens).",
         modal(capsule(FLAGS, pressable=True))),
        ("<b>1b · No review text.</b> The same acts, but nobody wrote words: the capsule is a display, no chevron, not a nav item.",
         modal(capsule(FLAGS))),
    ],
    "2-open": [
        ("<b>2a · Open, reviews only.</b> The glass panel under the capsule: one entry per review, newest first — tile, name, sentiment at its grade, the time, the text. A review with no words is the line alone (Sam).",
         modal(capsule(FLAGS, pressable=True, open_=True), REVIEWS.replace("ACTS", ""))),
        ("<b>2b · Open, reviews then acts.</b> The same, with one sentence per text-less flag under a hairline — who watched, who wants to watch. The gamepad's way to see who.",
         modal(capsule(FLAGS, pressable=True, open_=True), REVIEWS.replace("ACTS", ACTS))),
    ],
    "3-from-review": [
        ("<b>3 · Opened from Nick's review</b> (a Feed row or his card). His words lead the prose as today — now with his tile and the sentiment glyph — and the capsule still opens the rest.",
         modal(capsule(FLAGS, pressable=True), lead=LEAD)),
    ],
}


def page(title, sections):
    body = "\n".join(f'<div class="label">{label}</div>{html}' for label, html in sections)
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<style>{CSS}
{glyph_css()}</style></head><body>{body}</body></html>"""


for name, sections in PAGES.items():
    (OUT / f"{name}.html").write_text(page(name, sections))
    print("wrote", name)

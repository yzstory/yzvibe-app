#!/usr/bin/env python3
"""YzVibe 设计画布生成器：把共享样式 + 各屏 body 组装为 .dc.html 画板。
运行：python3 build.py  → 在同目录输出 *.dc.html 与 canvas.json

颜色与材质已同步到方向 B「焦橙纸感」（docs/DESIGN.md）。
注意：各屏的导航条 / 大标题 / 新建按钮仍是画稿时期的自绘版式；实现里这些已经换成
系统的 NavigationStack + navigationTitle + toolbar，以 DESIGN.md §5 和 iOS 代码为准。"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))

# ───────────── 图标（stroke SVG，24 网格） ─────────────
def ic(name, size=20, color="currentColor", sw=1.8):
    P = {
     "qr": '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M14 14h3v3h-3zM20 14v1M14 20h1M20 20h1M17.5 17.5h.01"/>',
     "plus": '<path d="M12 5v14M5 12h14"/>',
     "back": '<path d="M15 5l-7 7 7 7"/>',
     "chev": '<path d="M9 5l7 7-7 7"/>',
     "down": '<path d="M6 9l6 6 6-6"/>',
     "search": '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
     "gear": '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
     "folder": '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
     "up": '<path d="M12 19V5M5 12l7-7 7 7"/>',
     "camera": '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
     "stop": '<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
     "zap": '<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
     "file": '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
     "image": '<rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/>',
     "check": '<path d="M5 12l5 5 9-10"/>',
     "x": '<path d="M6 6l12 12M18 6L6 18"/>',
     "shield": '<path d="M12 3l8 3v6c0 4.5-3.5 7.8-8 9-4.5-1.2-8-4.5-8-9V6z"/>',
     "monitor": '<rect x="3" y="4" width="18" height="12" rx="2.5"/><path d="M8 20h8M12 16v4"/>',
     "phone": '<rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/>',
     "wifi": '<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M2 9a14 14 0 0 1 20 0"/><circle cx="12" cy="19.5" r="1"/>',
     "bell": '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>',
     "moon": '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
     "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
     "lock": '<rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
     "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
     "copy": '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
     "clip": '<path d="M21 11.5l-8.5 8.5a5 5 0 0 1-7-7l9-9a3.5 3.5 0 0 1 5 5l-9 9a2 2 0 0 1-3-3l8-8"/>',
     "more": '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
     "terminal": '<path d="M5 7l5 5-5 5M12 17h7"/>',
     "chat": '<path d="M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 4z"/>',
     "inbox": '<path d="M4 13l2.5-8h11L20 13v6H4z"/><path d="M4 13h5l1.5 2.5h3L15 13h5"/>',
     "user": '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
     "link": '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
     "download": '<path d="M12 4v12M6 11l6 6 6-6M4 20h16"/>',
     "markdown": '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M6 15V9l3 3 3-3v6M16 9v6M14 13l2 2 2-2"/>',
     "pen": '<path d="M4 20l4-1L19 8l-3-3L5 16z"/>',
     "cpu": '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
     "refresh": '<path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5"/>',
     "sparkle": '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
     "trash": '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
     "faceid": '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M9 9v1M15 9v1M12 9v4h-1M9 15a4 4 0 0 0 6 0"/>',
    }
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0">{P[name]}</svg>')

# ───────────── 共享样式 ─────────────
LIGHT = """
  --brand: #C75015; --brand-soft: #FFE5D8; --brand-ink: #FFFFFF; --brand-text: #A63D02;
  --sage: #1B7046; --sage-soft: #E0F1E7;
  --amber: #B0761A; --amber-text: #8A5A0E; --amber-soft: #FBEFD6;
  --danger: #C4261C; --danger-soft: #FBE3E0;
  --purple: #6E4B9E; --purple-soft: #EFE8F7;
  --blue: #1F6FA8; --blue-soft: #E3EFF8;
  --surface: #F9F6F2; --elev: #FFFDFA;
  --fill: #EFEAE2; --fill2: #F4F0E9;
  --border: #E6DFD5;
  --label: #231813; --label2: #6D6059; --label3: #877E78;
  --glass-bg: rgba(255,253,250,0.72); --glass-hi: rgba(255,255,255,0.5); --glass-hi2: rgba(255,255,255,0.2);
  --shadow-card: 0 1px 2px rgba(80,67,47,0.04);
  --shadow-glass: 0 0 0 0.5px rgba(80,67,47,0.10), 0 8px 24px rgba(80,67,47,0.10);
  --shadow-float: 0 2px 8px rgba(80,67,47,0.08), 0 12px 30px rgba(80,67,47,0.12);
  --orb-alpha: 0;
"""
DARK = """
  --brand: #FF9868; --brand-soft: #3A2A22; --brand-ink: #241812; --brand-text: #FFB08A;
  --sage: #5FD08E; --sage-soft: #23382D;
  --amber: #E8B45C; --amber-text: #E8B45C; --amber-soft: #3A3020;
  --danger: #FF6961; --danger-soft: #3A2422;
  --purple: #C09AE8; --purple-soft: #2F2838;
  --blue: #6FB6E8; --blue-soft: #22303A;
  --surface: #201E1B; --elev: #2C2A27;
  --fill: #383530; --fill2: #322F2B;
  --border: rgba(255,255,255,0.12);
  --label: #F5F2EE; --label2: #B5AEA6; --label3: #8A837B;
  --glass-bg: rgba(44,42,39,0.72); --glass-hi: rgba(255,255,255,0.10); --glass-hi2: rgba(255,255,255,0.06);
  --shadow-card: 0 1px 2px rgba(0,0,0,0.30);
  --shadow-glass: 0 0 0 0.5px rgba(0,0,0,0.4), 0 8px 24px rgba(0,0,0,0.45);
  --shadow-float: 0 2px 8px rgba(0,0,0,0.35), 0 12px 30px rgba(0,0,0,0.5);
  --orb-alpha: 0;
"""
CSS = """
  * { box-sizing: border-box; }
  body { margin: 0; background: transparent; }
  a { color: var(--brand); } a:hover { color: var(--brand-text); }
  .phone { position: relative; width: 390px; height: 844px; overflow: hidden; background: var(--surface); color: var(--label);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", "Noto Sans CJK SC", sans-serif;
    -webkit-font-smoothing: antialiased; font-size: 17px; line-height: 1.35; letter-spacing: -0.01em; }
  .paper { background-image: radial-gradient(oklch(0.5 0.03 60 / 0.035) 0.5px, transparent 0.5px); background-size: 6px 6px; }
  .orb { display: none; }   /* 方向 B 取消背景装饰球 */
  .mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; letter-spacing: 0; }
  .glass { background: var(--glass-bg); -webkit-backdrop-filter: blur(24px) saturate(180%); backdrop-filter: blur(24px) saturate(180%);
    box-shadow: inset 0 0 0 0.5px var(--border), var(--shadow-glass); }
  .glass-brand { background: color-mix(in srgb, var(--brand) 82%, transparent); color: var(--brand-ink);
    -webkit-backdrop-filter: blur(16px) saturate(160%); backdrop-filter: blur(16px) saturate(160%);
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.45), 0 8px 24px color-mix(in srgb, var(--brand) 35%, transparent);
    background-image: linear-gradient(135deg, rgba(255,255,255,0.28), transparent 50%); }
  .card { background: var(--elev); border-radius: 16px; border: 1px solid var(--border); box-shadow: var(--shadow-card); }
  .eyebrow { font-size: 12px; font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; color: var(--label2); }
  .large-title { font-size: 34px; font-weight: 700; letter-spacing: -0.025em; line-height: 1.15; }
  .title1 { font-size: 28px; font-weight: 700; letter-spacing: -0.015em; line-height: 1.2; }
  .title2 { font-size: 22px; font-weight: 600; letter-spacing: -0.01em; line-height: 1.25; }
  .headline { font-size: 17px; font-weight: 600; }
  .body { font-size: 17px; }
  .subhead { font-size: 15px; }
  .footnote { font-size: 13px; }
  .caption { font-size: 12px; }
  .l2 { color: var(--label2); } .l3 { color: var(--label3); }
  .chip { display: inline-flex; align-items: center; gap: 6px; height: 28px; padding: 0 11px; border-radius: 999px; font-size: 13px; font-weight: 600; white-space: nowrap; }
  .chip-claude { background: var(--brand-soft); color: var(--brand-text); }
  .chip-codex { background: var(--fill); color: var(--label2); }
  .chip-custom { background: var(--fill); color: var(--label2); }
  .chip-sage { background: var(--sage-soft); color: var(--sage); }
  .chip-brand { background: var(--brand-soft); color: var(--brand-text); }
  .chip-fill { background: var(--fill); color: var(--label2); }
  .chip-danger { background: var(--danger-soft); color: var(--danger); }
  .dot { width: 9px; height: 9px; border-radius: 999px; flex-shrink: 0; }
  .dot-sage { background: var(--sage); box-shadow: 0 0 0 3px color-mix(in srgb, var(--sage) 22%, transparent); }
  .dot-amber { background: var(--brand); box-shadow: 0 0 0 3px color-mix(in srgb, var(--brand) 22%, transparent); }
  .dot-danger { background: var(--danger); box-shadow: 0 0 0 3px color-mix(in srgb, var(--danger) 22%, transparent); }
  .dot-off { background: var(--label3); }
  .btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; height: 50px; padding: 0 20px; border-radius: 999px; font-size: 16px; font-weight: 600; border: none; }
  .btn-primary { background: var(--brand); color: var(--brand-ink); }
  .btn-secondary { background: var(--fill); color: var(--label); }
  .btn-outline { background: transparent; color: var(--label); box-shadow: inset 0 0 0 1.5px var(--border); }
  .btn-danger-outline { background: transparent; color: var(--danger); box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--danger) 55%, transparent); }
  .input { display: flex; align-items: center; gap: 10px; height: 52px; padding: 0 16px; border-radius: 16px; background: var(--fill); color: var(--label); box-shadow: inset 0 0 0 1px var(--border); font-size: 16px; }
  .icon-btn { width: 44px; height: 44px; border-radius: 999px; display: flex; align-items: center; justify-content: center; }
  .navbar { position: absolute; left: 16px; right: 16px; top: 62px; height: 56px; border-radius: 999px; display: flex; align-items: center; gap: 8px; padding: 0 6px 0 6px; z-index: 5; }
  /* 系统 Tab 栏：贴底通栏 + 顶部发丝线，不再是悬浮胶囊 */
  .tabbar { position: absolute; left: 0; right: 0; bottom: 0; height: 78px; display: flex; align-items: flex-start; justify-content: space-around; padding: 8px 6px 0; z-index: 5; border-top: 1px solid var(--border); }
  .tab { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; width: 72px; height: 54px; border-radius: 999px; color: var(--label2); font-size: 11px; font-weight: 600; position: relative; }
  .tab-on { color: var(--brand); }
  .badge { position: absolute; top: 0; right: 16px; min-width: 17px; height: 17px; padding: 0 5px; border-radius: 999px; background: var(--danger); color: #fff; font-size: 11px; font-weight: 700; display: flex; align-items: center; justify-content: center; }
  .toggle { width: 51px; height: 31px; border-radius: 999px; background: var(--brand); position: relative; flex-shrink: 0; }
  .toggle::after { content: ""; position: absolute; top: 2px; left: 22px; width: 27px; height: 27px; border-radius: 999px; background: white; box-shadow: 0 3px 8px rgba(0,0,0,0.15); }
  .toggle-off { background: var(--fill); box-shadow: inset 0 0 0 1px var(--border); }
  .toggle-off::after { left: 2px; }
  .row { display: flex; align-items: center; gap: 12px; min-height: 56px; padding: 0 18px; }
  .sep { height: 1px; background: var(--border); margin: 0 18px; }
  .code { background: var(--fill2); border-radius: 12px; padding: 10px 12px; font-size: 13px; line-height: 1.5; color: var(--label2); box-shadow: inset 0 0 0 1px var(--border); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .scroll { position: absolute; left: 0; right: 0; top: 0; bottom: 0; overflow: hidden; }
"""

def orbs():
    return ('<div class="orb" style="width:360px;height:360px;left:-120px;top:-140px;background:var(--brand-soft)"></div>'
            '<div class="orb" style="width:300px;height:300px;right:-130px;top:-40px;background:var(--amber-soft)"></div>'
            '<div class="orb" style="width:420px;height:420px;left:-15px;bottom:-260px;background:var(--sage-soft)"></div>')

def tabbar(active):
    items = [("devices","monitor","设备"),("sessions","chat","会话"),("approvals","inbox","审批"),("me","user","我")]
    out = []
    for key, icon, label in items:
        on = " tab-on" if key == active else ""
        badge = '<div class="badge">2</div>' if key == "approvals" and active != "approvals" else ""
        out.append(f'<div class="tab{on}">{ic(icon, 22)}<span>{label}</span>{badge}</div>')
    return f'<div class="tabbar glass">{"".join(out)}</div>'

def navbar(title, right="", back=True, sub=""):
    left = f'<div class="icon-btn" style="background:var(--fill)">{ic("back",20)}</div>' if back else '<div style="width:10px"></div>'
    subhtml = f'<div class="caption l2" style="margin-top:1px">{sub}</div>' if sub else ""
    return (f'<div class="navbar glass">{left}'
            f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;padding-left:{"2" if back else "14"}px">'
            f'<div class="headline" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{title}</div>{subhtml}</div>{right}</div>')

def phone(inner, dark=False, extra_class=""):
    vars_ = DARK if dark else LIGHT
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
  :root {{ {vars_} }}
  {CSS}
  </style>
</helmet>
<div class="phone paper {extra_class}">
{orbs()}
{inner}
</div>
</x-dc>
</body>
</html>
"""

# ───────────── 各屏 ─────────────
def device_card(name, host, mode, mode_cls, online, sessions, agent_chips):
    dot = "dot-sage" if online else "dot-off"
    status = '<span class="chip chip-sage">在线</span>' if online else '<span class="chip chip-fill">离线 · 2 小时前</span>'
    return f"""
<div class="card" style="padding:18px 18px 16px;display:flex;flex-direction:column;gap:14px">
  <div style="display:flex;align-items:center;gap:12px">
    <div style="width:44px;height:44px;border-radius:14px;background:var(--fill);display:flex;align-items:center;justify-content:center;color:var(--label2)">{ic("monitor",22)}</div>
    <div style="flex:1;min-width:0">
      <div style="display:flex;align-items:center;gap:8px"><div class="dot {dot}"></div><div class="title2" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{name}</div></div>
      <div class="footnote mono l2" style="margin-top:2px">{host}</div>
    </div>
    {ic("chev",20,"var(--label3)")}
  </div>
  <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
    <span class="chip {mode_cls}">{mode}</span>{status}{agent_chips}
    <span class="footnote l2" style="margin-left:auto">{sessions} 个会话</span>
  </div>
</div>"""

DEVICES = f"""
<div class="scroll">
  <div style="position:absolute;left:20px;right:20px;top:70px">
    <div class="eyebrow" style="color:var(--brand)">YzVibe</div>
    <div class="large-title" style="margin-top:6px">设备</div>
    <div class="subhead l2" style="margin-top:6px">已配对的电脑保存在本机，离开桌面也能一键重连。</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:196px;display:flex;flex-direction:column;gap:14px">
    {device_card("Yuki 的 Mac Studio","100.82.203.14:9876","Tailscale","chip-custom",True,3,'<span class="chip chip-claude">Claude · 2</span>')}
    {device_card("MacBook Pro 16","tunnel · xxx.trycloudflare.com","Cloudflare Tunnel","chip-brand",True,1,'<span class="chip chip-claude">Claude · 1</span>')}
    {device_card("公司 Mac mini","192.168.3.21:9876","局域网","chip-sage",False,0,'')}
  </div>
  <div style="position:absolute;left:20px;right:20px;bottom:104px;display:flex;gap:10px">
    <div class="btn btn-primary" style="flex:1.4">{ic("qr",20)}扫码配对</div>
    <div class="btn glass" style="flex:1;color:var(--label)">{ic("pen",18)}手动添加</div>
  </div>
</div>
{tabbar("devices")}
"""

PAIR = f"""
<div style="position:absolute;inset:0;background:oklch(0.18 0.01 50)"></div>
<div style="position:absolute;inset:0;background:radial-gradient(ellipse at 50% 42%, oklch(0.36 0.02 55) 0%, oklch(0.16 0.01 50) 70%)"></div>
<div style="position:absolute;left:0;right:0;top:0;height:844px;background-image:repeating-linear-gradient(0deg, rgba(255,255,255,0.025) 0 1px, transparent 1px 28px), repeating-linear-gradient(90deg, rgba(255,255,255,0.025) 0 1px, transparent 1px 28px)"></div>
<div class="navbar glass" style="--glass-bg:oklch(0.3 0.01 60 / 0.5);--glass-hi:rgba(255,255,255,0.18);--glass-hi2:rgba(255,255,255,0.08);color:white">
  <div class="icon-btn" style="background:rgba(255,255,255,0.12)">{ic("x",20,"white")}</div>
  <div class="headline" style="flex:1;padding-left:2px">扫码配对</div>
  <div class="icon-btn" style="background:rgba(255,255,255,0.12)">{ic("image",20,"white")}</div>
</div>
<div style="position:absolute;left:65px;top:262px;width:260px;height:260px;border-radius:32px;background:rgba(255,255,255,0.06);-webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px);box-shadow:inset 0 1px 0 rgba(255,255,255,0.3),inset 0 0 0 1px rgba(255,255,255,0.14), 0 0 0 999px rgba(0,0,0,0.28)"></div>
<svg width="260" height="260" viewBox="0 0 260 260" fill="none" stroke="var(--brand)" stroke-width="5" stroke-linecap="round" style="position:absolute;left:65px;top:262px">
  <path d="M8 44V28a20 20 0 0 1 20-20h16M216 8h16a20 20 0 0 1 20 20v16M252 216v16a20 20 0 0 1-20 20h-16M44 252H28a20 20 0 0 1-20-20v-16"/>
</svg>
<div style="position:absolute;left:80px;right:80px;top:388px;height:2px;background:linear-gradient(90deg, transparent, var(--brand), transparent);opacity:0.9"></div>
<div style="position:absolute;left:32px;right:32px;top:560px;text-align:center;color:rgba(255,255,255,0.86)">
  <div class="headline">对准终端里的二维码</div>
  <div class="subhead" style="margin-top:6px;color:rgba(255,255,255,0.6)">在电脑上运行下面命令后，扫一次即可完成配对</div>
</div>
<div class="mono glass" style="position:absolute;left:44px;right:44px;top:648px;height:48px;border-radius:14px;display:flex;align-items:center;justify-content:center;gap:10px;color:white;--glass-bg:oklch(0.3 0.01 60 / 0.55);--glass-hi:rgba(255,255,255,0.18);--glass-hi2:rgba(255,255,255,0.06);font-size:15px">{ic("terminal",18,"var(--amber)")}npx yzvibe</div>
<div style="position:absolute;left:20px;right:20px;bottom:36px;display:flex;gap:10px">
  <div class="btn glass" style="flex:1;color:white;--glass-bg:oklch(0.3 0.01 60 / 0.55);--glass-hi:rgba(255,255,255,0.18);--glass-hi2:rgba(255,255,255,0.06)">{ic("pen",18,"white")}手动输入 Host / Token</div>
</div>
"""

def session_card(agent, agent_cls, title, path, when, dot, extra=""):
    return f"""
<div class="card" style="padding:16px 18px;display:flex;flex-direction:column;gap:10px">
  <div style="display:flex;align-items:center;gap:8px">
    <div class="dot {dot}"></div>
    <span class="chip {agent_cls}">{agent}</span>{extra}
    <span class="footnote l3" style="margin-left:auto">{when}</span>
  </div>
  <div class="headline" style="font-size:18px">{title}</div>
  <div class="code mono">{path}</div>
</div>"""

SESSIONS = f"""
<div class="scroll">
  <div style="position:absolute;left:20px;right:20px;top:70px;display:flex;align-items:flex-end;justify-content:space-between">
    <div>
      <div class="eyebrow" style="color:var(--brand)">Yuki 的 Mac Studio</div>
      <div class="large-title" style="margin-top:6px">会话</div>
    </div>
    <div class="chip glass" style="height:36px;padding:0 12px 0 10px;gap:6px;color:var(--label)"><div class="dot dot-sage"></div>已连接 {ic("down",16,"var(--label2)")}</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:150px;display:flex;gap:10px">
    <div class="input" style="flex:1;height:46px;border-radius:999px;color:var(--label3)">{ic("search",18,"var(--label3)")}搜索会话或路径</div>
    <div class="chip chip-brand" style="height:46px;padding:0 14px">仅活跃</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:216px;display:flex;flex-direction:column;gap:12px">
    <div style="display:flex;align-items:center;gap:8px;padding:0 4px">
      {ic("down",16,"var(--label2)")}{ic("folder",18,"var(--label2)")}
      <div class="headline" style="font-size:16px">yukiTrace</div>
      <div class="footnote mono l3" style="flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">~/devops/aigc/yukiTrace</div>
      <div class="footnote l2">2 个</div>
    </div>
    {session_card("Claude","chip-claude","重构地图标记组件并补测试","~/devops/aigc/yukiTrace","运行中 · 3 分钟","dot-amber",'<span class="chip chip-danger">1 待审批</span>')}
    {session_card("Codex","chip-codex","修复 iOS Safari 日期输入溢出","~/devops/aigc/yukiTrace","空闲 · 26 分钟","dot-sage")}
    <div style="display:flex;align-items:center;gap:8px;padding:6px 4px 0">
      {ic("chev",16,"var(--label2)")}{ic("folder",18,"var(--label2)")}
      <div class="headline" style="font-size:16px">YzVibe</div>
      <div class="footnote mono l3" style="flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">~/devops/aigc/YzVibe</div>
      <div class="footnote l2">1 个</div>
    </div>
  </div>
  <div class="btn btn-primary" style="position:absolute;right:20px;bottom:104px;height:56px;padding:0 22px 0 18px;box-shadow:var(--shadow-float)">{ic("plus",22)}新建会话</div>
</div>
{tabbar("sessions")}
"""

def seg(items, active, cls_on="chip-brand"):
    cells = []
    for it in items:
        if it == active:
            cells.append(f'<div style="flex:1;height:40px;border-radius:999px;background:var(--brand-soft);color:var(--brand);box-shadow:inset 0 0 0 1.5px var(--brand);display:flex;align-items:center;justify-content:center;font-weight:600;font-size:15px">{it}</div>')
        else:
            cells.append(f'<div style="flex:1;height:40px;border-radius:999px;display:flex;align-items:center;justify-content:center;font-weight:600;font-size:15px;color:var(--label2)">{it}</div>')
    return f'<div style="display:flex;gap:4px;padding:4px;border-radius:999px;background:var(--fill);box-shadow:inset 0 0 0 1px var(--border)">{"".join(cells)}</div>'

NEWSESSION = f"""
<div style="position:absolute;inset:0;background:oklch(0.3 0.03 50 / 0.28)"></div>
<div style="position:absolute;left:0;right:0;top:64px;bottom:0;border-radius:36px 36px 0 0;background:var(--surface);box-shadow:var(--shadow-float);overflow:hidden">
  <div style="position:absolute;left:173px;top:10px;width:44px;height:5px;border-radius:999px;background:var(--label3);opacity:0.5"></div>
  <div style="position:absolute;left:20px;right:20px;top:34px;display:flex;align-items:center;justify-content:space-between">
    <div class="footnote" style="color:var(--brand);font-weight:600">取消</div>
    <div class="headline">新建会话</div>
    <div class="footnote" style="color:var(--label3);font-weight:600">开始</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:84px;display:flex;flex-direction:column;gap:20px">
    <div class="card" style="padding:18px;display:flex;flex-direction:column;gap:18px">
      <div style="display:flex;flex-direction:column;gap:10px">
        <div class="eyebrow">Agent</div>
        {seg(["Claude","Codex","自定义"],"Claude")}
      </div>
      <div style="display:flex;flex-direction:column;gap:10px">
        <div class="eyebrow">工作目录</div>
        <div class="input mono" style="font-size:15px">{ic("folder",18,"var(--label2)")}<span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">~/devops/aigc/yukiTrace</span>{ic("chev",16,"var(--label3)")}</div>
        <div style="display:flex;gap:8px;overflow:hidden"><span class="chip chip-fill mono" style="font-weight:500">yukiTrace</span><span class="chip chip-fill mono" style="font-weight:500">YzVibe</span><span class="chip chip-fill mono" style="font-weight:500">lobehub</span></div>
      </div>
      <div style="display:flex;flex-direction:column;gap:10px">
        <div class="eyebrow">首条消息（可选）</div>
        <div class="input" style="height:96px;align-items:flex-start;padding-top:14px;color:var(--label3);font-size:15px;line-height:1.4">让 Agent 审查、修复或继续某件事，会话启动后自动发送</div>
      </div>
    </div>
    <div class="eyebrow" style="padding:0 4px">会话模式</div>
    <div class="card" style="padding:4px 0">
      <div class="row">
        <div style="flex:1"><div class="headline">接续上次会话</div><div class="footnote l2">恢复该目录最近的上下文</div></div>
        <div class="toggle"></div>
      </div>
      <div class="sep"></div>
      <div class="row" style="min-height:76px">
        <div style="flex:1"><div class="headline" style="display:flex;align-items:center;gap:6px">YOLO 模式 {ic("zap",16,"var(--danger)")}</div><div class="footnote l2">跳过所有权限检查，手机端不会再收到审批</div><div class="caption mono l3" style="margin-top:2px">--dangerously-skip-permissions</div></div>
        <div class="toggle toggle-off"></div>
      </div>
    </div>
  </div>
  <div class="btn btn-primary" style="position:absolute;left:20px;right:20px;bottom:36px;height:54px">{ic("sparkle",20)}开始会话</div>
</div>
"""

def bubble_user(text):
    return f'<div style="display:flex;justify-content:flex-end"><div style="max-width:280px;padding:12px 16px;border-radius:22px 22px 6px 22px;background:var(--brand);color:var(--brand-ink);font-size:16px;line-height:1.4;box-shadow:0 6px 18px color-mix(in srgb, var(--brand) 25%, transparent)">{text}</div></div>'
def bubble_ai(html):
    return f'<div style="display:flex;justify-content:flex-start"><div class="card" style="max-width:300px;padding:14px 16px;border-radius:22px 22px 22px 6px;font-size:16px;line-height:1.45;display:flex;flex-direction:column;gap:10px">{html}</div></div>'
def toolcard(name, detail, state_cls, state):
    return f'<div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:14px;background:var(--fill2);box-shadow:inset 0 0 0 1px var(--border)"><div style="width:28px;height:28px;border-radius:9px;background:var(--elev);display:flex;align-items:center;justify-content:center;color:var(--label2)">{ic("terminal",16)}</div><div style="flex:1;min-width:0"><div class="footnote" style="font-weight:600">{name}</div><div class="caption mono l2" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{detail}</div></div><span class="chip {state_cls}" style="height:24px;font-size:12px;padding:0 9px">{state}</span></div>'

def approval_card(cmd, risk_label, risk_cls, bar, compact=False):
    return f"""
<div class="glass" style="border-radius:22px;padding:16px 16px 14px;display:flex;flex-direction:column;gap:12px;position:relative;overflow:hidden">
  <div style="position:absolute;left:0;top:0;bottom:0;width:4px;background:{bar}"></div>
  <div style="display:flex;align-items:center;gap:8px">
    <div style="width:30px;height:30px;border-radius:10px;background:var(--danger-soft);display:flex;align-items:center;justify-content:center">{ic("shield",17,"var(--danger)")}</div>
    <div class="headline" style="flex:1">需要你的批准</div>
    <span class="chip {risk_cls}" style="height:24px;font-size:12px;padding:0 9px">{risk_label}</span>
  </div>
  <div class="footnote l2">Agent 想在 <span class="mono">yukiTrace</span> 中执行 Shell 命令，将删除 3 个文件：</div>
  <div class="mono" style="padding:10px 12px;border-radius:12px;background:oklch(0.2 0.02 50);color:oklch(0.92 0.02 80);font-size:13px;line-height:1.5;white-space:pre-wrap">{cmd}</div>
  <div style="display:flex;gap:8px">
    <div class="btn btn-danger-outline" style="flex:1;height:44px;font-size:15px;padding:0">拒绝</div>
    <div class="btn btn-secondary" style="flex:1.1;height:44px;font-size:15px;padding:0">仅此一次</div>
    <div class="btn btn-primary" style="flex:1;height:44px;font-size:15px;padding:0">{ic("check",17)}允许</div>
  </div>
</div>"""

CHAT_INNER = f"""
{navbar("重构地图标记组件并补测试", f'<div class="icon-btn" style="background:var(--danger-soft);color:var(--danger);width:40px;height:40px">{ic("stop",18)}</div><span class="chip chip-claude">Claude</span>', sub="运行中 · yukiTrace")}
<div style="position:absolute;left:16px;right:16px;top:134px;display:flex;flex-direction:column;gap:14px">
  {bubble_user("把 yt-marker 拆成独立组件，补上快照测试")}
  {bubble_ai('<div>好的，先读现有实现再拆分。</div>' + toolcard("Read","src/components/map/marker.tsx","chip-sage","完成"))}
  {approval_card("rm -rf src/components/map/legacy/" + chr(10) + "  marker.old.tsx marker.test.old.tsx" + chr(10) + "  marker.snap","高风险","chip-danger","var(--danger)")}
</div>
<div style="position:absolute;left:0;right:0;bottom:96px;display:flex;gap:8px;padding:0 16px;overflow:hidden">
  <span class="chip chip-fill" style="height:36px;font-size:14px">继续</span><span class="chip chip-fill" style="height:36px;font-size:14px">LGTM，执行</span><span class="chip chip-fill" style="height:36px;font-size:14px">解释一下</span><span class="chip chip-fill" style="height:36px;font-size:14px">撤销上一步</span>
</div>
<div class="glass" style="position:absolute;left:16px;right:16px;bottom:26px;height:60px;border-radius:999px;display:flex;align-items:center;gap:8px;padding:0 6px 0 8px">
  <div class="icon-btn" style="background:var(--fill);color:var(--label2);width:40px;height:40px">{ic("camera",20)}</div>
  <div style="flex:1;color:var(--label3);font-size:16px;padding-left:4px">发消息给 Claude…</div>
  <div class="icon-btn glass-brand" style="width:46px;height:46px">{ic("up",22,"var(--brand-ink)",2.2)}</div>
</div>
"""
CHAT = CHAT_INNER
CHAT_DARK = CHAT_INNER

def approval_row(device, session, agent, agent_cls, kind, detail, when, risk_cls, risk):
    return f"""
<div class="card" style="padding:16px 18px;display:flex;flex-direction:column;gap:12px">
  <div style="display:flex;align-items:center;gap:8px">
    <div class="dot dot-danger"></div>
    <span class="chip {agent_cls}">{agent}</span>
    <span class="chip {risk_cls}">{risk}</span>
    <span class="footnote l3" style="margin-left:auto">{when}</span>
  </div>
  <div>
    <div class="headline" style="font-size:17px">{kind}</div>
    <div class="footnote l2" style="margin-top:2px">{device} · {session}</div>
  </div>
  <div class="code mono">{detail}</div>
  <div style="display:flex;gap:8px">
    <div class="btn btn-danger-outline" style="flex:1;height:44px;font-size:15px;padding:0">拒绝</div>
    <div class="btn btn-primary" style="flex:1.3;height:44px;font-size:15px;padding:0">{ic("check",17)}允许</div>
  </div>
</div>"""

APPROVALS = f"""
<div class="scroll">
  <div style="position:absolute;left:20px;right:20px;top:70px;display:flex;align-items:flex-end;justify-content:space-between">
    <div>
      <div class="eyebrow" style="color:var(--brand)">全部设备</div>
      <div class="large-title" style="margin-top:6px">审批</div>
    </div>
    <div class="icon-btn glass" style="color:var(--label)">{ic("faceid",22)}</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:150px">{seg(["待处理 2","历史"],"待处理 2")}</div>
  <div style="position:absolute;left:20px;right:20px;top:216px;display:flex;flex-direction:column;gap:12px">
    {approval_row("Mac Studio","重构地图标记组件","Claude","chip-claude","执行 Shell 命令","rm -rf src/components/map/legacy/","刚刚","chip-danger","高风险")}
    {approval_row("MacBook Pro 16","补充 API 文档","Claude","chip-claude","写入文件","docs/api.md（+142 行）","4 分钟前","chip-claude","低风险")}
    <div class="glass" style="border-radius:18px;padding:14px 16px;display:flex;align-items:center;gap:12px">
      {ic("lock",20,"var(--sage)")}
      <div class="footnote l2" style="flex:1">高风险审批默认需要 Face ID 确认，可在「我 › 安全」中调整。</div>
    </div>
  </div>
</div>
{tabbar("approvals")}
"""

def file_row(icon, color, name, meta, chip=""):
    return f'<div class="row" style="min-height:60px"><div style="width:38px;height:38px;border-radius:12px;background:{color};display:flex;align-items:center;justify-content:center;color:var(--label2)">{ic(icon,19)}</div><div style="flex:1;min-width:0"><div class="headline" style="font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{name}</div><div class="caption l3" style="margin-top:1px">{meta}</div></div>{chip}{ic("chev",18,"var(--label3)")}</div>'

FILES = f"""
{navbar("文件", f'<div class="icon-btn" style="background:var(--fill);color:var(--label2)">{ic("refresh",19)}</div>', sub="~/devops/aigc/yukiTrace")}
<div style="position:absolute;left:16px;right:16px;top:134px;display:flex;gap:6px;overflow:hidden;align-items:center">
  <span class="chip chip-fill mono" style="font-weight:500">~</span>{ic("chev",14,"var(--label3)")}<span class="chip chip-fill mono" style="font-weight:500">yukiTrace</span>{ic("chev",14,"var(--label3)")}<span class="chip chip-brand mono" style="font-weight:600">src/components/map</span>
</div>
<div class="card" style="position:absolute;left:16px;right:16px;top:184px;padding:4px 0">
  {file_row("folder","var(--amber-soft)","legacy","3 个文件 · 待删除",'<span class="chip chip-danger" style="height:24px;font-size:12px;padding:0 9px">审批中</span>')}
  <div class="sep"></div>
  {file_row("file","var(--blue-soft)","YtMarker.tsx","4.2 KB · 刚刚修改",'<span class="chip chip-sage" style="height:24px;font-size:12px;padding:0 9px">已改</span>')}
  <div class="sep"></div>
  {file_row("file","var(--blue-soft)","YtMarker.test.tsx","1.8 KB · 刚刚新建",'<span class="chip chip-sage" style="height:24px;font-size:12px;padding:0 9px">新</span>')}
  <div class="sep"></div>
  {file_row("markdown","var(--sage-soft)","README.md","2.1 KB · 昨天")}
  <div class="sep"></div>
  {file_row("image","var(--purple-soft)","marker-preview.png","318 KB · 3 天前")}
</div>
<div class="card" style="position:absolute;left:16px;right:16px;top:516px;padding:16px 18px;display:flex;flex-direction:column;gap:12px">
  <div style="display:flex;align-items:center;gap:10px">
    {ic("file",18,"var(--blue)")}
    <div class="headline" style="flex:1;font-size:16px">YtMarker.tsx</div>
    <span class="footnote l3">预览</span>
  </div>
  <div class="mono" style="padding:12px 14px;border-radius:12px;background:oklch(0.2 0.02 50);color:oklch(0.9 0.02 80);font-size:12px;line-height:1.55;white-space:pre">export function YtMarker({{ tone }}: Props) {{
  return (
    &lt;span className="yt-marker"
      style={{{{ background: tone }}}} /&gt;
  )
}}</div>
  <div style="display:flex;gap:8px">
    <div class="btn btn-secondary" style="flex:1;height:44px;font-size:15px">{ic("copy",17)}复制路径</div>
    <div class="btn btn-primary" style="flex:1;height:44px;font-size:15px">{ic("download",17)}下载到手机</div>
  </div>
</div>
<div class="footnote l3" style="position:absolute;left:0;right:0;bottom:30px;text-align:center;display:flex;align-items:center;justify-content:center;gap:6px">{ic("lock",14,"var(--label3)")}只预览与下载，手机不会执行任何文件</div>
"""

def settings_group(title, rows):
    body = '<div class="sep"></div>'.join(rows)
    return f'<div style="display:flex;flex-direction:column;gap:10px"><div class="eyebrow" style="padding:0 4px">{title}</div><div class="card" style="padding:4px 0">{body}</div></div>'
def srow(icon, color, label, right):
    return f'<div class="row"><div style="width:32px;height:32px;border-radius:10px;background:{color};display:flex;align-items:center;justify-content:center;color:white">{ic(icon,17,"white")}</div><div class="body" style="flex:1">{label}</div>{right}</div>'

ME = f"""
<div class="scroll">
  <div style="position:absolute;left:20px;right:20px;top:70px">
    <div class="eyebrow" style="color:var(--brand)">YzVibe</div>
    <div class="large-title" style="margin-top:6px">我</div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:150px;display:flex;flex-direction:column;gap:20px">
    <div class="glass" style="border-radius:22px;padding:16px 18px;display:flex;align-items:center;gap:14px">
      <div style="width:52px;height:52px;border-radius:16px;background:linear-gradient(135deg, var(--brand), var(--amber));display:flex;align-items:center;justify-content:center;box-shadow:0 8px 20px color-mix(in srgb, var(--brand) 30%, transparent)">{ic("phone",26,"white")}</div>
      <div style="flex:1"><div class="headline">这台 iPhone</div><div class="footnote l2">3 台已配对电脑 · 无账号，本地优先</div></div>
      {ic("chev",18,"var(--label3)")}
    </div>
    {settings_group("通知",[srow("bell","var(--danger)","有待审批时通知",'<div class="toggle"></div>'),srow("chat","var(--sage)","回复完成时通知",'<div class="toggle"></div>')])}
    {settings_group("会话列表",[srow("folder","var(--amber-text)","按文件夹分组",'<div class="toggle"></div>'),srow("zap","var(--brand)","仅显示活跃",'<div class="toggle toggle-off"></div>')])}
    {settings_group("外观",[f'<div style="padding:12px 14px">{seg(["自动","浅色","深色"],"自动")}</div>'])}
    {settings_group("安全",[srow("faceid","var(--purple)","高风险审批需 Face ID",'<div class="toggle"></div>'),srow("lock","var(--blue)","Token 存储",'<span class="footnote l2">钥匙串</span>')])}
    {settings_group("关于",[srow("info","var(--label3)","版本",'<span class="footnote l2 mono">0.1.0 (1)</span>')])}
  </div>
</div>
{tabbar("me")}
"""

# ───────────── 设计系统总览（宽画板） ─────────────
def swatch(var, name, val):
    return f'<div style="display:flex;flex-direction:column;gap:8px;width:120px"><div style="height:64px;border-radius:16px;background:var({var});box-shadow:inset 0 0 0 1px var(--border)"></div><div class="footnote" style="font-weight:600">{name}</div><div class="caption mono l2">{val}</div></div>'

TOKENS_INNER = f"""
<div style="position:absolute;left:0;right:0;top:0;bottom:0;padding:40px 48px;display:flex;flex-direction:column;gap:36px">
  <div>
    <div class="eyebrow" style="color:var(--brand)">YzVibe · Design System</div>
    <div class="large-title" style="margin-top:6px">Liquid Glass × 暖调纸感</div>
    <div class="subhead l2" style="margin-top:6px;max-width:720px">玻璃只用于漂浮层（导航、Tab、输入条、审批卡），内容层永远是不透明纸感卡片。赭红 = 行动，鼠尾草 = 在线/成功，琥珀 = Claude/等待，红 = 危险。</div>
  </div>
  <div style="display:flex;flex-direction:column;gap:14px">
    <div class="eyebrow">品牌与语义色</div>
    <div style="display:flex;gap:18px;flex-wrap:wrap">
      {swatch("--brand","brand 赭红","oklch(0.64 0.17 40)")}{swatch("--brand-soft","brand-soft","oklch(0.94 0.04 45)")}
      {swatch("--sage","sage 鼠尾草","oklch(0.60 0.09 165)")}{swatch("--sage-soft","sage-soft","oklch(0.93 0.035 165)")}
      {swatch("--amber","amber 琥珀","oklch(0.82 0.13 80)")}{swatch("--amber-soft","amber-soft","oklch(0.96 0.05 85)")}
      {swatch("--danger","danger","oklch(0.60 0.20 25)")}{swatch("--purple","purple (Codex)","oklch(0.55 0.15 310)")}{swatch("--blue","blue (Custom)","oklch(0.58 0.13 235)")}
    </div>
  </div>
  <div style="display:flex;flex-direction:column;gap:14px">
    <div class="eyebrow">纸感分层</div>
    <div style="display:flex;gap:18px;flex-wrap:wrap">
      {swatch("--surface","surface","oklch(0.975 0.009 80)")}{swatch("--elev","surface-elevated","oklch(0.995 0.004 85)")}{swatch("--fill","fill","oklch(0.935 0.012 75)")}{swatch("--fill2","fill-secondary","oklch(0.958 0.01 78)")}{swatch("--border","border","oklch(0.90 0.014 70)")}{swatch("--label","label","oklch(0.22 0.02 45)")}{swatch("--label2","label-secondary","oklch(0.50 0.02 55)")}{swatch("--label3","label-tertiary","oklch(0.68 0.018 60)")}
    </div>
  </div>
  <div style="display:flex;gap:40px">
    <div style="display:flex;flex-direction:column;gap:14px;flex:1">
      <div class="eyebrow">字阶（SF Pro / 苹方）</div>
      <div class="large-title">Large Title 34 Bold</div>
      <div class="title1">Title 1 28 Bold</div>
      <div class="title2">Title 2 22 Semibold</div>
      <div class="headline">Headline 17 Semibold</div>
      <div class="body">Body 17 Regular — 离开电脑，AI 会话照样往前推。</div>
      <div class="subhead l2">Subhead 15</div>
      <div class="footnote l2">Footnote 13</div>
      <div class="eyebrow">Eyebrow 12 · Tracking 0.1em</div>
      <div class="mono footnote">Mono 13 — npx yzvibe --access=local</div>
    </div>
    <div style="display:flex;flex-direction:column;gap:14px;flex:1.3">
      <div class="eyebrow">组件</div>
      <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center">
        <div class="btn btn-primary">{ic("check",18)}主按钮</div><div class="btn btn-secondary">次按钮</div><div class="btn btn-outline">描边</div><div class="btn btn-danger-outline">拒绝</div><div class="btn glass" style="color:var(--label)">玻璃按钮</div>
      </div>
      <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">
        <span class="chip chip-claude">Claude</span><span class="chip chip-codex">Codex</span><span class="chip chip-custom">自定义</span><span class="chip chip-sage">在线</span><span class="chip chip-brand">Tunnel</span><span class="chip chip-danger">高风险</span><span class="chip chip-fill">默认</span>
      </div>
      <div style="display:flex;gap:14px;align-items:center">
        <div class="dot dot-sage"></div><span class="footnote l2">空闲/在线</span><div class="dot dot-amber"></div><span class="footnote l2">运行中</span><div class="dot dot-danger"></div><span class="footnote l2">待审批</span><div class="dot dot-off"></div><span class="footnote l2">离线</span>
        <div class="toggle" style="margin-left:auto"></div><div class="toggle toggle-off"></div>
      </div>
      <div style="position:relative;height:150px;border-radius:24px;overflow:hidden;background:var(--surface)">
        <div class="orb" style="width:240px;height:240px;left:-40px;top:-100px;background:var(--brand-soft);filter:blur(40px)"></div>
        <div class="orb" style="width:240px;height:240px;right:-60px;top:-40px;background:var(--amber-soft);filter:blur(40px)"></div>
        <div class="navbar glass" style="top:16px;left:16px;right:16px">{'<div class="icon-btn" style="background:var(--fill)">'+ic("back",20)+'</div>'}<div class="headline" style="flex:1;padding-left:2px">玻璃导航条</div><span class="chip chip-claude">Claude</span></div>
        <div class="tabbar glass" style="bottom:14px;left:16px;right:16px;height:60px">{''.join(f'<div class="tab{" tab-on" if k=="devices" else ""}" style="height:48px">{ic(i,20)}<span>{l}</span></div>' for k,i,l in [("devices","monitor","设备"),("sessions","chat","会话"),("approvals","inbox","审批"),("me","user","我")])}</div>
      </div>
      <div class="caption l2">玻璃配方：elev @ 62% · blur 24px saturate 180% · 内描边 0.5pt 白 55% · 暖阴影。iOS 26 用 <span class="mono">.glassEffect()</span>，低版本回落 ultraThinMaterial。</div>
    </div>
  </div>
</div>
"""

def wide(inner, dark=False, w=1200, h=1180):
    vars_ = DARK if dark else LIGHT
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
  :root {{ {vars_} }}
  {CSS}
  .phone {{ width: {w}px; height: {h}px; }}
  </style>
</helmet>
<div class="phone paper">
{inner}
</div>
</x-dc>
</body>
</html>
"""

FILES_OUT = {
  "Main.dc.html": phone(DEVICES),
  "Pair.dc.html": phone(PAIR),
  "Sessions.dc.html": phone(SESSIONS),
  "NewSession.dc.html": phone(NEWSESSION),
  "Chat.dc.html": phone(CHAT),
  "Approvals.dc.html": phone(APPROVALS),
  "Files.dc.html": phone(FILES),
  "Me.dc.html": phone(ME),
  "ChatDark.dc.html": phone(CHAT_DARK, dark=True),
  "DesignSystem.dc.html": wide(TOKENS_INNER),
}
for name, src in FILES_OUT.items():
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        f.write(src)

W, H, GX, GY = 390, 844, 90, 140
row1 = ["Main.dc.html","Pair.dc.html","Sessions.dc.html","NewSession.dc.html","Chat.dc.html"]
row2 = ["Approvals.dc.html","Files.dc.html","Me.dc.html","ChatDark.dc.html"]
titles = {"Main.dc.html":"1 设备","Pair.dc.html":"2 扫码配对","Sessions.dc.html":"3 会话列表","NewSession.dc.html":"4 新建会话","Chat.dc.html":"5 聊天 + 审批卡","Approvals.dc.html":"6 审批收件箱","Files.dc.html":"7 远程文件","Me.dc.html":"8 我 / 设置","ChatDark.dc.html":"9 聊天 · 深色","DesignSystem.dc.html":"设计系统总览"}
arts = []
for i, f in enumerate(row1):
    arts.append({"file": f, "x": i*(W+GX), "y": 0, "w": W, "h": H, "title": titles[f], "page": "page-1"})
for i, f in enumerate(row2):
    arts.append({"file": f, "x": i*(W+GX), "y": H+GY, "w": W, "h": H, "title": titles[f], "page": "page-1"})
arts.append({"file": "DesignSystem.dc.html", "x": 0, "y": 0, "w": 1200, "h": 1180, "title": titles["DesignSystem.dc.html"], "page": "page-2"})
canvas = {
  "pages": [{"id":"page-1","name":"核心屏幕"},{"id":"page-2","name":"设计系统"}],
  "artboards": arts,
  "annotations": [
    {"id":"flow-note","x":0,"y":-150,"w":520,"page":"page-1",
     "text":"YzVibe · 手机远程掌控桌面 AI 会话\\n流程：设备 → 扫码配对 → 会话列表 → 新建会话 → 聊天（内嵌审批卡）\\n第二行：审批收件箱 / 远程文件 / 我 / 深色模式\\n风格：iOS 26 Liquid Glass × yukiTrace 暖调（赭红·鼠尾草·琥珀）"},
    {"id":"glass-rule","x":2400,"y":-150,"w":420,"page":"page-1",
     "text":"玻璃规则：只有导航条、Tab 栏、输入条、审批卡、浮动按钮是玻璃；内容卡片始终不透明，保证可读。"},
  ],
  "launch": {"view":"canvas","page":"page-1"},
}
with open(os.path.join(HERE, "canvas.json"), "w", encoding="utf-8") as f:
    json.dump(canvas, f, ensure_ascii=False, indent=2)
print("built", len(FILES_OUT), "artboards")

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""YzVibe 视觉方向对比页：4 个候选方向 × 2 个核心屏。
运行：python3 build.py  →  同目录输出 index.html（浏览器直接打开）"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))

# ───────────── 图标 ─────────────
ICONS = {
 "search":'<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
 "chev":'<path d="M9 5l7 7-7 7"/>',
 "down":'<path d="M6 9l6 6 6-6"/>',
 "folder":'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
 "plus":'<path d="M12 5v14M5 12h14"/>',
 "back":'<path d="M15 5l-7 7 7 7"/>',
 "monitor":'<rect x="3" y="4" width="18" height="12" rx="2.5"/><path d="M8 20h8M12 16v4"/>',
 "chat":'<path d="M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 4z"/>',
 "inbox":'<path d="M4 13l2.5-8h11L20 13v6H4z"/><path d="M4 13h5l1.5 2.5h3L15 13h5"/>',
 "user":'<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
 "terminal":'<path d="M5 7l5 5-5 5M12 17h7"/>',
 "copy":'<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
 "camera":'<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
 "send":'<path d="M12 19V5M5 12l7-7 7 7"/>',
 "stop":'<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
 "more":'<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
 "shield":'<path d="M12 3l8 3v6c0 4.5-3.5 7.8-8 9-4.5-1.2-8-4.5-8-9V6z"/>',
 "check":'<path d="M5 12l5 5 9-10"/>',
 "x":'<path d="M6 6l12 12M18 6L6 18"/>',
 "plusminus":'<circle cx="12" cy="12" r="9"/><path d="M9 9h6M12 6v6M9 16h6"/>',
 "wifi":'<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M2 9a14 14 0 0 1 20 0"/><circle cx="12" cy="19.5" r="1"/>',
}
def ic(n, size=20, color="currentColor", sw=1.8):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0">{ICONS[n]}</svg>')

# ───────────── 四个方向 ─────────────
DIRECTIONS = [
 dict(
  key="a", title="A · 原生优先", en="Native First",
  one="橙色只做 tint 和填充，不承担文字对比 —— 苹果自己怎么用 systemOrange，就怎么用。",
  vars="""
    --brand:#FF9500; --on-brand:#2B1D10; --brand-soft:#FFEBD2; --brand-text:#A6560A;
    --surface:#F2F1EE; --elev:#FFFFFF; --fill:#E9E7E2; --border:rgba(60,56,50,0.16);
    --label:#1C1A17; --label2:#6C6862; --label3:#8E8A84;
    --ok:#248A3D; --danger:#D70015; --danger-soft:#FFE5E3;
  """,
  st=dict(rows="grouped", bg="plain", tabbar="system", newbtn="toolbar", rowrad=0, dark=False),
  swatches=[("#FF9500","tint / 填充","深字 7.7:1"),("#A6560A","橙色文字","4.9:1"),("#FFEBD2","浅橙底",""),("#1C1A17","主文字","15.9:1")],
  fit="想尽快「看起来就是一个 iOS App」，愿意舍掉现在的暖纸氛围。",
  cost="品牌辨识度最低 —— 去掉 Logo 后和系统 App 难以区分。",
  work="改动最小：List + 系统导航 + 换 tint，约 2 天。",
 ),
 dict(
  key="b", title="B · 焦橙纸感", en="Terracotta Paper",
  one="系统结构 + 暖纸中性 + 一个焦橙。橙色实心、白字，全部合规。",
  vars="""
    --brand:#C75015; --on-brand:#FFFFFF; --brand-soft:#FFE5D8; --brand-text:#A63D02;
    --surface:#F9F6F2; --elev:#FFFDFA; --fill:#EFEAE2; --border:#E6DFD5;
    --label:#231813; --label2:#6D6059; --label3:#877E78;
    --ok:#1F7A4D; --danger:#C4261C; --danger-soft:#FBE3E0;
  """,
  st=dict(rows="card", bg="paper", tabbar="system", newbtn="pill", rowrad=16, dark=False),
  swatches=[("#C75015","主色 / 实心","白字 4.6:1"),("#A63D02","橙色文字","浅橙底 5.3:1"),("#FFE5D8","浅橙底",""),("#F9F6F2","暖纸底","")],
  fit="想保住「暖、手工、不是又一个 SaaS」的气质，同时通过无障碍审查。",
  cost="焦橙比现在的亮橙沉一档，第一眼没那么跳。",
  work="中等：List + 系统导航 + 色板重算 + 去装饰球，约 3 天。",
 ),
 dict(
  key="c", title="C · 液态玻璃", en="Liquid Glass Dark",
  one="深色为底，iOS 26 原生玻璃做浮层，亮橙只在 tint 和用户气泡上发光。",
  vars="""
    --brand:#FF9868; --on-brand:#241812; --brand-soft:rgba(255,152,104,0.16); --brand-text:#FFB08A;
    --surface:#201E1B; --elev:rgba(255,255,255,0.07); --fill:rgba(255,255,255,0.10); --border:rgba(255,255,255,0.12);
    --label:#F5F2EE; --label2:#B5AEA6; --label3:#8A837B;
    --ok:#5BD98A; --danger:#FF6961; --danger-soft:rgba(255,105,97,0.16);
  """,
  st=dict(rows="glass", bg="dark", tabbar="floating", newbtn="glasspill", rowrad=20, dark=True),
  swatches=[("#FF9868","主色 / tint","暗底 7.9:1"),("#FFB08A","橙色文字",""),("#201E1B","暖黑底",""),("#F5F2EE","主文字","16.7:1")],
  fit="产品定位是「开发者的夜间遥控器」，想要最强的记忆点。",
  cost="强依赖 iOS 26；低版本回落后差距明显。浅色模式要另做一套。",
  work="最大：材质、层级、双色板都要重做，约 5 天。",
 ),
 dict(
  key="d", title="D · 现状修正", en="Current, Fixed",
  one="保留装饰球、纸卡和五色分工，只修对比度、深色中性和结构问题。",
  vars="""
    --brand:#C75015; --on-brand:#FFFFFF; --brand-soft:#FFE5D8; --brand-text:#A63D02;
    --surface:#FAF6F0; --elev:#FFFDFA; --fill:#EEE9E1; --border:#E5DED4;
    --label:#231813; --label2:#6D6059; --label3:#877E78;
    --ok:#1F7A4D; --danger:#C4261C; --danger-soft:#FBE3E0;
    --sage:#3F8A6C; --sage-soft:#D3F0E2; --amber:#F0BA59; --amber-text:#8A5A0E; --amber-soft:#FFF0CC;
    --purple:#7A4A9E; --purple-soft:#F0E6F7;
  """,
  st=dict(rows="bigcard", bg="orbs", tabbar="floating", newbtn="fab", rowrad=24, dark=False),
  swatches=[("#C75015","主色（原 #DE602F）","白字 4.6:1"),("#3F8A6C","在线",""),("#8A5A0E","Claude",""),("#7A4A9E","Codex","")],
  fit="不想动视觉语言，只想把无障碍和结构补齐。",
  cost="仍然不像 iOS App；五个强调色让界面偏「花」。",
  work="最小：色板 + 结构，约 1.5 天。",
 ),
]

# ───────────── 组件 ─────────────
def statusbar(d):
    c = "var(--label)"
    return f'''<div class="sb"><span style="font-weight:600">9:41</span><span style="display:flex;gap:6px;align-items:center">
      <svg width="17" height="12" viewBox="0 0 17 12" fill="{c}"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="4.5" y="5.5" width="3" height="6.5" rx="1"/><rect x="9" y="3" width="3" height="9" rx="1"/><rect x="13.5" y="0" width="3" height="12" rx="1"/></svg>
      {ic("wifi",15,c,2)}
      <svg width="25" height="12" viewBox="0 0 25 12" fill="none"><rect x="0.5" y="0.5" width="21" height="11" rx="3.2" stroke="{c}" stroke-opacity="0.4"/><rect x="2" y="2" width="16" height="8" rx="2" fill="{c}"/><path d="M23 4v4a2.2 2.2 0 0 0 0-4z" fill="{c}" fill-opacity="0.4"/></svg>
    </span></div>'''

def orbs(d):
    if d["st"]["bg"] == "dark":
        return ('<div class="orb" style="width:520px;height:420px;left:-90px;top:-120px;'
                'background:radial-gradient(closest-side,rgba(255,152,104,0.30),transparent);filter:blur(50px)"></div>'
                '<div class="orb" style="width:460px;height:400px;right:-140px;bottom:-90px;'
                'background:radial-gradient(closest-side,rgba(120,160,255,0.16),transparent);filter:blur(50px)"></div>')
    if d["st"]["bg"] != "orbs": return ""
    return ('<div class="orb" style="width:360px;height:360px;left:-120px;top:-150px;background:var(--brand-soft)"></div>'
            '<div class="orb" style="width:300px;height:300px;right:-130px;top:-50px;background:var(--amber-soft)"></div>'
            '<div class="orb" style="width:420px;height:420px;left:-15px;bottom:-270px;background:var(--sage-soft)"></div>')

def rowbox(d, inner, pad="14px 16px"):
    """一行会话卡，按方向切换承载方式"""
    r = d["st"]["rows"]
    if r == "grouped":
        return f'<div class="grp-row" style="padding:{pad}">{inner}</div>'
    if r == "card":
        return f'<div class="p-card" style="padding:{pad}">{inner}</div>'
    if r == "glass":
        return f'<div class="g-card" style="padding:{pad}">{inner}</div>'
    return f'<div class="b-card" style="padding:16px 18px">{inner}</div>'

def chatbox(d, inner, pad="14px 16px"):
    """聊天里的消息 / 工具卡承载"""
    r = d["st"]["rows"]
    if r == "grouped":
        return f'<div class="m-bubble" style="padding:{pad}">{inner}</div>'
    if r == "card":
        return f'<div class="p-card" style="padding:{pad}">{inner}</div>'
    if r == "glass":
        return f'<div class="g-card" style="padding:{pad}">{inner}</div>'
    return f'<div class="b-card" style="padding:{pad}">{inner}</div>'

def chip(text, kind, d):
    m = {
      "claude": ("var(--brand-soft)", "var(--brand-text)"),
      "codex":  ("var(--fill)", "var(--label2)"),
      "wait":   ("var(--danger-soft)", "var(--danger)"),
      "fill":   ("var(--fill)", "var(--label2)"),
    }
    if d["key"] == "d":
        m["claude"] = ("var(--amber-soft)", "var(--amber-text)")
        m["codex"]  = ("var(--purple-soft)", "var(--purple)")
    bg, fg = m[kind]
    return f'<span class="chip" style="background:{bg};color:{fg}">{text}</span>'

def dot(color):
    return f'<span class="dot" style="background:{color};box-shadow:0 0 0 3px color-mix(in srgb,{color} 22%,transparent)"></span>'

def session_row(d, *, status, agent, title, path, meta, waiting=False):
    dc = {"run":"var(--brand)" if d["key"]!="d" else "var(--amber)", "idle":"var(--ok)" if d["key"]!="d" else "var(--sage)", "off":"var(--label3)"}[status]
    chev = ic("chev",16,"var(--label3)",2.2) if d["st"]["rows"]=="grouped" else ""
    head = (f'<div style="display:flex;align-items:center;gap:8px">{dot(dc)}{chip(agent,"claude" if agent=="Claude" else "codex",d)}'
            + (chip("1 待审批","wait",d) if waiting else "")
            + f'<span class="footnote l3" style="margin-left:auto">{meta}</span></div>')
    body = (f'<div class="headline" style="margin-top:9px;font-size:17px">{title}</div>'
            f'<div class="code mono" style="margin-top:8px">{path}</div>')
    if chev:
        inner = f'<div style="flex:1;min-width:0">{head}{body}</div>{chev}'
        return rowbox(d, f'<div style="display:flex;align-items:center;gap:10px">{inner}</div>')
    return rowbox(d, head + body)

def tabbar(d):
    items = [("monitor","设备",False,0),("chat","会话",True,0),("inbox","审批",False,2),("user","我",False,0)]
    cells = ""
    for n,label,on,badge in items:
        col = "var(--brand)" if on else "var(--label3)"
        bd = f'<span class="tbadge">{badge}</span>' if badge else ""
        if d["st"]["tabbar"] == "floating" and on:
            cells += (f'<div class="tab" style="color:var(--on-brand);background:var(--brand);border-radius:999px">'
                      f'{ic(n,22,"currentColor",2)}<span>{label}</span>{bd}</div>')
        else:
            cells += f'<div class="tab" style="color:{col}">{ic(n,23,"currentColor",2)}<span>{label}</span>{bd}</div>'
    cls = "tabbar-float glass" if d["st"]["tabbar"]=="floating" else "tabbar-sys"
    return f'<div class="{cls}">{cells}</div>'

# ───────────── 屏 1：会话列表 ─────────────
def screen_sessions(d):
    st = d["st"]
    gap = {"grouped":0,"card":10,"glass":10,"bigcard":12}[st["rows"]]
    rows = (session_row(d, status="run", agent="Claude", title="重构地图标记组件并补测试",
                        path="~/devops/aigc/yukiTrace", meta="运行中 · 3 分钟", waiting=True)
          + (('<div class="grp-sep"></div>') if st["rows"]=="grouped" else "")
          + session_row(d, status="idle", agent="Codex", title="修复 iOS Safari 日期输入溢出",
                        path="~/devops/aigc/yukiTrace", meta="空闲 · 26 分钟")
          + (('<div class="grp-sep"></div>') if st["rows"]=="grouped" else "")
          + session_row(d, status="off", agent="Claude", title="连接器日志轮转与资源回收",
                        path="~/devops/aigc/YzVibe", meta="已关闭 · 昨天"))
    if st["rows"] == "grouped":
        rows = f'<div class="grp">{rows}</div>'
    else:
        rows = f'<div style="display:flex;flex-direction:column;gap:{gap}px">{rows}</div>'

    # 导航区
    if st["newbtn"] == "toolbar":
        toolbar = f'<div class="tb-btn" style="color:var(--brand)">{ic("plus",24,"currentColor",2.2)}</div>'
    else:
        toolbar = f'<div class="chip" style="height:34px;background:var(--fill);color:var(--label2);gap:5px">{dot("var(--ok)" if d["key"]!="d" else "var(--sage)")}已连接{ic("down",14,"var(--label3)",2.2)}</div>'
    nav = f'''<div style="display:flex;align-items:flex-end;justify-content:space-between;padding:0 20px">
      <div><div class="eyebrow" style="color:var(--brand-text)">YUKI 的 MAC STUDIO</div>
      <div class="large-title" style="margin-top:5px">会话</div></div>{toolbar}</div>'''

    search = f'''<div style="padding:14px 20px 0;display:flex;gap:10px">
      <div class="searchbar">{ic("search",17,"var(--label3)",2)}<span class="l3">搜索会话或路径</span></div>
      <div class="chip" style="height:38px;padding:0 14px;background:var(--brand-soft);color:var(--brand-text)">仅活跃</div></div>'''

    group = f'''<div style="display:flex;align-items:center;gap:7px;padding:18px 20px 8px">
      {ic("folder",16,"var(--label2)",2)}<span class="headline" style="font-size:15px">yukiTrace</span>
      <span class="footnote mono l3" style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">~/devops/aigc/yukiTrace</span>
      <span class="footnote l3">3</span></div>'''

    fab = ""
    if st["newbtn"] == "pill":
        fab = f'<div class="fab" style="background:var(--brand);color:var(--on-brand)">{ic("plus",20,"currentColor",2.2)}新建会话</div>'
    elif st["newbtn"] == "glasspill":
        fab = f'<div class="fab glass" style="color:var(--brand)">{ic("plus",20,"currentColor",2.2)}新建会话</div>'
    elif st["newbtn"] == "fab":
        fab = f'<div class="fab" style="background:var(--brand);color:var(--on-brand);box-shadow:0 12px 30px color-mix(in srgb,var(--brand) 38%,transparent)">{ic("plus",22,"currentColor",2.2)}新建会话</div>'

    pad = "0 20px" if st["rows"] != "grouped" else "0 16px"
    return f'''<div class="frame {"paper" if st["bg"]=="paper" else ""}">{orbs(d)}{statusbar(d)}
      <div class="body-scroll">{nav}{search}{group}<div style="padding:{pad}">{rows}</div></div>
      {fab}{tabbar(d)}</div>'''

# ───────────── 屏 2：聊天 / 审批 ─────────────
def screen_chat(d):
    st = d["st"]
    navcls = "chatnav glass" if st["rows"] in ("glass",) or st["bg"]=="orbs" else "chatnav solid"
    nav = f'''<div class="{navcls}">
      <div style="width:32px;color:var(--brand)">{ic("back",22,"currentColor",2.2)}</div>
      <div style="flex:1;text-align:center;min-width:0">
        <div class="headline" style="font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">重构地图标记组件</div>
        <div class="caption l3">等待审批 · yukiTrace</div></div>
      <div style="display:flex;gap:14px;color:var(--brand)">{ic("plusminus",21,"currentColor",2)}{ic("more",21,"currentColor",2)}</div></div>'''

    assistant = chatbox(d, f'''<div class="body-t">我准备把 <span class="mono" style="font-size:14px">MarkerLayer</span> 拆成三个文件，先跑一遍现有测试确认基线。</div>
      <div class="codeblock mono" style="margin-top:10px">
        <div class="cb-head"><span>bash</span>{ic("copy",13,"currentColor",2)}</div>
        <div class="cb-body">npm test -- --run marker</div></div>''', pad="14px 16px")

    tool = chatbox(d, f'''<div style="display:flex;align-items:center;gap:10px">
        {ic("terminal",18,"var(--label2)",2)}<span class="headline" style="font-size:15px">Bash</span>
        <span class="footnote l3">·  12 passed</span>
        <span style="margin-left:auto;color:var(--ok)">{ic("check",17,"currentColor",2.4)}</span></div>''', pad="13px 16px")

    ap_wrap = {"glass":"g-card","bigcard":"b-card","grouped":"m-bubble"}.get(st["rows"], "p-card")
    approval = f'''<div class="{ap_wrap}" style="padding:0;overflow:hidden;display:flex">
      <div style="width:4px;background:var(--danger);flex-shrink:0"></div>
      <div style="flex:1;min-width:0;padding:14px 16px">
        <div style="display:flex;align-items:center;gap:8px">{ic("shield",17,"var(--danger)",2)}
          <span class="headline" style="font-size:15px">需要你批准</span>
          <span class="footnote l3" style="margin-left:auto">Claude · 刚刚</span></div>
        <div class="codeblock mono" style="margin-top:10px"><div class="cb-body">rm -rf ./dist &amp;&amp; npm run build</div></div>
        <div style="display:flex;gap:8px;margin-top:12px">
          <div class="btn btn-ghost" style="color:var(--danger);box-shadow:inset 0 0 0 1.5px color-mix(in srgb,var(--danger) 50%,transparent)">拒绝</div>
          <div class="btn btn-ghost" style="background:var(--fill);color:var(--label)">仅此次</div>
          <div class="btn" style="background:var(--brand);color:var(--on-brand);flex:1.2">放行</div>
        </div></div></div>'''

    bubble = f'''<div style="display:flex;justify-content:flex-end;margin-top:14px">
      <div class="bubble" style="background:var(--brand);color:var(--on-brand)">先跑测试，别动 dist 目录</div></div>'''

    earlier = f'''<div style="display:flex;justify-content:flex-end;margin-bottom:14px">
      <div class="bubble" style="background:var(--brand);color:var(--on-brand)">把 MarkerLayer 拆一下，太长了</div></div>'''
    composer_cls = "composer glass" if st["rows"]=="glass" or st["bg"]=="orbs" else "composer solid"
    composer = f'''<div class="{composer_cls}">
      <div style="color:var(--label3)">{ic("camera",22,"currentColor",2)}</div>
      <div style="flex:1" class="l3">继续说点什么…</div>
      <div class="send" style="background:var(--brand);color:var(--on-brand)">{ic("send",19,"currentColor",2.4)}</div></div>'''

    return f'''<div class="frame {"paper" if st["bg"]=="paper" else ""}">{orbs(d)}{statusbar(d)}{nav}
      <div class="chat-scroll">{earlier}{assistant}<div style="height:10px"></div>{tool}<div style="height:10px"></div>{approval}{bubble}</div>
      {composer}</div>'''

# ───────────── 页面 ─────────────
CSS = """
*{box-sizing:border-box}
body{margin:0;background:#0F0E0D;color:#EDE9E4;padding:44px 32px 80px;
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue",sans-serif;
  -webkit-font-smoothing:antialiased}
.wrap{max-width:1180px;margin:0 auto}
h1{font-size:32px;font-weight:700;letter-spacing:-0.02em;margin:0 0 10px}
.lede{font-size:16px;line-height:1.65;color:#A9A29A;max-width:760px;margin:0 0 8px}
.dir{margin-top:64px;padding-top:34px;border-top:1px solid rgba(255,255,255,0.10)}
.dir h2{font-size:24px;font-weight:700;letter-spacing:-0.015em;margin:0 0 4px}
.dir h2 em{font-style:normal;font-weight:500;color:#8B8379;font-size:16px;margin-left:10px}
.dir .one{font-size:15.5px;line-height:1.6;color:#B9B2A9;max-width:720px;margin:0 0 20px}
.sw{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:24px}
.sw div{display:flex;align-items:center;gap:9px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.08);
  border-radius:11px;padding:8px 13px 8px 9px;font-size:12.5px;color:#B9B2A9}
.sw i{width:26px;height:26px;border-radius:7px;display:block;flex-shrink:0;box-shadow:inset 0 0 0 1px rgba(255,255,255,0.14)}
.sw b{color:#EDE9E4;font-weight:600}
.sw s{text-decoration:none;color:#7E766C;font-size:11.5px}
.frames{display:flex;gap:26px;flex-wrap:wrap}
.meta{display:flex;gap:26px;flex-wrap:wrap;margin-top:24px}
.meta div{flex:1;min-width:230px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.07);
  border-radius:13px;padding:14px 16px;font-size:13.5px;line-height:1.6;color:#B9B2A9}
.meta strong{display:block;color:#EDE9E4;font-size:12px;font-weight:600;letter-spacing:0.08em;margin-bottom:6px}
.cap{font-size:12px;color:#7E766C;margin:10px 0 0;letter-spacing:0.02em}

/* ── 手机框 ── */
.frame{position:relative;width:390px;height:800px;overflow:hidden;border-radius:42px;
  background:var(--surface);color:var(--label);font-size:17px;line-height:1.35;letter-spacing:-0.01em;
  box-shadow:0 0 0 1px rgba(255,255,255,0.09),0 30px 70px rgba(0,0,0,0.5)}
.paper{background-image:radial-gradient(rgba(120,95,70,0.045) 0.5px,transparent 0.5px);background-size:6px 6px}
.orb{position:absolute;border-radius:999px;filter:blur(60px);opacity:0.85;pointer-events:none}
.sb{position:relative;z-index:6;height:52px;display:flex;align-items:flex-end;justify-content:space-between;padding:0 26px 6px;font-size:14px}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;letter-spacing:0}
.large-title{font-size:33px;font-weight:700;letter-spacing:-0.025em;line-height:1.12}
.eyebrow{font-size:11px;font-weight:600;letter-spacing:0.09em}
.headline{font-size:17px;font-weight:600;letter-spacing:-0.012em}
.body-t{font-size:16px;line-height:1.5}
.footnote{font-size:13px} .caption{font-size:11.5px}
.l2{color:var(--label2)} .l3{color:var(--label3)}
.body-scroll{position:relative;z-index:2;padding-top:8px}
.chip{display:inline-flex;align-items:center;gap:6px;height:26px;padding:0 10px;border-radius:999px;
  font-size:12.5px;font-weight:600;white-space:nowrap}
.dot{width:9px;height:9px;border-radius:999px;flex-shrink:0;display:block}
.code{font-size:12.5px;color:var(--label2);background:color-mix(in srgb,var(--fill) 70%,transparent);
  border-radius:8px;padding:5px 9px;display:inline-block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.searchbar{flex:1;height:38px;border-radius:11px;background:var(--fill);display:flex;align-items:center;gap:8px;padding:0 12px;font-size:15px}

/* 行承载 */
.grp{background:var(--elev);border-radius:12px;overflow:hidden}
.grp-row{background:transparent}
.grp-sep{height:1px;background:var(--border);margin-left:16px}
.p-card{background:var(--elev);border-radius:16px;border:1px solid var(--border);box-shadow:0 1px 2px rgba(80,60,40,0.04)}
.g-card{background:var(--elev);border-radius:20px;border:1px solid var(--border);
  backdrop-filter:blur(24px) saturate(180%);box-shadow:inset 0 1px 0 rgba(255,255,255,0.10)}
.m-bubble{background:var(--elev);border-radius:20px}
.b-card{background:var(--elev);border-radius:24px;box-shadow:0 1px 2px rgba(80,60,40,0.05),0 8px 24px rgba(80,60,40,0.08)}

/* tab bar */
.tabbar-sys{position:absolute;left:0;right:0;bottom:0;height:83px;z-index:6;display:flex;
  padding:8px 6px 0;background:color-mix(in srgb,var(--surface) 82%,transparent);
  backdrop-filter:blur(22px) saturate(180%);border-top:1px solid var(--border)}
.tabbar-float{position:absolute;left:18px;right:18px;bottom:20px;height:64px;border-radius:999px;z-index:6;
  display:flex;align-items:center;padding:0 6px}
.tab{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;
  height:52px;font-size:10.5px;font-weight:600;position:relative}
.tbadge{position:absolute;top:0;right:22%;min-width:17px;height:17px;padding:0 5px;border-radius:999px;
  background:var(--danger);color:#fff;font-size:10.5px;font-weight:700;display:flex;align-items:center;justify-content:center}
.glass{background:color-mix(in srgb,var(--elev) 70%,transparent);backdrop-filter:blur(26px) saturate(180%);
  box-shadow:inset 0 1px 0 rgba(255,255,255,0.22),inset 0 0 0 0.5px rgba(255,255,255,0.14),0 10px 34px rgba(40,30,20,0.18)}
.fab{position:absolute;right:18px;z-index:7;bottom:100px;height:50px;padding:0 20px 0 16px;border-radius:999px;
  display:flex;align-items:center;gap:7px;font-size:16px;font-weight:600}

/* 聊天 */
.chatnav{position:relative;z-index:6;height:50px;display:flex;align-items:center;gap:6px;padding:0 16px}
.chatnav.solid{background:color-mix(in srgb,var(--surface) 86%,transparent);backdrop-filter:blur(20px);border-bottom:1px solid var(--border)}
.chatnav.glass{margin:0 12px;border-radius:999px;height:52px;background:color-mix(in srgb,var(--elev) 70%,transparent);
  backdrop-filter:blur(26px) saturate(180%);box-shadow:inset 0 1px 0 rgba(255,255,255,0.20),0 8px 26px rgba(40,30,20,0.16)}
.chat-scroll{position:relative;z-index:2;height:622px;padding:0 16px 12px;
  display:flex;flex-direction:column;justify-content:flex-end}
.codeblock{border-radius:10px;background:color-mix(in srgb,var(--fill) 80%,transparent);
  border:1px solid var(--border);overflow:hidden;font-size:13px}
.cb-head{display:flex;align-items:center;justify-content:space-between;padding:6px 10px 4px;
  color:var(--label3);font-size:11px;border-bottom:1px solid var(--border)}
.cb-body{padding:9px 11px;color:var(--label2);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.btn{height:40px;border-radius:999px;display:flex;align-items:center;justify-content:center;
  flex:1;font-size:14.5px;font-weight:600}
.btn-ghost{background:transparent}
.bubble{max-width:74%;padding:11px 15px;border-radius:20px 20px 6px 20px;font-size:16px;line-height:1.45}
.composer{position:absolute;left:12px;right:12px;bottom:18px;z-index:7;height:52px;border-radius:999px;
  display:flex;align-items:center;gap:11px;padding:0 6px 0 14px;font-size:16px}
.composer.solid{background:var(--elev);border:1px solid var(--border);box-shadow:0 6px 22px rgba(80,60,40,0.10)}
.send{width:40px;height:40px;border-radius:999px;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.tb-btn{width:34px;height:34px;display:flex;align-items:center;justify-content:center}
"""

def page():
    blocks = ""
    for d in DIRECTIONS:
        sw = "".join(f'<div><i style="background:{c}"></i><span><b>{c}</b><br><s>{lab}{"  ·  "+extra if extra else ""}</s></span></div>'
                     for c, lab, extra in d["swatches"])
        blocks += f'''
<section class="dir dir-{d["key"]}">
  <h2>{d["title"]}<em>{d["en"]}</em></h2>
  <p class="one">{d["one"]}</p>
  <div class="sw">{sw}</div>
  <div class="frames">{screen_sessions(d)}{screen_chat(d)}</div>
  <p class="cap">左：会话列表　·　右：聊天与审批（产品最核心的两个界面）</p>
  <div class="meta">
    <div><strong>适合</strong>{d["fit"]}</div>
    <div><strong>代价</strong>{d["cost"]}</div>
    <div><strong>工作量</strong>{d["work"]}</div>
  </div>
</section>'''
    scoped = "\n".join(f'.dir-{d["key"]} {{{d["vars"]}}}' for d in DIRECTIONS)
    return f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>YzVibe 视觉方向对比</title>
<style>{CSS}
{scoped}
</style></head><body><div class="wrap">
<h1>YzVibe 视觉方向 · 4 选 1</h1>
<p class="lede">同样两个屏幕（会话列表 / 聊天与审批），四种视觉主张。四个方案的<strong>结构都已经改成苹果原生</strong>——系统大标题、List 分组、系统 Tab 栏——差异在中性色、材质、以及橙色怎么用。所有颜色对比度都已实算并标在色板上。</p>
<p class="lede">看的时候建议只问自己一个问题：<strong>哪一个更像"我想让别人截图转发的那个 App"。</strong></p>
{blocks}
</div></body></html>'''

if __name__ == "__main__":
    out = os.path.join(HERE, "index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page())
    print("wrote", out)

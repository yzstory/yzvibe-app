import build, os
HERE=os.path.dirname(os.path.abspath(__file__))
for d in build.DIRECTIONS:
    html=f'''<!doctype html><html><head><meta charset="utf-8"><style>{build.CSS}
    .dir-{d["key"]} {{{d["vars"]}}}
    body{{padding:26px;background:#0F0E0D}}
    .frames{{display:flex;gap:26px}}</style></head>
    <body><div class="dir-{d["key"]}"><div class="frames">{build.screen_sessions(d)}{build.screen_chat(d)}</div></div></body></html>'''
    open(os.path.join(HERE,f"_shot-{d['key']}.html"),"w",encoding="utf-8").write(html)
print("ok")

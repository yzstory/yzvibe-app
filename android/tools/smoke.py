#!/usr/bin/env python3
"""Run against a disposable emulator and tools/mock-connector.mjs; never use real devices."""
import os, pathlib, re, shlex, subprocess, sys, time, xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parents[2]
ADB = str(pathlib.Path(os.environ.get('ANDROID_HOME', str(pathlib.Path.home() / 'Library/Android/sdk'))) / 'platform-tools/adb')
SERIAL = os.environ.get('ANDROID_SERIAL', 'emulator-5554')
if not SERIAL.startswith('emulator-'):
    raise SystemExit('Smoke test is restricted to a disposable Android emulator')
def adb(*args):
    return subprocess.check_output([ADB, '-s', SERIAL, *args], timeout=30, text=True)
def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/yz-smoke.xml')
    return list(ET.fromstring(adb('shell', 'cat', '/sdcard/yz-smoke.xml')).iter('node'))
def wait(label, exact=False, timeout=20):
    until = time.time() + timeout
    while time.time() < until:
        for n in nodes():
            value = n.get('text') or n.get('content-desc') or ''
            if value == label if exact else label in value:
                return n
        time.sleep(.25)
    raise AssertionError('Missing UI: ' + label)
def tap(n):
    x1,y1,x2,y2 = map(int, re.findall(r'\d+', n.get('bounds')))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
def enter(text):
    edit = next(n for n in nodes() if n.get('class') == 'android.widget.EditText')
    tap(edit); adb('shell','input','text',text); adb('shell','input','keyevent','4'); time.sleep(.4)
def launch():
    adb('shell','am','start','-n','icu.yzvibe.android/.MainActivity'); wait('在线')

fixture = subprocess.Popen(['node', 'android/tools/mock-connector.mjs'], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    line = fixture.stdout.readline()
    if 'listening' not in line: raise RuntimeError(line)
    apk = ROOT / 'android/app/build/outputs/apk/debug/app-debug.apk'
    adb('install','-r',str(apk)); adb('shell','pm','clear','icu.yzvibe.android'); adb('reverse','tcp:29876','tcp:29876')
    link = pathlib.Path('/tmp/yz-android-smoke-pair.txt').read_text()
    adb('shell','am','start','-n','icu.yzvibe.android/.MainActivity','-a','android.intent.action.VIEW','-d',shlex.quote(link))
    wait('在线'); tap(wait('Android 联调会话',True)); wait('欢迎使用')
    enter('draft_survives_123')
    tap(wait('返回',True)); tap(wait('草稿保留测试',True)); wait('OMP')
    tap(wait('返回',True)); tap(wait('Android 联调会话',True)); wait('draft_survives_123',True)
    adb('shell','am','force-stop','icu.yzvibe.android'); launch(); tap(wait('Android 联调会话',True)); wait('draft_survives_123',True)
    print('PASS draft survives session switch and process restart', flush=True)
    tap(wait('发送',True)); wait('收到「draft_survives_123')
    wait('发消息给 codex',True)
    print('PASS durable delivery and streamed reply', flush=True)
    enter('deploy_test')
    tap(wait('发送',True)); time.sleep(2)
    tap(wait('更多',True)); tap(wait('审批',True)); tap(wait('允许',True)); time.sleep(1)
    adb('shell','input','keyevent','4'); wait('任务完成')
    print('PASS approval request and allow response', flush=True)
    # Scroll to the first message and tap the rendered document link.
    for _ in range(3): adb('shell','input','swipe','500','500','500','1500','400')
    first = wait('查看 Markdown'); x1,y1,x2,y2=map(int,re.findall(r'\d+',first.get('bounds')))
    adb('shell','input','tap',str(x1+130),str(y2-28)); wait('Android 文件预览')
    print('PASS rendered remote Markdown', flush=True)
    output=ROOT/'android/app/build/outputs/smoke'; output.mkdir(parents=True,exist_ok=True)
    adb('shell','screencap','-p','/sdcard/yz-smoke.png'); adb('pull','/sdcard/yz-smoke.png',str(output/'markdown.png'))
finally:
    fixture.terminate()
    try: fixture.wait(timeout=5)
    except subprocess.TimeoutExpired: fixture.kill()

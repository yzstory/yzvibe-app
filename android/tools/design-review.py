#!/usr/bin/env python3
"""Compose regression and screenshots on a disposable emulator; clears its App test data."""
import os
import pathlib
import shlex
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SDK = pathlib.Path(os.environ.get('ANDROID_HOME', pathlib.Path.home() / 'Library/Android/sdk'))
ADB = str(SDK / 'platform-tools/adb')
SERIAL = os.environ.get('ANDROID_SERIAL', 'emulator-5554')
if not SERIAL.startswith('emulator-'):
    raise SystemExit('Use a disposable emulator: this test clears App test data.')
PARITY = os.environ.get('YZVIBE_UI_SUITE') == 'parity'
FOLDER = 'parity-review' if PARITY else 'design-review'
TEST_CLASS = 'ParityFlowTest' if PARITY else 'DesignFlowTest'
OUTPUT = ROOT / 'android/app/build/outputs' / FOLDER


def adb(*args, timeout=30):
    return subprocess.check_output([ADB, '-s', SERIAL, *args], text=True, timeout=timeout)


old_font = adb('shell', 'settings', 'get', 'system', 'font_scale').strip()
old_night = adb('shell', 'cmd', 'uimode', 'night').strip().split()[-1]
try:
    adb('install', '-r', str(ROOT / 'android/app/build/outputs/apk/debug/app-debug.apk'))
    adb('install', '-r', str(ROOT / 'android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'))
    for name, night, scale in [('dark', 'yes', '1.0'), ('light', 'no', '1.0'), ('large', 'no', '1.3')]:
        fixture = subprocess.Popen(['node', 'android/tools/mock-connector.mjs'], cwd=ROOT,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            if 'listening' not in fixture.stdout.readline():
                raise RuntimeError('Could not start isolated fixture; check port 29876.')
            adb('shell', 'pm', 'clear', 'icu.yzvibe.android')
            adb('reverse', 'tcp:29876', 'tcp:29876')
            adb('shell', 'cmd', 'uimode', 'night', night)
            adb('shell', 'settings', 'put', 'system', 'font_scale', scale)
            pair = pathlib.Path('/tmp/yz-android-smoke-pair.txt').read_text().strip()
            result = adb('shell', 'am', 'instrument', '-w', '-e', 'pairUri', shlex.quote(pair),
                         '-e', 'class', f'icu.yzvibe.android.{TEST_CLASS}',
                         'icu.yzvibe.android.test/androidx.test.runner.AndroidJUnitRunner', timeout=90)
            directory = OUTPUT / name
            directory.mkdir(parents=True, exist_ok=True)
            (directory / 'test-result.txt').write_text(result.replace(pair, '[redacted]'))
            if 'OK (1 test)' not in result:
                raise RuntimeError(f'{name} failed; see {directory / "test-result.txt"}')
            adb('pull', f'/sdcard/Android/data/icu.yzvibe.android/files/{FOLDER}/', str(directory))
            print(f'PASS {name}: {TEST_CLASS}; screenshots saved.', flush=True)
        finally:
            fixture.terminate()
            try:
                fixture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
finally:
    if old_font == 'null':
        adb('shell', 'settings', 'delete', 'system', 'font_scale')
    else:
        adb('shell', 'settings', 'put', 'system', 'font_scale', old_font)
    adb('shell', 'cmd', 'uimode', 'night', old_night)

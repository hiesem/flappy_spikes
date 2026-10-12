#!/usr/bin/env python3
"""PRD-2.2 §33.3 soak run on the Pixel 8: ONE command builds the FS_SOAK
profile APK, installs it over the existing app (same upload key, data kept),
plays 20 games unattended and records the §33.3 numbers after games
1, 2, 5, 10, 20 plus one Perfetto trace around game 10.

    python3 tool/soak.py --label baseline-2.1 [--no-build] [--serial S]

Output: docs/p22/perf/<label>/ (soak.csv, soak.json, logcat.txt, raw dumps,
trace_g10.perfetto-trace). The in-app driver lives in lib/services/soak.dart;
the counters in lib/game/audio_counter.dart.

Needs: flutter/adb on PATH (CLAUDE.md "Commands"), android/app/key.properties
+ android/upload-keystore.jks for an install over a release build.
The screen brightness is fixed for the run (manual, --brightness) and the old
values are restored at the end; nothing else on the phone is changed.
"""
import argparse
import csv
import json
import os
import re
import subprocess
import sys
import threading
import time

PKG = 'com.flappyspikes.flappy_spikes'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sh(args, check=False, timeout=180):
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        sys.exit(f'failed: {" ".join(args)}\n{r.stdout}\n{r.stderr}')
    return r.stdout


class Phone:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *a, timeout=180):
        return sh(['adb', '-s', self.serial, *a], timeout=timeout)

    def shell(self, cmd, timeout=180):
        return self.adb('shell', cmd, timeout=timeout)

    def pid(self):
        return self.shell(f'pidof {PKG}').strip().split(' ')[0]

    def skin_temp(self):
        # The live HAL values ("Cached temperatures" can be stale).
        t = self.shell('dumpsys thermalservice')
        t = t[t.find('Current temperatures from HAL'):]
        m = re.search(r'mValue=([\d.]+), mType=3, mName=VIRTUAL-SKIN,', t)
        return float(m.group(1)) if m else None

    def battery_temp(self):
        m = re.search(r'temperature: (\d+)', self.shell('dumpsys battery'))
        return int(m.group(1)) / 10 if m else None

    def thermal_status(self):
        m = re.search(r'Thermal Status: (\d+)',
                      self.shell('dumpsys thermalservice'))
        return int(m.group(1)) if m else None

    def proc_ticks(self, pid):
        # utime + stime (fields 14, 15) in clock ticks (100 Hz).
        s = self.shell(f'run-as {PKG} cat /proc/{pid}/stat').strip()
        if not s or 'No such' in s:
            s = self.shell(f'cat /proc/{pid}/stat').strip()
        f = s[s.rfind(')') + 2:].split()
        return int(f[11]) + int(f[12])

    def threads(self, pid):
        s = self.shell(f'run-as {PKG} cat /proc/{pid}/status')
        if 'Threads' not in s:
            s = self.shell(f'cat /proc/{pid}/status')
        m = re.search(r'Threads:\s+(\d+)', s)
        return int(m.group(1)) if m else None


def parse_meminfo(t):
    def kb(label):
        m = re.search(rf'^\s*{label}:\s+(\d+)', t, re.M)
        return int(m.group(1)) if m else None
    # App Summary section (KB).
    return {
        'pss_kb': kb('TOTAL PSS') or kb('TOTAL'),
        'native_kb': kb('Native Heap'),
        'graphics_kb': kb('Graphics'),
        'java_kb': kb('Java Heap'),
        'code_kb': kb('Code'),
    }


def parse_flinger(t):
    tracks = active = 0
    for m in re.finditer(r'(\d+) Tracks? of which (\d+) (?:is|are) active', t):
        tracks += int(m.group(1))
        active += int(m.group(2))
    clients = len(re.findall(r'^\s*pid:\s*\d+', t, re.M))
    return {'af_tracks': tracks, 'af_active': active, 'af_clients': clients}


def parse_gfx(t):
    m = {}
    for k, rx in [('gfx_frames', r'Total frames rendered: (\d+)'),
                  ('gfx_janky_pct', r'Janky frames: \d+ \(([\d.]+)%\)'),
                  ('gfx_p50', r'50th percentile: (\d+)ms'),
                  ('gfx_p90', r'90th percentile: (\d+)ms')]:
        r = re.search(rx, t)
        m[k] = float(r.group(1)) if r else None
    return m


def parse_app(line):
    """key=value pairs of an FS_SOAK line (frame stats and audio counters)."""
    d = {}
    for k, v in re.findall(r'(\w+)=([\w.%/-]+)', line):
        d[k] = v.rstrip('%')
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', required=True)
    ap.add_argument('--serial', default='38300DLJH004SD')
    ap.add_argument('--no-build', action='store_true')
    ap.add_argument('--games', type=int, default=20)
    ap.add_argument('--hold', type=int, default=100)
    ap.add_argument('--brightness', type=int, default=128)
    ap.add_argument('--start-temp', type=float, default=31.0,
                    help='wait (max 15 min) until VIRTUAL-SKIN <= this')
    ap.add_argument('--trace-game', type=int, default=10)
    ap.add_argument('--no-banner', action='store_true',
                    help='S7-19 diagnosis: build without the gameplay banner')
    a = ap.parse_args()

    out = os.path.join(ROOT, 'docs', 'p22', 'perf', a.label)
    os.makedirs(os.path.join(out, 'raw'), exist_ok=True)
    ph = Phone(a.serial)
    if a.serial not in sh(['adb', 'devices']):
        sys.exit(f'{a.serial} not attached')

    apk = os.path.join(ROOT, 'build/app/outputs/flutter-apk/app-profile.apk')
    if not a.no_build:
        sh(['flutter', 'build', 'apk', '--profile', '--dart-define=FS_SOAK=true',
            f'--dart-define=FS_SOAK_GAMES={a.games}',
            f'--dart-define=FS_SOAK_HOLD={a.hold}',
            *(['--dart-define=FS_SOAK_NO_BANNER=true'] if a.no_banner else [])],
           check=True, timeout=1800)
    r = ph.adb('install', '-r', apk, timeout=600)
    if 'Success' not in r:
        sys.exit(f'install failed: {r}')

    old_mode = ph.shell('settings get system screen_brightness_mode').strip()
    old_bri = ph.shell('settings get system screen_brightness').strip()
    ph.shell('settings put system screen_brightness_mode 0')
    ph.shell(f'settings put system screen_brightness {a.brightness}')
    meta = {'label': a.label, 'serial': a.serial, 'games': a.games,
            'no_banner': a.no_banner,
            'hold_s': a.hold, 'brightness': a.brightness,
            'old_brightness': [old_mode, old_bri],
            'stay_on': ph.shell('settings get global stay_on_while_plugged_in').strip(),
            'android': ph.shell('getprop ro.build.version.release').strip(),
            'version': re.findall(r'versionName=(\S+)',
                                  ph.shell(f'dumpsys package {PKG}'))[:1]}
    rows = []
    try:
        ph.shell(f'am force-stop {PKG}')
        t0 = time.time()
        while True:
            st = ph.skin_temp()
            if st is None or st <= a.start_temp or time.time() - t0 > 900:
                break
            print(f'cooling: skin {st} °C', flush=True)
            time.sleep(30)
        meta['start_skin_c'] = ph.skin_temp()
        meta['start_battery_c'] = ph.battery_temp()
        meta['start_thermal_status'] = ph.thermal_status()
        print('start', meta, flush=True)

        ph.adb('logcat', '-c')
        ph.shell(f'am start -n {PKG}/.MainActivity --ez trace-systrace true')
        log = subprocess.Popen(
            ['adb', '-s', a.serial, 'logcat', '-v', 'time', '-s', 'flutter:I'],
            stdout=subprocess.PIPE, text=True)
        logf = open(os.path.join(out, 'logcat.txt'), 'w')
        hold_line = {}
        pid = None
        trace_started = False
        for line in log.stdout:
            logf.write(line)
            logf.flush()
            if 'FS_SOAK' not in line:
                continue
            print(line.strip()[:240], flush=True)
            pid = pid or ph.pid()
            app = parse_app(line)
            if 'FS_SOAK start ' in line:
                g = int(app['game'])
                ph.shell(f'dumpsys gfxinfo {PKG} reset')
                if g == a.trace_game and not trace_started:
                    trace_started = True
                    ph.shell('perfetto --background -o /data/misc/perfetto-traces/'
                             'soak_g10.perfetto-trace -t 40s -b 96mb '
                             f'-a {PKG} sched freq idle gfx view input dalvik '
                             'binder_driver audio hal am wm power')
            elif 'FS_SOAK death ' in line:
                hold_line.setdefault(int(app['game']), {})['run'] = app
            elif 'FS_SOAK game-end ' in line:
                hold_line.setdefault(int(app['game']), {})['post'] = app
            elif 'FS_SOAK hold game=' in line:
                g = int(app['game'])
                rec = {'game': g, 'pid': pid}
                rec.update({f'app_{k}': v for k, v in app.items()
                            if k in ('players', 'creates', 'disposes',
                                     'releases', 'pools', 'pooled',
                                     'evicted', 'steals',
                                     'posPolls', 'resumes')})
                run = hold_line.get(g, {}).get('run', {})
                rec.update({f'run_{k}': run.get(k) for k in
                            ('frames', 'p50', 'p90', 'p99', 'max', 'jank',
                             'build90', 'raster90', 'hoops')})
                gfx = ph.shell(f'dumpsys gfxinfo {PKG} framestats')
                open(os.path.join(out, 'raw', f'gfx_g{g}.txt'), 'w').write(gfx)
                rec.update(parse_gfx(gfx))
                mem = ph.shell(f'dumpsys meminfo {PKG}')
                open(os.path.join(out, 'raw', f'meminfo_g{g}.txt'), 'w').write(mem)
                rec.update(parse_meminfo(mem))
                af = ph.shell('dumpsys media.audio_flinger')
                open(os.path.join(out, 'raw', f'flinger_g{g}.txt'), 'w').write(af)
                rec.update(parse_flinger(af))
                rec['threads'] = ph.threads(pid)
                # 60 s idle on Home: the app's CPU share.
                c0, w0 = ph.proc_ticks(pid), time.time()
                time.sleep(60)
                c1, w1 = ph.proc_ticks(pid), time.time()
                rec['idle_cpu_pct'] = round((c1 - c0) / (w1 - w0), 1)
                cpu = ph.shell('dumpsys cpuinfo')
                open(os.path.join(out, 'raw', f'cpuinfo_g{g}.txt'), 'w').write(cpu)
                rec['thermal_status'] = ph.thermal_status()
                rec['skin_c'] = ph.skin_temp()
                rec['battery_c'] = ph.battery_temp()
                rec['wall_s'] = round(time.time() - t0)
                rows.append(rec)
                hold_line[g]['hold_app'] = app
                print('measured', json.dumps(rec), flush=True)
            elif 'FS_SOAK hold-end' in line:
                g = int(app['game'])
                for rec in rows:
                    if rec['game'] == g:
                        h = hold_line[g]['hold_app']
                        dt = float(app['t']) - float(h['t'])
                        rec['idle_pos_polls_per_s'] = round(
                            (int(app.get('posPolls', 0)) -
                             int(h.get('posPolls', 0))) / dt, 1)
                        rec.update({f'idle_{k}': app.get(k) for k in
                                    ('frames', 'p50', 'p90', 'jank')})
                        if 'post' in hold_line[g]:
                            p = hold_line[g]['post']
                            rec.update({f'post_{k}': p.get(k) for k in
                                        ('frames', 'p90', 'jank')})
            if 'FS_SOAK done' in line:
                break
        log.terminate()
        logf.close()
        if trace_started:
            time.sleep(2)
            ph.adb('pull', '/data/misc/perfetto-traces/soak_g10.perfetto-trace',
                   os.path.join(out, 'trace_g10.perfetto-trace'), timeout=300)
    finally:
        ph.shell(f'settings put system screen_brightness_mode {old_mode}')
        ph.shell(f'settings put system screen_brightness {old_bri}')
        meta['rows'] = rows
        json.dump(meta, open(os.path.join(out, 'soak.json'), 'w'), indent=1)
        if rows:
            keys = []
            for r in rows:
                keys += [k for k in r if k not in keys]
            with open(os.path.join(out, 'soak.csv'), 'w', newline='') as f:
                w = csv.DictWriter(f, fieldnames=keys)
                w.writeheader()
                w.writerows(rows)
        print('wrote', out, flush=True)


if __name__ == '__main__':
    main()

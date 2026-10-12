#!/usr/bin/env python3
"""QA host helpers. All interactions are recorded, always on the named Pixel.
Import from a scenario script, or run: drive.py status / shot NAME / cmd JSON.
"""
import json
import pathlib
import shlex
import subprocess
import sys
import time

OUT = pathlib.Path(__file__).resolve().parent
SERIAL = '38300DLJH004SD'
PKG = 'com.flappyspikes.flappy_spikes'

def adb(*args, data=None, binary=False, timeout=60):
    argv = ['adb', '-s', SERIAL, *map(str, args)]
    r = subprocess.run(argv, input=data, capture_output=True, timeout=timeout)
    with (OUT / 'interactions.jsonl').open('a') as f:
        f.write(json.dumps({'time': time.time(), 'argv': argv,
            'input': data.decode() if data else None, 'code': r.returncode,
            'output': None if binary else r.stdout.decode(errors='replace')[:1500],
            'stderr': r.stderr.decode(errors='replace')[:1500]}) + '\n')
    if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout if binary else r.stdout.decode(errors='replace')

def state():
    for _ in range(20):
        try:
            return json.loads(adb('exec-out', 'run-as', PKG, 'cat', 'code_cache/qa_state.json'))
        except (ValueError, RuntimeError): time.sleep(.1)
    raise RuntimeError('No readable harness state')

def cmd(op, **args):
    seq = time.time_ns() // 1000
    obj = dict(seq=seq, op=op, **args)
    # stdin carries JSON as data; shell text contains only this fixed path.
    adb('shell', 'run-as', PKG, 'sh', '-c', shlex.quote('cat > code_cache/qa_command.pending'),
        data=json.dumps(obj).encode())
    adb('shell','run-as',PKG,'mv','code_cache/qa_command.pending','code_cache/qa_command.json')
    return until(lambda s: s['seq'] == seq, seconds=20)

def until(predicate, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        s = state()
        if predicate(s): return s
        time.sleep(.2)
    raise RuntimeError('Timeout: ' + json.dumps(state()))

def tap(x, y):
    if not foreground(): raise RuntimeError('Refuse tap outside app activity')
    adb('shell', 'input', 'tap', round(x*3.375), round(y*3.375))

def start():
    for _ in range(5):
        if not state()['modal']: break
        cmd('close'); time.sleep(.4)
    s=state()
    tap(*s['start'])
    return until(lambda s: s['state']=='playing', seconds=30)

def foreground():
    focus=[x for x in adb('shell','dumpsys','window').splitlines() if 'mCurrentFocus=' in x]
    return bool(focus and PKG in focus[0] and 'MainActivity' in focus[0])

def launch():
    adb('shell','am','force-stop',PKG)
    adb('shell','run-as',PKG,'rm','-f','code_cache/qa_command.json','code_cache/qa_command.pending','code_cache/qa_state.json')
    adb('shell','am','start','-n',PKG+'/.MainActivity')
    for _ in range(20):
        try: s=state(); break
        except RuntimeError: time.sleep(.5)
    else: raise RuntimeError('Harness did not boot')
    for _ in range(5):
        if not state()['modal']: break
        cmd('close');time.sleep(.4)
    time.sleep(.4)
    return state()

def decline():
    s=state();tap(160,s['height']/2+169.5)

def back():
    adb('shell', 'input', 'swipe', 2, 1200, 400, 1200, 150)
    time.sleep(.8)

def shot(name):
    (OUT / 'shots').mkdir(exist_ok=True)
    (OUT / 'shots' / (name+'.png')).write_bytes(adb('exec-out','screencap','-p',binary=True))

def snapshot(name):
    s=state()
    (OUT / 'states').mkdir(exist_ok=True)
    (OUT / 'states' / (name+'.json')).write_text(json.dumps(s,indent=2)+'\n')
    shot(name)
    (OUT / 'states' / (name+'_activity.txt')).write_text(adb('shell','dumpsys','activity','activities'))
    print(name, json.dumps(s), flush=True)
    return s

def record(name):
    (OUT / 'recordings').mkdir(exist_ok=True)
    path='/sdcard/qa_'+name+'.mp4'
    argv=['adb','-s',SERIAL,'shell','screenrecord','--time-limit','20',
          '--bit-rate','1000000','--size','540x1200',path]
    with (OUT/'interactions.jsonl').open('a') as f:
        f.write(json.dumps({'time':time.time(),'argv':argv})+'\n')
    return subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE), path

def finish_record(handle, name):
    p,path=handle
    p.communicate(timeout=25)
    adb('pull',path,OUT/'recordings'/(name+'.mp4'))
    adb('shell','rm',path)

if __name__=='__main__':
    if sys.argv[1]=='status': print(json.dumps(state(),indent=2))
    elif sys.argv[1]=='shot': snapshot(sys.argv[2])
    elif sys.argv[1]=='cmd':
        obj=json.loads(sys.argv[2]); print(json.dumps(cmd(obj.pop('op'),**obj)))

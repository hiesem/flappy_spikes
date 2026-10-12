"""S7-20 fix verification: one real edge swipe / one KEYCODE_BACK per case."""
import json, pathlib, sys, time
sys.path.insert(0, '/home/killerhis/Projects/flappyspikes/.worktrees/g7-fin-back/docs/p22/device')
import drive
OUT = pathlib.Path('/home/killerhis/Projects/flappyspikes/.worktrees/g7-fin-back/docs/p22/device/back_fix')
drive.OUT = OUT
from drive import adb, cmd, decline, foreground, launch, snapshot, start, until

def resumed():
    lines = [l.strip() for l in adb('shell','dumpsys','activity','activities').splitlines() if 'topResumedActivity' in l]
    return lines[0] if lines else ''

def do_back(kind):
    if kind == 'swipe':
        adb('shell','input','swipe',2,1200,400,1200,150)
    else:
        adb('shell','input','keyevent','KEYCODE_BACK')
    time.sleep(1.0)

MENUS = ['settings','shop','skins','levels','debug','no_ads','level_up',
         'purchase_cancelled','purchase_failed','celebration']
cases = MENUS + ['nested_shop_skins','delete_confirm','home','playing','paused','run_settings','results']
KINDS = [a[5:] for a in sys.argv[1:] if a.startswith('kind=')] or ['swipe','key']
only = [a for a in sys.argv[1:] if not a.startswith('kind=')] or None
results = json.loads((OUT/'results.json').read_text()) if (OUT/'results.json').exists() else []
results = [r for r in results if not only or r['case'].split('_',1)[1] not in only or r['case'].split('_',1)[0] not in KINDS]
for kind in KINDS:
    for c in cases:
        if only and c not in only: continue
        name = f'{kind}_{c}'
        launch()
        if c == 'nested_shop_skins':
            cmd('open', screen='shop'); time.sleep(.6); cmd('open', screen='skins')
        elif c == 'delete_confirm':
            cmd('open', screen='settings'); time.sleep(.6); cmd('open', screen='delete_confirm')
        elif c in ['playing','paused','run_settings','results']:
            cmd('prepare', bot=True, god=True); start(); cmd('passes', count=4)
            if c in ['paused','run_settings']:
                cmd('pause')
                if c == 'run_settings': cmd('open', screen='run_settings')
            elif c == 'results':
                cmd('kill'); st = until(lambda s: (s['state']=='reviving' and s['reviveUi']==1) or s['state'] in ['results','bonus'])
                if st['state']=='reviving': decline()
                until(lambda s: s['state'] in ['results','bonus'])
        elif c != 'home':
            cmd('open', screen=c)
        time.sleep(.9)
        before = snapshot(name+'_before')
        do_back(kind)
        fg = foreground(); res = resumed()
        after = snapshot(name+'_after')
        if c in MENUS:
            ok = after['menu']=='home' and not after['modal'] and not after['debug']
        elif c == 'nested_shop_skins':
            ok = after['menu']=='shop' and not after['modal']
        elif c == 'delete_confirm':
            ok = after['menu']=='settings' and not after['modal']
        elif c == 'home':
            ok = after['state']=='start' and after['menu']=='home'
        else:
            ok = after['state']==before['state'] and after['menu']==before['menu'] and after['modal']==before['modal']
        ok = bool(ok and fg and 'MainActivity' in res)
        results.append(dict(case=name, pass_=ok, foreground=fg, resumed=res,
                            before={k:before.get(k) for k in ['state','menu','modal','debug']},
                            after={k:after.get(k) for k in ['state','menu','modal','debug']}))
        print(name, 'PASS' if ok else 'FAIL', results[-1]['before'], '->', results[-1]['after'], flush=True)
        (OUT/'results.json').write_text(json.dumps(results, indent=2)+'\n')

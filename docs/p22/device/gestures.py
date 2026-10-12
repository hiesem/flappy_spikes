"""Every case starts fresh; physical gestures must keep MainActivity foreground."""
import json,time
from drive import OUT,adb,back,cmd,decline,finish_record,foreground,launch,record,snapshot,start,state,tap,until
results=[]
for screen in ['home','settings','shop','skins','levels','debug','no_ads',
               'level_up','purchase_cancelled','purchase_failed','celebration','delete_confirm',
               'playing','paused','run_settings','revive','results','bonus']:
    launch()
    if screen=='delete_confirm':
        cmd('open',screen='settings');time.sleep(.5);cmd('open',screen=screen)
    elif screen in ['playing','paused','run_settings','revive','results','bonus']:
        cmd('prepare',bot=True,god=True);start();cmd('passes',count=6)
        if screen in ['paused','run_settings']:
            cmd('pause')
            if screen=='run_settings':cmd('open',screen=screen)
        elif screen in ['revive','results','bonus']:
            if screen=='bonus':cmd('feathers',count=3)
            cmd('kill');until(lambda s:s['state']=='reviving' and s['reviveUi']==1)
            if screen in ['results','bonus']:
                decline();until(lambda s:s['state'] in ['results','bonus'])
    elif screen!='home':cmd('open',screen=screen)
    time.sleep(.6)
    before=snapshot('back_'+screen+'_before')
    h=record('back_'+screen) if screen in ['home','shop','playing'] else None
    back()
    after=snapshot('back_'+screen+'_after')
    fg=foreground()
    ok=fg and ((after['menu']=='home' and not after['modal'] and not after['debug'])
               if screen in ['settings','shop','skins','levels','debug','no_ads','level_up',
                             'purchase_cancelled','purchase_failed','celebration']
               else (after['menu']=='settings' and not after['modal']) if screen=='delete_confirm' else True)
    results.append(dict(screen=screen,pass_=ok,foreground=fg,before=before,after=after))
    (OUT/'gesture_results.json').write_text(json.dumps(results,indent=2)+'\n')
    if h:finish_record(h,'back_'+screen)
launch();cmd('open',screen='settings');time.sleep(.7)
snapshot('key_back_settings_before');adb('shell','input','keyevent','KEYCODE_BACK');time.sleep(.7)
snapshot('key_back_settings_after')
launch()

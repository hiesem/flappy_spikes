"""Physical NEXT / TEST ad close and in-memory guard probes."""
import json,time,xml.etree.ElementTree as ET
from drive import *

launch()
snapshot('interstitial_loading_guard')
cmd('games',count=2);snapshot('interstitial_first_runs_guard')
cmd('no_ads',value=True);snapshot('interstitial_no_ads_guard')
cmd('no_ads',value=False);cmd('games',count=10)
cmd('prepare',seed=7,bot=True,god=True);start()
until(lambda s:s['interstitialLoaded'],seconds=50)
adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(.5)
snapshot('interstitial_background_guard')
adb('shell','am','start','-n',PKG+'/.MainActivity');time.sleep(.7)
cmd('resume')
cmd('passes',count=10);cmd('kill')
until(lambda s:s['state']=='reviving' and s['reviveUi']==1);decline()
until(lambda s:s['state']=='results');time.sleep(2)
snapshot('results_native_level_rays')
# NEXT also settles any owed CLAIM. It is anchored 65 pt above the bottom.
h=record('interstitial_after_next')
tap(160,state()['height']-90)
until(lambda s:s['interstitial'],seconds=20);time.sleep(2)
snapshot('interstitial_native_suspended')
deadline=time.monotonic()+50
while time.monotonic()<deadline:
    adb('shell','uiautomator','dump','/sdcard/qa_interstitial.xml')
    xml=adb('exec-out','cat','/sdcard/qa_interstitial.xml')
    (OUT/'interstitial.xml').write_text(xml)
    # Only explicit Close / × nodes, never ad content or install buttons.
    root=ET.fromstring(xml)
    closes=[n for n in root.iter('node') if
            n.get('content-desc','').lower() in ('close','close ad') or
            n.get('text','') in ('×','✕')]
    if closes:
        import re
        n=closes[-1];x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
        shot('interstitial_test_close')
        adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
        time.sleep(1)
        if not state()['interstitial']:break
    time.sleep(2)
until(lambda s:s['state']=='start' and not s['interstitial'],seconds=20)
snapshot('interstitial_home_restored')
finish_record(h,'interstitial_after_next')
for _ in range(5):
    if not state()['modal']:break
    cmd('close')
cmd('prepare',seed=8,bot=True,god=True);start()
snapshot('interstitial_cooldown_guard')
cmd('passes',count=6);cmd('kill')
until(lambda s:s['state']=='reviving' and s['reviveUi']==1);decline()
until(lambda s:s['state']=='results');time.sleep(1)
tap(160,state()['height']-90)
until(lambda s:s['state']=='start',seconds=20)
snapshot('interstitial_cooldown_next_skipped')
adb('shell','rm','-f','/sdcard/qa_interstitial.xml')

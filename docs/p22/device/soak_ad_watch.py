"""Close only Google TEST ads if the merged §7 flow interrupts the legacy soak.
Does not interact with consent, billing, sign-in, external apps or real ad units.
Stop by creating soak_watch.stop. Profile/debug IDs are verified in ads_service.
"""
import json,pathlib,re,subprocess,time,xml.etree.ElementTree as ET
from drive import OUT,adb,shot
n=0
while not (OUT/'soak_watch.stop').exists():
    w=adb('shell','dumpsys','window')
    focus=[x for x in w.splitlines() if 'mCurrentFocus=' in x]
    if focus and 'AdActivity' in focus[0]:
        time.sleep(8)
        n+=1
        shot('soak_test_ad_'+str(n))
        adb('shell','uiautomator','dump','/sdcard/qa_soak_ad.xml')
        xml=adb('exec-out','cat','/sdcard/qa_soak_ad.xml')
        (OUT/('soak_ad_'+str(n)+'.xml')).write_text(xml)
        try:
            nodes=ET.fromstring(xml).iter('node')
            candidates=[]
            for node in nodes:
                a=node.attrib
                desc=a.get('content-desc','').lower()
                text=a.get('text','').lower()
                if 'close' in desc or text in ('x','×','close','close ad'):
                    v=list(map(int,re.findall(r'\d+',a.get('bounds',''))))
                    if len(v)==4 and a.get('clickable')=='true':
                        candidates.append(((v[0]+v[2])//2,(v[1]+v[3])//2))
            if candidates:
                x,y=candidates[0]
                adb('shell','input','tap',x,y)
                print('Closed test ad',n,x,y,flush=True)
            else:
                print('Test ad has no accessible close button yet',n,flush=True)
        except ET.ParseError: pass
    time.sleep(8)

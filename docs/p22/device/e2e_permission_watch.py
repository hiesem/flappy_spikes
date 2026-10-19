import pathlib,subprocess,time,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parent
import os,sys
adb=['adb','-s',os.environ.get('FS_DEVICE') or sys.exit('No device: set FS_DEVICE=<adb serial>')]
for i in range(50):
    s=subprocess.run(adb+['shell','dumpsys','window'],capture_output=True,text=True).stdout
    focus=[x for x in s.splitlines() if 'mCurrentFocus=' in x]
    if focus and 'GrantPermissionsActivity' in focus[0]:
        subprocess.run(adb+['shell','uiautomator','dump','/sdcard/qa_permission.xml'],capture_output=True)
        xml=subprocess.run(adb+['exec-out','cat','/sdcard/qa_permission.xml'],capture_output=True).stdout
        (root/'e2e_permission.xml').write_bytes(xml)
        for n in ET.fromstring(xml).iter('node'):
            if n.attrib.get('text')=='Allow' and n.attrib.get('package')=='com.google.android.permissioncontroller':
                import re
                v=list(map(int,re.findall(r'\d+',n.attrib['bounds'])))
                argv=adb+['shell','input','tap',str((v[0]+v[2])//2),str((v[1]+v[3])//2)]
                subprocess.run(argv,capture_output=True)
                print('Reminder e2e permission accepted:', ' '.join(argv),flush=True)
                raise SystemExit()
    time.sleep(20)

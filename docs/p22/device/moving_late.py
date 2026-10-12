import json,time,pathlib
from drive import *
seen=set()
for seed in range(30):
    launch();cmd('prepare',seed=seed,index=60,force=['moving_ring'],bot=True,god=True);start()
    s=until(lambda s:any(r['motion'] is not None and not r['resolved'] for r in s['rings']),seconds=15)
    m=next(r['motion'] for r in s['rings'] if r['motion'] is not None and not r['resolved'])
    if m not in seen:
        snapshot('moving_'+m+'_approach')
        h=record('moving_'+m)
        until(lambda s:s['hoops']>=1,seconds=15)
        snapshot('moving_'+m+'_passed')
        finish_record(h,'moving_'+m)
        seen.add(m)
        (OUT/'moving_types.json').write_text(json.dumps(sorted(seen))+'\n')
    else:time.sleep(2.5)
    print('seed',seed,'motion',m,'seen',seen,flush=True)
    if {'rail','swing','horizontal','diagonal','orbit','rock'}<=seen:break
else: print('Not every type seen in 30 seeds',flush=True)

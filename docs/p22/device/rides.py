import sys,time,json
from drive import *
for i,ride in enumerate(['cannon','space','volcano','sea','pinball','storm']):
    launch();cmd('prepare',seed=70+i,index=25,ride=ride,force=['portal'],bot=True,god=True)
    start();until(lambda s:s['ride'] is not None,seconds=60)
    h=record('ride_'+ride)
    seen=set();end=time.monotonic()+35
    while time.monotonic()<end:
        s=state()
        if s['ride'] is None:
            snapshot('ride_'+ride+'_control')
            time.sleep(2.3);snapshot('ride_'+ride+'_first_ring')
            break
        phase=s['ride'].split('/')[-1]
        if phase not in seen:
            seen.add(phase)
            if phase=='ride':time.sleep(.7)
            snapshot('ride_'+ride+'_'+phase)
        time.sleep(.15)
    finish_record(h,'ride_'+ride)
# The comet activity includes its quiet landing. Actual curve/physics events.
launch();cmd('prepare',seed=44,index=10,force=['comet'],bot=True,god=True)
start();until(lambda s:s['ride'] is not None and s['ride'].startswith('comet'),seconds=60)
h=record('comet_zigzag_landing')
time.sleep(2);snapshot('comet_zigzag')
until(lambda s:s['ride'] is None,seconds=30);snapshot('comet_auto_flap')
time.sleep(.4);snapshot('comet_landing_half_speed')
time.sleep(1.2);snapshot('comet_landing_full_speed')
finish_record(h,'comet_zigzag_landing')

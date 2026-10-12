import json,time
from drive import *
# Rim overlap is setup only: a real physics step produces RimTouched / egg loss.
launch();cmd('prepare',seed=7,bot=True,god=True);start();cmd('pickup',element='egg')
until(lambda s:any(not r['resolved'] and 50<r['x']<155 for r in s['rings']),seconds=20)
snapshot('egg_before_rim')
h=record('egg_rim_break')
cmd('rim_setup');time.sleep(.12);snapshot('egg_after_real_rim')
(OUT/'rumble_knock.txt').write_text(adb('shell','dumpsys','vibrator_manager'))
cmd('passes',count=1);time.sleep(.15)
snapshot('perfect_native_rumble')
(OUT/'rumble_shake.txt').write_text(adb('shell','dumpsys','vibrator_manager'))
finish_record(h,'egg_rim_break')
# Repeated forced moving rings, different seeds; no passes are injected here.
for seed in range(8):
    launch();cmd('prepare',seed=seed,index=20,force=['moving_ring'],bot=True,god=True)
    start()
    until(lambda s:any(r['motion'] is not None for r in s['rings']),seconds=15)
    snapshot('moving_seed_'+str(seed)+'_approach')
    time.sleep(4);snapshot('moving_seed_'+str(seed)+'_passed')
# Saw/spring/FEVER sizes and the native piggy coin field.
launch();cmd('prepare',seed=91,index=70,force=['saw'],bot=True,god=True);start()
snapshot('saw_hoop70');time.sleep(2)
cmd('force',element='fever');time.sleep(3);snapshot('fever_hoop70')
launch();cmd('prepare',seed=13,index=12,force=['piggy'],bot=True,god=True);start()
h=record('piggy_coins')
for _ in range(20):
    s=state()
    if s['activity']=='piggy':
        time.sleep(.3);snapshot('piggy_coins_16pt');break
    time.sleep(.3)
finish_record(h,'piggy_coins')
# Show that already-carried egg / true bird colours survive the stage change.
launch();cmd('prepare',seed=81,bot=False,god=True);start()
snapshot('bird_colours_stage0');cmd('stage',stage=3);time.sleep(.6);snapshot('bird_colours_cyan')
# Native completion sticker lifecycle, recheck the already-open QA P3 finding.
cmd('passes',count=8,perfect=False);cmd('pieces',mask=7)
cmd('pickup',element='puzzle_piece');time.sleep(1.6);snapshot('puzzle_complete_before_death')
cmd('kill');until(lambda s:s['state']=='reviving' and s['reviveUi']==1)
snapshot('puzzle_sticker_after_death')

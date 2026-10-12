"""Native visual/physics checks; setup is labelled in every state/command log."""
import json,time
from drive import OUT,adb,back,cmd,decline,finish_record,record,snapshot,start,state,tap,until

# Close any launch queue using the production back handler.
for _ in range(5):
    if not state()['modal']: break
    cmd('close')
# A real full-height mode switch and the fresh-default volume.
snapshot('home_versus');tap(*state()['modeTap']);time.sleep(.5);snapshot('home_free_fly')
cmd('open',screen='settings');time.sleep(.7);snapshot('settings_music_25');cmd('close')
cmd('prepare',seed=7,bot=True,god=True)
start();time.sleep(1);snapshot('run_banner_661')
# Check own-music recheck with the native watcher while real taps keep SFX busy.
cmd('bot',value=False);cmd('music_skip')
snapshot('music_skipped_setup')
# The next scene change must bring it back; reset this run via the normal flow.
cmd('passes',count=6);cmd('kill')
until(lambda s:s['state']=='reviving' and s['reviveUi']==1)
decline();until(lambda s:s['state']=='results')
time.sleep(2);cmd('no_ads',value=True);cmd('home');until(lambda s:s['state']=='start')
for _ in range(5):
    if not state()['modal']:break
    cmd('close')
cmd('no_ads',value=False);cmd('prepare',seed=8,bot=False,god=True)
cmd('music_skip');start()
h=record('flapping_music_return')
for i in range(12):
    tap(280,530);time.sleep(.12)
snapshot('music_return_while_flapping');finish_record(h,'flapping_music_return')
# Full-length native sound source and stop requests, no synthetic audio backend.
cmd('cue',name='perfect3');time.sleep(2.7);snapshot('perfect3_full_length')
# Fire and high-score rendering use the game's existing debugPass/addScore hooks.
cmd('passes',count=3);time.sleep(.2);snapshot('fire_3')
cmd('passes',count=2);time.sleep(.2);snapshot('fire_5')
cmd('passes',count=2);time.sleep(.2);snapshot('fire_7')
cmd('position_y',y=188);cmd('engine',value=False);snapshot('banner_behind_bird')
cmd('engine',value=True)
for score in [99999,999999,9999999]:
    cmd('score',score=score);time.sleep(.5);snapshot('score_'+str(score))
# Strong stage colour is retained on revive, grey replaces it on both pages.
cmd('stage',stage=3);cmd('feathers',count=3)
cmd('kill');until(lambda s:s['state']=='reviving' and s['reviveUi']==1)
snapshot('revive_before_idle')
h=record('revive_wait_and_empty_taps')
for x,y in [(20,130),(285,77),(160,240),(30,570),(295,600),(160,630)]:
    tap(x,y);time.sleep(.3)
snapshot('revive_after_empty_taps')
finish_record(h,'revive_wait_and_empty_taps');time.sleep(12)
snapshot('revive_after_30_seconds')
decline();until(lambda s:s['state']=='bonus')
time.sleep(1);snapshot('bonus_grey')
# Six balloon centres from the actual native layout (adjust via PNG if needed).
for x,y in [(66,288),(160,288),(254,288)]:
    tap(x,y);time.sleep(1.5)
time.sleep(1);snapshot('bonus_feather_x3_offer')
# Leave this page for the separate rewarded-ad check, avoiding purchases.

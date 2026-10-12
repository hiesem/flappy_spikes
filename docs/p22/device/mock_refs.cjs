const {chromium}=require('/home/killerhis/Projects/flappyspikes/tools/node_modules/playwright');
const path=require('path');
const fs=require('fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--allow-file-access-from-files']});
 const page=await browser.newPage({viewport:{width:1200,height:1000},deviceScaleFactor:1});
 const out=path.join(__dirname,'refs'); fs.mkdirSync(out,{recursive:true});
 const root='/home/killerhis/Projects/flappyspikes/design/menu_v2';
 for(const name of ['screen_mode_toggle3','screen_fire_choice2','screen_comet_weave','screen_portal_rides3','screen_piggy_coins2x','screen_streak_names','screen_levelup_rays_new']){
  await page.goto('file://'+root+'/'+name+'.html'+(name==='screen_comet_weave'?'?m=zig&path=1':''));
  await page.waitForTimeout(1300);
  await page.screenshot({path:path.join(out,name+'.png')});
  console.log(name, await page.locator('canvas').count());
 }
 await browser.close();
})();

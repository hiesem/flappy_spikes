// ach_art_v26.js: the 10 new 2.6 achievement icons (PRD-2.6 §7.1 D15, O94) in the 17C spike-ring style.
// Loads AFTER ach_art.js and only ADDS to it: new scenes go into SCENES, new disc ramps into RAMP.
// Nothing of the 48 approved icons changes. The ring, rays, drop shadow (frame/drawIcon) and the bird
// (bird/drawBird) are the masters from achievements.tpl.html / ach_art.js; this file never redraws them.
// Cast (same as BEAK TO BEAK): YOU = pink Classic bird with the gold sweatband, the RIVAL = Sky blue with the red band.

// ---------- extra disc ramps (new keys only) ----------
Object.assign(RAMP,{
 stratos:['#E6FAFF','#6FB7FF','#3B2C9E'],   // SKY HIGH: above the clouds
 prey:['#FFE2B0','#F0702E','#6E1020'],      // BIRD OF PREY
 steel:['#FFFFFF','#A7C0D4','#2E4A66'],     // IRON BEAK
 gem:['#FBEFFF','#C08CFF','#4B1FA6'],       // FLAWLESS
});

// ---------- helpers ----------
const YOU={c:'#EC008C',hat:'band',hatC:'#FFC400'};
const RIVAL={c:'#29B6F6',d:'#0277BD',hat:'band',hatC:'#FF3B30'};
// run fn in the same space bird() draws in (bird space, body 0..225), for props held by / worn on a bird
function onBird(c,x,y,s,rot,flip,fn){c.save();c.translate(x,y);c.rotate(rot*Math.PI/180);c.scale(flip?-s:s,s);c.translate(-118,-112);fn(c);c.restore()}
// a chunky number in the icon font: white (or gold) fill on a navy edge, so it reads on any disc
function bigText(c,t,x,y,size,col='#FFC400',rot=0){c.save();c.translate(x,y);c.rotate(rot);c.font=`${size}px Opificio, sans-serif`;c.textAlign='center';c.textBaseline='middle';
 c.lineJoin='round';c.lineWidth=size*.26;c.strokeStyle='#14204A';c.strokeText(t,0,0);c.fillStyle=col;c.fillText(t,0,0);c.restore()}
// a front-facing hoop ring (the run's hoop, seen straight on)
function ringO(c,x,y,r,w,col,colL){c.strokeStyle=col;c.lineWidth=w;c.beginPath();c.arc(x,y,r,0,TAU);c.stroke();if(colL){c.strokeStyle=colL;c.lineWidth=w*.3;c.beginPath();c.arc(x,y,r,-2.6,-1.5);c.stroke()}}
// the Golden Thread trail (F10): a gold wave with small perfect rings on it
function goldThread(c,pts,rings){c.save();A_L(c,pts,'#C98A00',16);A_L(c,pts,'#FFC400',10);c.restore();
 for(const[x,y]of rings){ringO(c,x,y,13,7,'#FFE082');A_C(c,x,y,4,'#fff')}}
// cartoon wind: a line that ends in a curl
function gust(c,x0,y,len,r,col='#fff',w=13){c.strokeStyle=col;c.lineWidth=w;c.lineCap='round';c.beginPath();c.moveTo(x0,y);c.lineTo(x0+len,y);c.arc(x0+len,y-r,r,Math.PI/2,-Math.PI*.9,true);c.stroke()}
// a 4-point star in gold with a navy edge (win marks)
function winStar(c,x,y,r){A_P(c,starPts(x,y+3,r+5),'#14204A');A_P(c,starPts(x,y,r),'#FFC400');A_P(c,starPts(x-r*.12,y-r*.12,r*.45),'#FFF3B0')}
// the Flappy Spikes trophy (leaderboard page, round 23): gold cup, pink spike crown, hoop handles, pink plinth
function fsCup(c,x,y,s){c.save();c.translate(x,y);c.scale(s,s);const G='#FFC400',D='#E69500';
 A_R(c,-70,90,140,30,'#EC008C');A_R(c,-70,90,140,8,'#FF4FB7');A_R(c,-46,68,92,22,G);A_R(c,4,68,42,22,D);
 A_R(c,-14,30,28,40,G);A_R(c,0,30,14,40,D);
 for(const sx of[-1,1]){c.strokeStyle=G;c.lineWidth=14;c.beginPath();c.ellipse(sx*78,-30,20,36,0,0,TAU);c.stroke();
  c.strokeStyle=D;c.beginPath();c.ellipse(sx*78,-30,20,36,0,sx>0?-1.2:1.9,sx>0?1.2:4.3);c.stroke()}
 c.fillStyle=G;c.beginPath();c.moveTo(-70,-80);c.lineTo(70,-80);c.lineTo(70,-50);c.quadraticCurveTo(70,12,0,26);c.quadraticCurveTo(-70,12,-70,-50);c.closePath();c.fill();
 c.fillStyle=D;c.beginPath();c.moveTo(22,-80);c.lineTo(70,-80);c.lineTo(70,-50);c.quadraticCurveTo(70,10,22,24);c.closePath();c.fill();
 c.save();c.globalAlpha=.55;A_P(c,[[-52,-70],[-36,-70],[-48,0],[-58,-20]],'#FFF3B0');c.restore();
 for(let i=0;i<5;i++){const x0=-70+i*28,h=i===2?40:30;A_P(c,[[x0,-80],[x0+28,-80],[x0+14,-80-h]],i%2?'#C40073':'#EC008C')}
 c.restore()}
// a cut diamond (FLAWLESS)
function diamond(c,x,y,s){c.save();c.translate(x,y);c.scale(s,s);
 A_P(c,[[-110,-40],[-60,-100],[60,-100],[110,-40],[0,110]],'#7FE3FF');
 A_P(c,[[-110,-40],[110,-40],[0,110]],'#29B6F6');
 A_P(c,[[-60,-100],[-20,-40],[-110,-40]],'#B4F7FF');A_P(c,[[60,-100],[20,-40],[110,-40]],'#4FC3F7');
 A_P(c,[[-60,-100],[60,-100],[20,-40],[-20,-40]],'#E1FBFF');
 A_P(c,[[-20,-40],[20,-40],[0,110]],'#81D4FA');A_P(c,[[20,-40],[110,-40],[0,110]],'#0288D1');
 c.save();c.globalAlpha=.85;A_P(c,[[-44,-90],[-26,-90],[-60,-46],[-78,-46]],'#fff');c.restore();c.restore()}

// ---------- the 10 scenes (+ alternatives B) ----------
Object.assign(SCENES,{
 // BULLSEYE: beak-first into the dead centre of a hoop-coloured target, the Golden Thread behind
 bullseye(c){
  const tx=95,ty=-20;
  for(const[r,col]of[[168,'#EC008C'],[140,'#fff'],[110,'#EC008C'],[80,'#fff'],[50,'#EC008C'],[24,'#FFC400']])A_E(c,tx,ty,r*.58,r,col);
  A_E(c,tx+6,ty,168*.58,168,'rgba(0,0,0,0)');
  c.save();c.globalAlpha=.35;A_E(c,tx-60,ty-60,14,40,'#fff',-.3);c.restore();
  goldThread(c,[[-230,150],[-180,110],[-130,135],[-90,75]],[[-180,110],[-130,135]]);
  bird(c,-30,-10,.6,-2,{...YOU,beak:'closed',eye:'fierce',brow:'angry',wing:'tuck'});
  for(const[a,l]of[[-1.2,46],[-.5,40],[.3,46],[1.1,40],[2.3,36],[-2.3,36]])A_L(c,[[tx+Math.cos(a)*44,ty+Math.sin(a)*64],[tx+Math.cos(a)*(44+l),ty+Math.sin(a)*(64+l)]],'#fff',9);
  bigText(c,'×25',-120,-150,74)},
 bullseyeB(c){ // B: right through the middle of a hoop, 25 perfect sparkles in a ring around it
  for(let i=0;i<25;i++){const a=i/25*TAU-Math.PI/2;sparkle(c,Math.cos(a)*185,Math.sin(a)*185,i%5?7:12,i%5?'#FFF3B0':'#FFC400')}
  hoopBack(c,30,0,62,160,'#EC008C');
  goldThread(c,[[-220,60],[-160,30],[-100,50],[-60,20]],[[-160,30]]);
  bird(c,0,0,.66,0,{...YOU,beak:'grin',eye:'big',wing:'up'});
  hoopFront(c,30,0,62,160,'#EC008C','#FF8FD0');
  A_C(c,30,0,12,'rgba(255,255,255,.0)');bigText(c,'×25',-90,-120,64)},

 // SKY HIGH: above the clouds, wearing the Sky Crown, hoops far below
 skyHigh(c){
  for(let i=0;i<16;i++)A_C(c,-200+hash(i+60)*400,-215+hash(i+90)*170,1.5+hash(i+4)*3,'rgba(255,255,255,.9)');
  cloud(c,-160,222,170,'#fff');cloud(c,30,240,200,'#fff');cloud(c,190,212,140,'#fff');
  cloud(c,175,130,70,'rgba(255,255,255,.75)');
  bird(c,40,-40,.68,-24,{c:'#FF7A1A',d:'#C43E00',beak:'open',eye:'wide',brow:'high',wing:'up'});
  onBird(c,40,-40,.68,-24,0,c=>{ // the Sky Crown: a gold crown whose three points are tiny hoops
   A_P(c,[[18,10],[10,-62],[64,-26],[114,-84],[164,-26],[218,-62],[210,10]],'#FFC400');A_R(c,14,-16,200,24,'#E69500');A_P(c,[[114,-84],[164,-26],[124,-26]],'#E69500');
   for(const[x,y]of[[10,-62],[114,-84],[218,-62]]){c.strokeStyle='#EC008C';c.lineWidth=11;c.beginPath();c.ellipse(x,y-26,15,24,0,0,TAU);c.stroke();c.strokeStyle='#FF8FD0';c.lineWidth=4;c.beginPath();c.ellipse(x+2,y-26,15,20,0,-1.4,-.2);c.stroke()}
   A_C(c,114,-4,11,'#EC008C')});
  for(const[x,y,r]of[[170,-150,18],[-150,-120,14]])sparkle(c,x,y,r)},

 // BIRD OF PREY: an eagle diving in for the fifth straight win, five win stars in a row
 birdOfPrey(c){
  for(let i=0;i<5;i++){const a=Math.PI*(1.1+i*.2);winStar(c,Math.cos(a)*176,Math.sin(a)*176+46,i===4?25:19)}
  bird(c,10,40,.74,22,{c:'#FFFFFF',d:'#4A2A14',ey:'#FFE082',bk:'#FFC400',bkD:'#E69500',beak:'closed',eye:'fierce',brow:'angry',wing:'spread',tail:'#5D3A1A'});
  onBird(c,10,40,.74,22,0,c=>{ // bald-eagle colours: white head, brown body; yellow legs, talons out
   A_P(c,[[0,0],[66,0],[92,140],[225,166],[225,225],[0,225]],'#6B3F22');A_P(c,[[0,150],[92,140],[225,166],[225,225],[0,225]],'#5A331B');
   A_P(c,[[30,8],[60,8],[50,120],[20,120]],'rgba(255,255,255,.14)');
   for(const x of[50,150]){A_R(c,x,225,28,50,'#FFC400');A_R(c,x+14,225,14,50,'#E69500');for(const d of[-26,0,26])A_P(c,[[x+8+d*.2,268],[x+20+d*.2,268],[x+14+d*1.3,312]],'#14204A')}})},

 // BIRDWATCHER: binoculars up, everything in the guide spotted around it
 birdwatcher(c){
  // what it has spotted: a tiny bird, a hoop, a heart, a star, a coin
  A_C(c,150,-140,52,'rgba(255,255,255,.35)');c.strokeStyle='#fff';c.lineWidth=6;c.beginPath();c.arc(150,-140,52,0,TAU);c.stroke();
  A_L(c,[[150,-200],[150,-180]],'#fff',5);A_L(c,[[150,-100],[150,-80]],'#fff',5);A_L(c,[[90,-140],[110,-140]],'#fff',5);A_L(c,[[190,-140],[210,-140]],'#fff',5);
  bird(c,150,-140,.2,-8,{c:'#FFC629',d:'#C98A00',beak:'open',wing:'up'});
  hoopBack(c,-150,-110,20,52,'#EC008C');hoopFront(c,-150,-110,20,52,'#EC008C','#FF8FD0');
  heartP(c,195,-20,.75,'#FF3B30');A_P(c,starPts(-60,-185,24),'#FFC400');coin(c,-190,0,22);
  // the watcher
  bird(c,-20,60,.74,-6,{c:'#8BC34A',d:'#558B2F',belly:'#DCEDC8',hat:'bucket',hatC:'#A1887F',hatC2:'#6D4C41',beak:'closed',eye:'big',brow:'none',wing:'tri'});
  onBird(c,-20,60,.74,-6,0,c=>{ // binoculars up to the eye, held in the wing
   A_R(c,138,-4,150,58,'#263238');A_R(c,138,-4,150,12,'#455A64');A_E(c,288,25,14,29,'#1B2429');A_E(c,290,25,9,21,'#7FE3FF');
   A_R(c,190,48,30,16,'#1B2429');
   A_R(c,128,58,172,66,'#37474F');A_R(c,128,58,172,14,'#607D8B');
   A_E(c,300,91,18,33,'#1B2429');A_E(c,302,91,12,25,'#7FE3FF');A_E(c,298,81,5,9,'#fff');
   A_P(c,[[60,160],[150,112],[236,116],[228,150],[120,196]],'#558B2F');A_P(c,[[150,112],[236,116],[230,130],[160,128]],'#7CB342')})},

 // SECOND WIND: a big gust carries you past the rival from behind
 secondWind(c){
  c.save();c.globalAlpha=.92;bird(c,-140,-50,.42,6,{...RIVAL,eye:'wide',brow:'worried',beak:'open',wing:'tri'});c.restore();
  gust(c,-230,40,170,30);gust(c,-210,110,220,38);gust(c,-240,175,150,26);
  bird(c,80,10,.7,-18,{...YOU,eye:'fierce',brow:'angry',beak:'grin',wing:'up'});
  for(const[x,y,r]of[[170,-150,16],[-40,-170,12]])sparkle(c,x,y,r)},

 // ALBATROSS: the giant wings, the rival half its size: double the score
 albatross(c){
  bird(c,40,-10,.82,-6,{c:'#FAFAFA',d:'#37474F',ey:'#fff',bk:'#FFC48A',bkD:'#F08A4B',beak:'closed',eye:'half',brow:'none',wing:'spread',tail:'#37474F',hat:'band',hatC:'#FFC400'});
  onBird(c,40,-10,.82,-6,0,c=>A_R(c,100,6,130,10,'#90A4AE'));
  bird(c,-150,150,.34,6,{...RIVAL,eye:'wide',brow:'worried',beak:'open',wing:'up'});
  bigText(c,'×2',150,150,96);
  gust(c,-230,-150,110,20,'rgba(255,255,255,.9)',10);gust(c,-200,-100,80,16,'rgba(255,255,255,.9)',10)},

 // THREE LITTLE BIRDS: three chicks on a branch, a win medal each, all on one sunny day
 threeLittleBirds(c){
  A_C(c,120,-140,40,'#FFF59D');for(let i=0;i<10;i++){const a=i/10*TAU;A_P(c,[[120+Math.cos(a-.12)*50,-140+Math.sin(a-.12)*50],[120+Math.cos(a)*72,-140+Math.sin(a)*72],[120+Math.cos(a+.12)*50,-140+Math.sin(a+.12)*50]],'#FFF59D')}
  A_P(c,[[-250,124],[250,94],[250,120],[-250,152]],'#6D4C41');A_P(c,[[150,104],[210,60],[220,70],[170,108]],'#6D4C41');A_E(c,214,58,22,12,'#7CB342',-.5);A_E(c,-205,138,22,12,'#7CB342',.4);
  const B=[[-138,52,'#FFD54F','#FFA000'],[-2,40,'#FF6E9C','#C2185B'],[134,28,'#4FC3F7','#0277BD']];
  for(const[x,y,col,d]of B){bird(c,x,y,.5,-4,{sh:'chick',c:col,d,bk:'#FF7A1A',bkD:'#E65100',beak:'small',eye:'happy',brow:'none',blush:1,wing:'tri'});
   A_L(c,[[x-18,y+34],[x-2,y+62],[x+14,y+34]],'#EC008C',8);A_C(c,x-2,y+78,22,'#E69500');A_C(c,x-2,y+76,20,'#FFC400');A_P(c,starPts(x-2,y+76,12),'#fff')}
  for(const[x,y,r]of[[-140,-90,0],[-40,-150,1]]){c.font='bold 64px Opificio, sans-serif';c.textAlign='center';c.fillStyle='#fff';c.fillText(r?'♫':'♪',x,y)}},

 // IRON BEAK: a steel beak that smashes through for 1,000+
 ironBeak(c){ // the steel beak snaps the tip off one of the ring's navy spikes
  A_P(c,[[214,-128],[214,136],[60,12]],'#0546A8');
  A_P(c,[[204,-136],[204,128],[92,26],[70,4],[96,-18],[84,-34],[104,-44]],'#14204A');A_P(c,[[204,-136],[104,-44],[84,-34],[96,-18],[70,4],[204,4]],'#24357A');
  A_L(c,[[104,-44],[130,-62],[124,-86],[150,-104]],'#fff',6);A_L(c,[[92,26],[118,44],[112,72]],'#fff',6);
  c.save();c.translate(-10,-150);c.rotate(-.55);A_P(c,[[36,-30],[-50,0],[36,30],[20,0]],'#14204A');A_P(c,[[36,-30],[-50,0],[20,0]],'#24357A');c.restore();
  for(const[a,l]of[[-2.4,44],[-2.95,56],[2.6,44],[2.1,34],[-1.9,38],[3.5,28]])A_L(c,[[56+Math.cos(a)*28,Math.sin(a)*28],[56+Math.cos(a)*(28+l),Math.sin(a)*(28+l)]],'#FFF59D',8);
  sparkle(c,52,0,30,'#FFE082');
  speed(c,[[[-240,-20],[-200,-20]],[[-245,40],[-205,40]]]);
  bird(c,-88,0,.64,0,{...YOU,eye:'fierce',brow:'angry',beak:'closed',bk:'#ECEFF1',bkD:'#90A4AE',wing:'tuck'});
  onBird(c,-88,0,.64,0,0,c=>{A_P(c,[[232,76],[296,106],[232,98]],'#fff');for(const[x,y]of[[240,104],[240,140],[268,124]])A_C(c,x,y,7,'#607D8B')});
  bigText(c,'1000',-70,150,66,'#fff',-.06)},
 ironBeakB(c){ // B: a knight's helmet instead of the broken spike
  speed(c,[[[-220,-20],[-150,-20]],[[-230,40],[-160,40]],[[-200,100],[-140,100]]]);
  bird(c,0,20,.8,-8,{...YOU,hat:'',eye:'fierce',brow:'none',beak:'closed',bk:'#ECEFF1',bkD:'#90A4AE',wing:'up'});
  onBird(c,0,20,.8,-8,0,c=>{A_P(c,[[-10,60],[-10,-30],[40,-80],[190,-80],[240,-30],[240,10],[96,10],[96,60]],'#90A4AE');A_R(c,-10,-30,250,16,'#B0BEC5');
   for(const x of[10,50,200])A_C(c,x,-50,8,'#ECEFF1');A_P(c,[[100,-80],[120,-140],[160,-150],[150,-80]],'#FF3B30');
   A_P(c,[[240,78],[290,104],[240,100]],'#fff')});
  for(const[x,y,r]of[[180,-40,18],[200,60,12]])sparkle(c,x,y,r,'#FFF59D');
  bigText(c,'1000',0,170,66,'#fff',-.06)},

 // FLAWLESS: a flawless diamond, a ×20 streak, not a scratch
 flawless(c){
  for(let i=0;i<10;i++){c.save();c.globalAlpha=.25;c.rotate(i/10*TAU);A_P(c,[[0,-60],[-18,-196],[18,-196]],'#fff');c.restore()}
  diamond(c,-60,-10,1.2);
  bird(c,110,90,.6,-8,{...YOU,beak:'grin',eye:'closed',brow:'none',wing:'hug',blush:1});
  for(const[x,y,r]of[[-170,-130,22],[40,-170,16],[-200,80,12],[180,-40,14]])sparkle(c,x,y,r);
  bigText(c,'×20',140,-130,64)},

 // TOP BIRD: #1 of the day, holding up the Flappy Spikes trophy
 topBird(c){
  for(let i=0;i<12;i++){c.save();c.globalAlpha=.28;c.rotate(i/12*TAU);A_P(c,[[0,0],[-20,-196],[20,-196]],'#FFF59D');c.restore()}
  fsCup(c,-70,10,1.3);
  bigText(c,'1',-70,-50,92,'#fff');
  bird(c,110,80,.6,-10,{...YOU,beak:'grin',eye:'happy',brow:'none',wing:'up',blush:1});
  for(const[x,y,r]of[[150,-150,20],[-190,-120,14],[190,30,12]])sparkle(c,x,y,r)},
 topBirdB(c){ // B: the top row of today's board
  const rows=[[-30,'#FFC400','#E69500','1'],[60,'#fff','#CFD8DC','2'],[140,'#fff','#CFD8DC','3']];
  for(const[y,col,d,n]of rows){const w=n==='1'?380:330,x=n==='1'?-190:-165;A_R(c,x,y,w,n==='1'?74:62,col);A_R(c,x,y+(n==='1'?62:52),w,n==='1'?12:10,d);
   c.font=`${n==='1'?52:40}px Opificio, sans-serif`;c.textAlign='center';c.textBaseline='middle';c.fillStyle=n==='1'?'#fff':'#90A4AE';c.fillText(n,x+40,y+(n==='1'?34:28));
   if(n!=='1'){A_R(c,x+90,y+18,150,14,'#ECEFF1');A_R(c,x+90,y+38,90,8,'#ECEFF1')}}
  A_R(c,-90,-12,190,14,'rgba(255,255,255,.7)');A_R(c,-90,8,120,9,'rgba(255,255,255,.6)');
  bird(c,40,-110,.56,-8,{...YOU,hat:'crown',beak:'grin',eye:'happy',brow:'none',wing:'up',blush:1});
  for(const[x,y,r]of[[170,-150,18],[-160,-120,14]])sparkle(c,x,y,r)},
});

// ---------- the catalogue (PRD-2.6 J9 / texts.html ACH-49 … ACH-58) ----------
// id = proposed asset key (ach_<id>.png); the builder may rename it to the final achievement id.
const ACH_V26=[
 {id:'bullseye',ach:'ACH-50',n:'BULLSEYE',d:'Score a ×25 perfect streak.',p:40,vis:'Visible',s:'bullseye',unlock:'Golden Thread trail',idea:'Beak-first into the dead centre of a pink hoop target, the Golden Thread trail behind, “×25” on top.',alt:{s:'bullseyeB',idea:'Right through the middle of a hoop, ringed by 25 sparkles (every 5th gold).'},rec:'A',q:'Recommended: A. A target says “dead centre” at any size; B looks a lot like the approved FIRST FLIGHT.'},
 {id:'sky_high',ach:'ACH-51',n:'SKY HIGH',d:'Pass 150 hoops in one run.',p:50,vis:'Visible',s:'skyHigh',r:'stratos',unlock:'Sky Crown hat',idea:'Climbing far above the clouds in the Sky Crown (its three points are tiny hoops), into a high, starry sky.'},
 {id:'bird_of_prey',ach:'ACH-52',n:'BIRD OF PREY',d:'Win 5 versus races in a row.',p:25,vis:'Hidden',s:'birdOfPrey',r:'prey',unlock:'Bird of Prey frame',idea:'A brown eagle diving, talons out, under an arc of five gold win stars (the fifth is bigger).'},
 {id:'birdwatcher',ach:'ACH-49',n:'BIRDWATCHER',d:'Meet all 32 things in the Flight Guide.',p:25,vis:'Visible',s:'birdwatcher',unlock:'—',idea:'Bird in a bucket hat with binoculars (O77); what it has spotted floats around: a bird in the cross-hair, a hoop, a heart, a star, a coin.'},
 {id:'second_wind',ach:'ACH-53',n:'SECOND WIND',d:'Win a versus race after trailing your rival by 100 points.',p:10,vis:'Visible',s:'secondWind',unlock:'Skywriter name style',idea:'A big gust carries you (pink, gold band) up and past the rival (blue, red band) from behind.'},
 {id:'albatross',ach:'ACH-54',n:'ALBATROSS',d:'Win a versus race with double your rival’s score (rival 100+).',p:15,vis:'Visible',s:'albatross',unlock:'Thunderstruck name style',idea:'A big white albatross (wearing your gold band) next to a rival half its size, “×2”.'},
 {id:'three_little_birds',ach:'ACH-55',n:'THREE LITTLE BIRDS',d:'Win 3 versus races in one day, each with 500+ points.',p:10,vis:'Visible',s:'threeLittleBirds',unlock:'Headliner name style',idea:'Three singing chicks on a branch under the sun, each wearing a gold win medal.'},
 {id:'iron_beak',ach:'ACH-56',n:'IRON BEAK',d:'Win a versus race with 1,000 points or more.',p:10,vis:'Visible',s:'ironBeak',r:'steel',unlock:'Unstoppable sticker',idea:'A riveted steel beak snaps the tip off one of the navy spikes, sparks flying, “1000”.',alt:{s:'ironBeakB',idea:'The steel-beaked bird in a knight’s helmet with a red plume, “1000” below.'},rec:'A',q:'Recommended: A. The broken spike and the sparks show a beak harder than the spikes; the helmet in B reads as “armour” more than “beak”.'},
 {id:'flawless',ach:'ACH-57',n:'FLAWLESS',d:'Win a versus race with a ×20 perfect streak and no revive.',p:10,vis:'Visible',s:'flawless',r:'gem',unlock:'Flawless sticker',idea:'A flawless cut diamond, a calm bird hugging it, sparkles, “×20”.'},
 {id:'top_bird',ach:'ACH-58',n:'TOP BIRD',d:'Finish a day #1 in your leaderboard group.',p:15,vis:'Visible',s:'topBird',unlock:'Top of the Flock sticker',idea:'You next to the Flappy Spikes trophy from our leaderboard (gold cup, pink spike crown, hoop handles) with a big “1”.',alt:{s:'topBirdB',idea:'The top three rows of today’s board, you crowned on the gold #1 row.'},rec:'A',q:'Recommended: A. It reuses the trophy players already see on our leaderboard; B is clear too but close to the approved PECKING ORDER podium.'},
];

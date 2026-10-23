// ach_art.js: the 38 non-rank achievement icons in the 17C app-icon style.
// Needs skin_art.js (TAU) and the page's frame()/shadow pipeline. Scenes draw in icon space:
// origin at the disc centre, disc radius 248, spike teeth reach in to r ~202.

// ---------- primitives ----------
const A_P=(c,pts,col)=>{c.fillStyle=col;c.beginPath();pts.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath();c.fill()};
const A_R=(c,x,y,w,h,col)=>{c.fillStyle=col;c.fillRect(x,y,w,h)};
const A_C=(c,x,y,r,col)=>{c.fillStyle=col;c.beginPath();c.arc(x,y,r,0,TAU);c.fill()};
const A_E=(c,x,y,rx,ry,col,rot=0)=>{c.fillStyle=col;c.beginPath();c.ellipse(x,y,rx,ry,rot,0,TAU);c.fill()};
const A_L=(c,pts,col,w,cap='round')=>{c.strokeStyle=col;c.lineWidth=w;c.lineCap=cap;c.lineJoin='round';c.beginPath();pts.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.stroke()};
const octP=(x,y,w,h,k)=>[[x+k,y],[x+w-k,y],[x+w,y+k],[x+w,y+h-k],[x+w-k,y+h],[x+k,y+h],[x,y+h-k],[x,y+k]];
function starPts(x,y,r,n=5,inner=.45,rot=-Math.PI/2){const p=[];for(let i=0;i<n*2;i++){const rr=i%2?r*inner:r,a=rot+i*Math.PI/n;p.push([x+Math.cos(a)*rr,y+Math.sin(a)*rr])}return p}
function sparkle(c,x,y,r,col='#fff'){A_P(c,[[x,y-r],[x+r*.25,y-r*.25],[x+r,y],[x+r*.25,y+r*.25],[x,y+r],[x-r*.25,y+r*.25],[x-r,y],[x-r*.25,y-r*.25]],col)}
function heartP(c,x,y,s,col){c.save();c.translate(x,y);c.scale(s,s);c.fillStyle=col;c.beginPath();c.moveTo(0,30);c.bezierCurveTo(-60,-8,-38,-58,0,-26);c.bezierCurveTo(38,-58,60,-8,0,30);c.fill();c.restore()}
function coin(c,x,y,r){A_C(c,x,y,r,'#E9A600');A_C(c,x-r*.08,y-r*.08,r*.92,'#FFC400');A_C(c,x-r*.08,y-r*.08,r*.62,'#FFB000');A_R(c,x-r*.22,y-r*.38,r*.28,r*.6,'#FFE082');c.save();c.globalAlpha=.7;A_P(c,[[x-r*.7,y-r*.2],[x-r*.2,y-r*.75],[x-r*.05,y-r*.6],[x-r*.55,y-r*.05]],'#fff');c.restore()}
function eggP(c,x,y,w,h,col,spot){c.fillStyle=col;c.beginPath();c.moveTo(x,y-h/2);c.bezierCurveTo(x+w*.62,y-h/2,x+w*.55,y+h/2,x,y+h/2);c.bezierCurveTo(x-w*.55,y+h/2,x-w*.62,y-h/2,x,y-h/2);c.fill();if(spot)for(const[u,v,r]of[[-.18,-.12,.07],[.2,.05,.06],[-.05,.22,.05],[.12,-.28,.04]])A_C(c,x+u*w,y+v*h,r*w,spot)}
function cloud(c,x,y,s,col){for(const[u,v,r]of[[-.5,.1,.38],[0,-.15,.5],[.5,.1,.38]])A_C(c,x+u*s,y+v*s,r*s,col);A_R(c,x-.5*s,y+.1*s,s,.38*s,col)}
function hoopBack(c,x,y,rx,ry,col){c.strokeStyle=col;c.lineWidth=26;c.beginPath();c.ellipse(x,y,rx,ry,0,Math.PI*.5,Math.PI*1.5);c.stroke()}
function hoopFront(c,x,y,rx,ry,col,colL){c.strokeStyle=col;c.lineWidth=26;c.beginPath();c.ellipse(x,y,rx,ry,0,-Math.PI*.5,Math.PI*.5);c.stroke();c.strokeStyle=colL;c.lineWidth=8;c.beginPath();c.ellipse(x+3,y,rx,ry-6,0,-Math.PI*.42,-Math.PI*.05);c.stroke()}
function speed(c,lines,col='#fff',w=13,a=.85){c.save();c.globalAlpha=a;for(const l of lines)A_L(c,l,col,w);c.restore()}

// ---------- the 17C bird, any skin ----------
// Bird space: body x 0..225 (y 0..225 for the square), eye white 104..220 x 22..136, beak from x 225.
const INK17='#1A1030';
const SHAPES={
 sq:{top:0,bot:225,path:()=>[[0,0],[225,0],[225,225],[0,225]]},
 round:{top:0,bot:225,path:()=>octP(0,0,225,225,62)},
 tall:{top:-34,bot:225,path:()=>[[0,-34],[225,-34],[225,225],[0,225]]},
 chick:{top:14,bot:225,path:()=>octP(6,14,213,211,70)},
 peng:{top:-40,bot:240,path:()=>octP(0,-40,225,280,64)},
 owl:{top:0,bot:225,path:()=>[[0,0],[30,-46],[70,0],[160,0],[200,-46],[225,0],[225,225],[0,225]]},
 puff:{top:0,bot:225,path:()=>octP(0,0,225,225,70)},
 ghost:{top:0,bot:225,path:()=>{const p=[[0,225]];for(let i=0;i<=16;i++){const a=Math.PI+i/16*Math.PI;p.push([112.5+Math.cos(a)*112.5,112.5+Math.sin(a)*112.5])}p.push([225,225]);for(let i=1;i<6;i++)p.push([225-i*45,i%2?190:225]);return p}},
 pixel:{top:0,bot:225,path:()=>[[30,0],[195,0],[195,30],[225,30],[225,195],[195,195],[195,225],[30,225],[30,195],[0,195],[0,30],[30,30]]},
 duck:{top:-10,bot:225,path:()=>[[90,-10],[200,-10],[225,20],[225,120],[260,140],[250,225],[20,225],[-20,150],[-40,60],[10,90],[90,110]]},
};
function bodyPath(c,sh){c.beginPath();SHAPES[sh].path().forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath()}
function pattern(c,o,top,bot){
 const p=o.pat;if(!p)return;const d=o.d;
 if(p==='stripes'||p==='bee')for(let x=40;x<225;x+=70)A_R(c,x,top,30,bot-top,p==='bee'?INK17:d);
 if(p==='zebra')for(let i=-2;i<6;i++)A_P(c,[[i*60,top],[i*60+26,top],[i*60+90,bot],[i*60+64,bot]],INK17);
 if(p==='dots')for(const[x,y]of[[40,40],[90,180],[30,150],[170,200],[80,90]])A_C(c,x,y,16,d);
 if(p==='camo')for(const[x,y,r]of[[40,50,34],[120,190,40],[30,170,28],[190,170,22]])A_E(c,x,y,r,r*.7,d,.5);
 if(p==='galaxy'){for(let i=0;i<18;i++)A_C(c,hash(i)*225,top+hash(i+9)*(bot-top),2+hash(i+3)*5,'#fff');A_E(c,70,170,60,24,'rgba(124,77,255,.6)',-.4)}
 if(p==='gold'){c.save();c.globalAlpha=.45;A_P(c,[[30,top],[80,top],[0,bot*.6],[0,bot*.3]],'#fff');A_P(c,[[110,top],[130,top],[20,bot],[0,bot]],'#fff');c.restore()}
 if(p==='rainbow'){const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'];C.forEach((k,i)=>A_R(c,0,top+i*(bot-top)/6,225,(bot-top)/6+1,k))}
 if(p==='robo'){c.strokeStyle=d;c.lineWidth=6;c.strokeRect(14,150,90,60);for(const[x,y]of[[16,16],[16,128],[90,16],[200,200]])A_C(c,x,y,8,d)}
 if(p==='zombie'){A_R(c,20,150,70,50,'#6B9E3A');A_L(c,[[40,40],[90,70]],INK17,6);for(let i=0;i<4;i++)A_L(c,[[46+i*12,36+i*8],[38+i*12,52+i*8]],INK17,5)}
 if(p==='lava')A_L(c,[[0,160],[60,140],[90,180],[150,150],[225,190]],'#FF6D00',12);
 if(p==='ice'){c.save();c.globalAlpha=.8;A_L(c,[[20,30],[70,80],[50,140]],'#fff',6);A_L(c,[[70,80],[120,60]],'#fff',6);c.restore()}
 if(p==='peacock')for(const[x,y]of[[40,60],[60,170],[150,200]])A_C(c,x,y,12,'#00BFA5');
}
function bird(c,x,y,s,rot,o){c.save();c.translate(x,y);c.rotate(rot*Math.PI/180);c.scale(o.flip?-s:s,s);drawBird(c,o);c.restore()}
function drawBird(c,o){
 const sh=o.sh||'sq',S=SHAPES[sh],top=S.top,bot=S.bot,body=o.c||'#EC008C',wing=o.d||'#C4234F',bk=o.bk||'#FFC400',bkD=o.bkD||'#E9A600';
 c.save();c.translate(-118,-112);
 const G=o.gear||'',H=o.hat||'';
 // behind the body
 if(G==='jetpack'){A_R(c,-60,30,70,150,'#90A4AE');A_R(c,-60,30,70,24,'#607D8B');A_P(c,[[-58,180],[8,180],[-10,250],[-25,300],[-40,250]],'#FF7A1A');A_P(c,[[-46,180],[-4,180],[-25,250]],'#FFC400')}
 if(G==='windup'){A_R(c,-50,100,52,16,'#B0BEC5');A_E(c,-62,82,18,30,'#FFC400');A_E(c,-62,140,18,30,'#FFC400')}
 if(G==='scarf'){A_P(c,[[30,170],[-50,150],[-140,190],[-200,160],[-180,210],[-100,232],[-30,205],[30,212]],o.scarfC||'#FF3B30');}
 if(G==='carpet'){A_P(c,[[-70,250],[300,250],[320,282],[-50,290]],'#7C4DFF');A_R(c,-60,262,370,8,'#FFC400');for(const x of[-70,320])A_P(c,[[x,250],[x-24,262],[x,274]],'#FFC400')}
 if(o.fan){for(let i=0;i<9;i++){const an=-Math.PI*(.06+i*.11);c.save();c.translate(90,120);c.rotate(an+Math.PI/2);A_P(c,[[-30,0],[0,-300],[30,0]],i%2?'#00897B':'#00BFA5');A_E(c,0,-255,30,40,'#1DE9B6');A_E(c,0,-252,16,22,'#283593');A_C(c,0,-250,7,'#FFC400');c.restore()}}
 // wing behind
 const W=o.wing||'tri';
 if(W==='up')A_P(c,[[40,60],[-30,-110],[60,-60],[130,40]],wing);
 if(W==='spread')A_P(c,[[30,70],[-200,40],[-170,110],[90,140]],wing);
 if(W==='hug')A_P(c,[[150,110],[300,60],[310,110],[170,170]],wing);
 // tail + body
 if(sh!=='duck'&&sh!=='ghost')A_P(c,[[-60,68],[0,68],[0,125]],o.tail||body);
 if(sh==='puff')for(let i=0;i<10;i++){const a=i/10*TAU,cx=112+Math.cos(a)*112,cy=112+Math.sin(a)*112;A_P(c,[[cx+Math.cos(a+1.4)*20,cy+Math.sin(a+1.4)*20],[112+Math.cos(a)*150,112+Math.sin(a)*150],[cx+Math.cos(a-1.4)*20,cy+Math.sin(a-1.4)*20]],o.d)}
 bodyPath(c,sh);c.fillStyle=body;c.fill();
 c.save();bodyPath(c,sh);c.clip();
 pattern(c,o,top,bot);
 if(o.belly)A_P(c,[[70,150],[230,120],[230,bot],[70,bot]],o.belly);
 if(o.neck)A_R(c,150,150,90,26,o.neck);
 if(W==='tri')A_P(c,[[26,top+8],[26,top+124],[110,top+124]],wing);
 if(W==='tuck')A_P(c,[[10,40],[120,130],[10,150]],wing);
 // eye
 const E=o.eye||'big',ey=o.ey||'#fff';
 if(E==='happy'){A_L(c,[[118,100],[162,52],[206,100]],INK17,20,'butt')}
 else if(E==='closed'){A_L(c,[[118,80],[162,96],[206,80]],INK17,18,'butt')}
 else{A_R(c,104,22,116,114,ey);
  if(E==='dizzy'){c.strokeStyle=INK17;c.lineWidth=10;c.beginPath();for(let t=0;t<16;t+=.2){const r=4+t*3.2;c.lineTo(162+Math.cos(t)*r,79+Math.sin(t)*r)}c.stroke()}
  else if(E==='heart'){heartP(c,164,84,.85,'#FF3B30')}
  else{const pu={big:[152,28,56,58],wide:[160,50,40,40],half:[150,70,56,52],fierce:[156,52,52,56],down:[150,74,56,56],up:[156,26,52,52],back:[108,40,52,56]}[E]||[152,28,56,58];
   A_R(c,...pu,o.pupil||INK17);A_R(c,pu[0]+(E==='wide'?22:32),pu[1]+6,E==='wide'?12:16,E==='wide'?12:16,'#fff');
   if(E==='half'){A_R(c,104,22,116,52,body);A_R(c,104,66,116,10,INK17)}}}
 c.restore();
 // brow
 const B=o.brow||'raised';
 if(B==='raised')A_P(c,[[98,4],[222,-14],[224,6],[102,24]],INK17);
 if(B==='high')A_P(c,[[104,-18],[160,-40],[218,-22],[214,-6],[160,-24],[108,-2]],INK17);
 if(B==='angry')A_P(c,[[98,6],[224,40],[224,62],[102,28]],INK17);
 if(B==='worried')A_P(c,[[98,30],[222,-4],[224,16],[102,50]],INK17);
 // beak
 const K=o.beak||'open';
 if(K==='open'){A_P(c,[[225,100],[300,136],[225,176]],'#7A0040');A_E(c,244,160,16,9,'#FF6E9C');A_P(c,[[225,44],[306,40],[225,112]],bk);A_P(c,[[225,150],[300,212],[225,206]],bkD)}
 if(K==='closed'){A_P(c,[[225,70],[310,118],[225,124]],bk);A_P(c,[[225,124],[310,118],[225,170]],bkD)}
 if(K==='grin'){A_P(c,[[225,60],[312,96],[225,124]],bk);A_P(c,[[225,124],[300,112],[225,160]],bkD);A_R(c,225,118,60,6,'#7A0040')}
 if(K==='toucan'){A_P(c,[[225,30],[380,70],[420,150],[225,120]],'#FF9800');A_P(c,[[225,120],[420,150],[225,170]],'#4CAF50');A_P(c,[[380,70],[420,150],[400,100]],'#F44336')}
 if(K==='hook'){A_P(c,[[225,60],[300,70],[310,150],[285,130],[225,130]],'#fff');A_P(c,[[285,90],[310,150],[285,130]],INK17)}
 if(K==='duck'){A_P(c,[[225,70],[330,90],[330,120],[225,130]],bk);A_P(c,[[225,130],[320,124],[225,160]],bkD)}
 if(K==='small'){A_P(c,[[225,80],[275,104],[225,128]],bk)}
 if(K==='worm'){A_P(c,[[225,60],[312,96],[225,124]],bk);A_P(c,[[225,124],[300,112],[225,160]],bkD);A_L(c,[[290,110],[320,150],[300,190],[330,230]],'#FF6E9C',22)}
 // cheeks
 if(o.blush)A_E(c,150,165,22,12,'#FF6E9C');
 // gear on the body
 if(G==='shades'){A_R(c,70,34,196,18,INK17);for(const x0 of[96,176]){A_R(c,x0,52,72,22,INK17);A_R(c,x0+12,74,60,12,INK17);A_R(c,x0+24,86,36,10,INK17);A_R(c,x0+12,56,14,10,'#fff')}}
 if(G==='hearts'){A_R(c,70,40,196,12,'#B71C1C');heartP(c,140,78,1,'#FF3B30');heartP(c,224,78,1,'#FF3B30');A_R(c,124,60,12,10,'#fff')}
 if(G==='monocle'){c.strokeStyle='#FFC400';c.lineWidth=12;c.beginPath();c.arc(178,62,52,0,TAU);c.stroke();A_L(c,[[150,110],[130,190],[150,240]],'#FFC400',5)}
 if(G==='patch'){A_P(c,[[60,20],[240,70],[240,84],[60,34]],INK17);A_E(c,170,70,46,40,INK17)}
 if(G==='mask'){A_R(c,40,40,200,54,o.maskC||'#D32F2F');A_R(c,140,44,60,44,'#fff');A_R(c,160,52,30,30,INK17);A_P(c,[[40,40],[-30,20],[-20,60],[40,90]],o.maskC||'#D32F2F')}
 if(G==='stache')A_P(c,[[220,140],[300,130],[320,160],[290,150],[260,170],[230,160]],'#4E342E');
 if(G==='bowtie'){A_P(c,[[190,190],[150,165],[150,225]],o.bowC||'#D32F2F');A_P(c,[[190,190],[230,165],[230,225]],o.bowC||'#D32F2F');A_R(c,180,180,20,22,o.bowC2||'#9A0007')}
 if(G==='chain'){c.strokeStyle='#FFC400';c.lineWidth=12;c.setLineDash([16,8]);c.beginPath();c.arc(150,90,120,Math.PI*.2,Math.PI*.8);c.stroke();c.setLineDash([]);coin(c,120,215,28)}
 if(G==='bandana'){A_P(c,[[110,150],[250,150],[200,240]],o.bandC||'#D32F2F');for(const[x,y]of[[150,170],[200,165],[190,200]])A_C(c,x,y,6,'#fff')}
 if(G==='scarf')A_R(c,20,168,215,34,o.scarfC||'#FF3B30');
 if(G==='bandage'){A_R(c,0,6,225,30,'#FFF3E0');A_R(c,60,0,30,42,'#FFF3E0');A_L(c,[[70,10],[70,34]],'#E0C9A6',4);A_L(c,[[80,10],[80,34]],'#E0C9A6',4)}
 if(G==='sneakers'){for(const x of[40,140]){A_P(c,[[x,225],[x+70,225],[x+90,260],[x,262]],'#fff');A_R(c,x,250,90,12,'#FF3B30')}}
 if(G==='snorkel'){A_R(c,96,14,136,130,'rgba(179,229,252,.55)');c.strokeStyle='#FFC400';c.lineWidth=12;c.strokeRect(96,14,136,130);A_R(c,40,-60,22,120,'#FF7A1A');A_R(c,40,40,70,18,'#FF7A1A')}
 // hats (head top = top, head centre x ~120)
 const T=top;
 if(H==='cap'){A_P(c,[[30,T+6],[50,T-50],[200,T-50],[225,T+6]],o.hatC||'#1E88E5');A_P(c,[[150,T-4],[300,T-4],[300,T+14],[150,T+14]],o.hatC2||'#1565C0');A_R(c,110,T-62,20,14,o.hatC2||'#1565C0')}
 if(H==='beanie'){A_P(c,[[20,T+10],[40,T-60],[110,T-90],[190,T-60],[210,T+10]],o.hatC||'#FF7043');A_R(c,14,T-10,202,30,o.hatC2||'#D84315');A_C(c,114,T-100,24,'#fff')}
 if(H==='party'){A_P(c,[[50,T+6],[130,T-170],[190,T+6]],o.hatC||'#7C4DFF');A_P(c,[[78,T-56],[156,T-56],[166,T-30],[70,T-30]],'#FFC400');A_P(c,[[100,T-110],[150,T-110],[146,T-96],[104,T-96]],'#FFC400');A_C(c,130,T-176,22,'#FF3B30')}
 if(H==='band'){A_R(c,-4,T+4,233,34,o.hatC||'#FF3B30');A_R(c,-4,T+16,233,8,'#fff');A_P(c,[[-4,T+6],[-60,T-20],[-50,T+20]],o.hatC||'#FF3B30');A_P(c,[[-4,T+30],[-64,T+40],[-40,T+60]],o.hatC||'#FF3B30')}
 if(H==='bucket'){A_P(c,[[40,T+4],[60,T-60],[180,T-60],[200,T+4]],o.hatC||'#FFC400');A_P(c,[[-10,T+4],[250,T+4],[270,T+30],[-30,T+30]],o.hatC2||'#F29100')}
 if(H==='tophat'){A_R(c,50,T-150,130,140,INK17);A_R(c,50,T-50,130,24,'#D32F2F');A_R(c,10,T-14,210,22,INK17)}
 if(H==='cowboy'){A_P(c,[[50,T-6],[60,T-90],[115,T-70],[170,T-90],[180,T-6]],'#8D5A2B');A_P(c,[[-30,T-40],[10,T+6],[220,T+6],[260,T-40],[230,T-10],[0,T-10]],'#A1683A');A_R(c,58,T-30,118,14,'#5D3A1A')}
 if(H==='prop'){A_P(c,[[30,T+6],[50,T-50],[190,T-50],[210,T+6]],'#FFC400');A_P(c,[[30,T+6],[70,T-48],[110,T-50],[110,T+6]],'#FF3B30');A_P(c,[[110,T-50],[150,T-50],[190,T+6],[110,T+6]],'#1E88E5');A_R(c,114,T-80,12,32,INK17);A_E(c,120,T-84,70,12,'#7FE3FF')}
 if(H==='chef'){A_R(c,50,T-60,140,64,'#fff');for(const x of[60,120,180])A_C(c,x,T-80,46,'#fff');A_R(c,50,T-14,140,10,'#E0E0E0')}
 if(H==='viking'){A_P(c,[[20,T+10],[40,T-60],[120,T-90],[200,T-60],[220,T+10]],'#90A4AE');A_R(c,20,T-8,200,22,'#FFC400');A_P(c,[[30,T-30],[-40,T-120],[-10,T-30]],'#FFF8E1');A_P(c,[[210,T-30],[280,T-120],[250,T-30]],'#FFF8E1')}
 if(H==='pirate'){A_P(c,[[-20,T+4],[40,T-80],[120,T-50],[200,T-80],[260,T+4]],INK17);A_C(c,120,T-36,18,'#fff');A_R(c,108,T-24,24,8,'#fff')}
 if(H==='wizard'){A_P(c,[[20,T+6],[140,T-200],[180,T-160],[200,T+6]],o.hatC||'#5E35B1');A_P(c,[[-10,T+6],[240,T+6],[230,T+24],[0,T+24]],o.hatC2||'#4527A0');for(const[x,y,r]of[[100,T-50,16],[150,T-110,12],[160,T-30,10]])A_P(c,starPts(x,y,r),'#FFC400')}
 if(H==='crown'){A_P(c,[[20,T+6],[20,T-80],[70,T-40],[120,T-100],[170,T-40],[220,T-80],[220,T+6]],'#FFC400');A_R(c,20,T-14,200,20,'#E69500');A_C(c,120,T-46,14,'#E53935');A_C(c,60,T-4,8,'#1E88E5');A_C(c,180,T-4,8,'#43A047')}
 if(H==='halo'){c.strokeStyle='#FFE082';c.lineWidth=18;c.beginPath();c.ellipse(120,T-60,90,24,0,0,TAU);c.stroke()}
 if(H==='astro'){c.save();c.globalAlpha=.4;A_C(c,130,110,190,'#B3E5FC');c.restore();c.strokeStyle='#fff';c.lineWidth=12;c.beginPath();c.arc(130,110,190,0,TAU);c.stroke();A_E(c,60,20,40,18,'rgba(255,255,255,.7)',-.6)}
 if(H==='crest'){for(let i=0;i<5;i++){const a=-2.6+i*.32;A_P(c,[[90+i*12,T+10],[90+i*12+Math.cos(a)*150,T+Math.sin(a)*150],[110+i*12,T+10]],'#FF9800');A_C(c,90+i*12+Math.cos(a)*150,T+Math.sin(a)*150,10,INK17)}}
 if(H==='mailcap'){A_P(c,[[30,T+6],[44,T-56],[200,T-56],[214,T+6]],'#3949AB');A_P(c,[[150,T-4],[290,T-4],[290,T+14],[150,T+14]],INK17);A_R(c,100,T-48,40,26,'#FFC400')}
 if(H==='beret'){A_E(c,110,T-10,120,40,'#D32F2F',-.1);A_R(c,104,T-62,12,20,'#D32F2F')}
 if(H==='nightcap'){A_P(c,[[20,T+10],[110,T-80],[260,T-20],[210,T+10]],'#3949AB');A_C(c,270,T-10,22,'#fff');A_R(c,14,T-6,210,24,'#fff')}
 if(H==='shell'){A_P(c,[[30,T+10],[50,T-40],[120,T-60],[190,T-40],[205,T+10],[175,T-6],[150,T+16],[120,T-10],[90,T+14],[60,T-8]],'#FFF4DE')}
 c.restore();
}

// ---------- disc colour ramps (default: the app icon cyan) ----------
const CYAN=['#B4F7FF','#2BC8F5','#0A6FE2'];
const RAMP={space:['#9575FF','#3A1C8C','#0E0530'],volcano:['#FFE0A0','#FF6D00','#8E1B0B'],sea:['#9BF0FF','#0398D6','#012F66'],
 pinball:['#FFB3E6','#E040FB','#4A0072'],storm:['#C5CAE9','#5C6BC0','#141A4D'],cannon:['#FFF6B0','#FFB300','#D84315'],
 night:['#7986CB','#283593','#0B0F38'],sunrise:['#FFF7C2','#FFB74D','#E6452A'],fire:['#FFE58A','#FF5722','#8A1200'],gold:['#FFF6C9','#FFC629','#C77700']};

// ---------- scenes ----------
const SCENES={
 // --- rides ---
 cannon(c){ // bird fired from a circus cannon
  c.save();c.rotate(-.55);A_R(c,-210,40,190,96,'#37474F');A_R(c,-40,28,40,120,'#263238');A_R(c,-200,52,170,16,'#607D8B');A_R(c,-225,58,20,60,'#263238');c.restore();
  A_C(c,-118,170,46,'#8D5A2B');A_C(c,-118,170,18,'#5D3A1A');
  for(const[x,y,r]of[[-30,40,38],[10,0,30],[-60,10,26]])A_C(c,x,y,r,'rgba(255,255,255,.9)');
  speed(c,[[[-20,-30],[40,-90]],[[10,10],[80,-50]]]);
  bird(c,70,-60,.82,-38,{c:'#FF7A1A',d:'#C43E00',hat:'band',hatC:'#1E88E5',eye:'wide',brow:'high',beak:'open',wing:'spread'});
  for(const[x,y,r]of[[150,-170,14],[-150,-120,10],[180,40,10]])sparkle(c,x,y,r)},
 space(c){ // astro bird among planets
  for(let i=0;i<30;i++)A_C(c,-220+hash(i)*440,-220+hash(i+50)*440,1.5+hash(i+7)*3.5,'#fff');
  A_C(c,130,-120,54,'#FF7043');c.strokeStyle='#FFCC80';c.lineWidth=10;c.beginPath();c.ellipse(130,-120,90,22,-.4,0,TAU);c.stroke();
  A_C(c,-150,130,30,'#26C6DA');
  A_P(c,[[-200,170],[-60,40],[-40,60],[-180,190]],'rgba(255,255,255,.5)');
  bird(c,0,20,.78,-20,{c:'#29B6F6',d:'#0277BD',hat:'astro',eye:'big',beak:'open',wing:'up'});
  sparkle(c,-120,-140,20);sparkle(c,170,120,14)},
 volcano(c){
  A_P(c,[[-230,230],[-70,10],[70,10],[230,230]],'#4E342E');A_P(c,[[-70,10],[70,10],[50,50],[20,30],[-10,60],[-40,30]],'#FF6D00');
  for(const[x,y,r]of[[-30,-40,30],[30,-90,24],[-60,-120,18],[60,-20,20]])A_C(c,x,y,r,'#FFC400');
  A_P(c,[[-20,10],[20,10],[60,-140],[0,-60],[-50,-150]],'#FF5722');
  bird(c,30,-40,.8,-12,{sh:'round',c:'#F48FB1',d:'#EC407A',beak:'hook',gear:'shades',wing:'up',brow:'none'});
  for(const[x,y]of[[-170,-80],[150,-150],[-130,-170]])A_P(c,[[x,y-16],[x+10,y],[x,y+16],[x-10,y]],'#FFC400')},
 sea(c){
  for(const[x,y,r]of[[-150,-120,22],[-120,-170,14],[150,-160,18],[170,-110,10],[-170,60,12]]){c.strokeStyle='rgba(255,255,255,.85)';c.lineWidth=6;c.beginPath();c.arc(x,y,r,0,TAU);c.stroke()}
  A_P(c,[[-240,170],[-160,140],[-80,170],[0,140],[80,170],[160,140],[240,170],[240,260],[-240,260]],'#01579B');
  for(const[x,y,col,f]of[[-150,110,'#FFC400',1],[150,60,'#FF7043',-1]]){c.save();c.translate(x,y);c.scale(f,1);A_E(c,0,0,34,20,col);A_P(c,[[-30,0],[-56,-20],[-56,20]],col);A_C(c,16,-4,5,INK17);c.restore()}
  bird(c,0,-10,.8,10,{sh:'peng',c:'#263238',d:'#101518',belly:'#fff',beak:'small',bk:'#FF9800',gear:'snorkel',wing:'tuck',brow:'none'})},
 pinball(c){
  for(const[x,y,col]of[[-140,-110,'#FFC400'],[150,-60,'#00E5FF']]){A_C(c,x,y,46,'#fff');A_C(c,x,y,36,col);A_P(c,starPts(x,y,20),'#fff')}
  A_P(c,[[-180,170],[-40,200],[-40,214],[-184,190]],'#FFC400');A_P(c,[[180,170],[40,200],[40,214],[184,190]],'#FFC400');A_C(c,-180,180,14,'#FF3B30');A_C(c,180,180,14,'#FF3B30');
  speed(c,[[[-120,90],[-60,40]],[[-150,50],[-100,10]]]);
  bird(c,20,0,.72,25,{sh:'round',c:'#FFC107',d:'#212121',pat:'bee',bk:'#212121',bkD:'#000',eye:'dizzy',brow:'none',beak:'open',wing:'up'});
  for(const[x,y,r]of[[100,-160,16],[-60,-170,12],[190,60,10]])sparkle(c,x,y,r,'#FFE082')},
 storm(c){
  cloud(c,-40,-130,150,'#B0BEC5');cloud(c,80,-150,110,'#CFD8DC');
  A_P(c,[[60,-110],[20,-30],[50,-30],[0,60],[90,-50],[56,-50],[90,-110]],'#FFEB3B');
  c.save();c.globalAlpha=.8;for(let i=0;i<9;i++){const x=-200+i*48;A_L(c,[[x,-40+(i%3)*30],[x-18,0+(i%3)*30]],'#E3F2FD',6)}c.restore();
  bird(c,-20,80,.78,-6,{c:'#FAFAFA',d:'#B0BEC5',ey:'#fff',hat:'bucket',eye:'wide',brow:'worried',beak:'open',wing:'up'});
  for(const[x,y,a]of[[-150,30,.6],[130,40,-.4],[-120,170,.2]]){c.save();c.translate(x,y);c.rotate(a);A_E(c,0,0,10,28,'#ECEFF1');c.restore()}},
 frequent(c){ // ticket with six ride stamps
  c.save();c.rotate(-.18);A_R(c,-200,-60,290,180,'#FFF8E1');A_R(c,-200,-60,290,40,'#FF4FB7');
  for(let i=0;i<6;i++){const x=-160+(i%3)*90,y=10+Math.floor(i/3)*60,cols=['#FFB300','#7C4DFF','#FF6D00','#0398D6','#E040FB','#5C6BC0'];c.strokeStyle=cols[i];c.lineWidth=7;c.beginPath();c.arc(x,y,22,0,TAU);c.stroke();A_P(c,[[x-10,y],[x-2,y+9],[x+12,y-9]],cols[i])}
  c.setLineDash([10,8]);A_L(c,[[40,-60],[40,120]],'#E0C9A6',4);c.setLineDash([]);c.restore();
  bird(c,110,30,.7,-10,{c:'#FFC629',d:'#C98A00',pat:'gold',hat:'cap',hatC:'#3949AB',hatC2:INK17,gear:'shades',beak:'grin',wing:'up',brow:'none'})},
 // --- first catch ---
 heart(c){heartP(c,-40,10,3.2,'#FF3B30');heartP(c,-60,-20,1.4,'rgba(255,255,255,.35)');
  bird(c,90,40,.7,-8,{c:'#FF6F61',d:'#C62828',pat:'dots',gear:'hearts',beak:'grin',wing:'hug',brow:'none',blush:1});
  for(const[x,y,s]of[[-170,-140,.5],[160,-160,.4],[-180,140,.35]])heartP(c,x,y,s,'#FF8A80')},
 shield(c){A_P(c,[[-150,-150],[60,-150],[60,30],[-45,150],[-150,30]],'#1E88E5');A_P(c,[[-130,-130],[40,-130],[40,22],[-45,124],[-130,22]],'#64B5F6');A_P(c,[[-45,-110],[-20,-60],[30,-55],[-8,-20],[5,35],[-45,8],[-95,35],[-82,-20],[-120,-55],[-70,-60]],'#fff');
  bird(c,90,60,.68,-6,{c:'#7C8B6E',d:'#4B5842',pat:'camo',hat:'viking',eye:'fierce',brow:'angry',beak:'grin',wing:'up'})},
 star(c){const pts=[[-190,140],[-140,90],[-90,50],[-40,20],[10,0]];pts.forEach(([x,y],i)=>A_P(c,starPts(x,y,20+i*4),'#FFC400'));
  bird(c,90,-20,.72,-14,{c:'#8E24AA',d:'#4A148C',hat:'wizard',beak:'open',wing:'up'});
  for(const[x,y,r]of[[-120,-140,20],[170,140,16]])sparkle(c,x,y,r)},
 hourglass(c){c.save();c.rotate(-.12);A_R(c,-180,-160,180,24,'#8D5A2B');A_R(c,-180,136,180,24,'#8D5A2B');
  A_P(c,[[-170,-136],[-10,-136],[-60,-10],[-60,10],[-10,136],[-170,136],[-120,10],[-120,-10]],'rgba(255,255,255,.75)');
  A_P(c,[[-150,-110],[-30,-110],[-80,-20],[-100,-20]],'#FFC400');A_P(c,[[-150,136],[-30,136],[-60,90],[-120,90]],'#FFC400');A_R(c,-93,-20,6,110,'#FFC400');c.restore();
  bird(c,95,40,.66,-6,{sh:'owl',c:'#A1887F',d:'#6D4C41',belly:'#D7CCC8',gear:'monocle',beak:'closed',bk:'#FFB300',brow:'none',eye:'half'})},
 mini(c){ // a tiny bird next to its own big silhouette
  c.save();c.globalAlpha=.28;bird(c,-40,-10,.95,-8,{c:'#fff',d:'#fff',bk:'#fff',bkD:'#fff',brow:'none',eye:'closed',beak:'closed'});c.restore();
  bird(c,90,90,.42,-12,{sh:'chick',c:'#FFD54F',d:'#FFA000',bk:'#FF7A1A',bkD:'#E65100',hat:'beanie',hatC:'#26C6DA',hatC2:'#00838F',eye:'big',beak:'open',blush:1});
  for(const[x,y,a]of[[30,40,.8],[150,0,2.4]]){c.save();c.translate(x,y);c.rotate(a);A_P(c,[[0,-18],[16,0],[6,0],[6,18],[-6,18],[-6,0],[-16,0]],'#fff');c.restore()}},
 frenzy(c){for(const[x,y,r]of[[-150,-120,34],[-60,-170,28],[150,-130,30],[-180,20,26],[170,30,24],[-120,150,30],[140,150,28],[40,-190,22]])coin(c,x,y,r);
  bird(c,0,20,.78,-10,{c:'#FFE03A',d:'#F29100',bk:'#FF5722',bkD:'#D84315',pat:'stripes',gear:'shades',beak:'grin',wing:'up',brow:'none'})},
 egg(c){eggP(c,-70,20,190,250,'#FFF4DE','#7FE3FF');eggP(c,-100,-40,40,70,'rgba(255,255,255,.6)');
  bird(c,100,60,.66,-8,{c:'#3DDBB0',d:'#00897B',hat:'chef',beak:'open',wing:'up',eye:'wide',brow:'high',blush:1});
  for(const[x,y,r]of[[-180,-140,18],[50,-170,14]])sparkle(c,x,y,r)},
 piggy(c){A_E(c,-50,30,150,110,'#F48FB1');A_C(c,-180,40,40,'#F48FB1');A_E(c,-200,40,22,26,'#EC407A');A_C(c,-206,32,5,'#880E4F');A_C(c,-194,48,5,'#880E4F');
  A_P(c,[[-130,-60],[-110,-120],[-80,-70]],'#EC407A');A_C(c,-130,0,10,INK17);for(const x of[-140,-60,20,80])A_R(c,x,120,30,46,'#EC407A');A_R(c,-60,-82,70,14,'#880E4F');coin(c,-24,-120,30);
  bird(c,110,-40,.6,-6,{c:'#26A69A',d:'#00695C',hat:'tophat',gear:'bowtie',beak:'grin',brow:'none'})},
 jar(c){A_R(c,-160,-120,180,260,'rgba(255,255,255,.35)');A_R(c,-170,-150,200,40,'#8D5A2B');c.strokeStyle='rgba(255,255,255,.9)';c.lineWidth=8;c.strokeRect(-160,-110,180,250);
  for(let i=0;i<9;i++){const x=-140+hash(i+3)*140,y=-80+hash(i+21)*200;A_C(c,x,y,16,'rgba(255,241,118,.45)');A_C(c,x,y,7,'#FFF176')}
  bird(c,110,40,.66,-8,{c:'#7CB342',d:'#33691E',hat:'bucket',hatC:'#A1887F',hatC2:'#6D4C41',beak:'open',wing:'up',eye:'up'})},
 feather(c){c.save();c.rotate(.6);A_P(c,[[0,-200],[60,-120],[70,0],[40,120],[0,180],[-40,120],[-70,0],[-60,-120]],'#fff');A_L(c,[[0,-180],[0,220]],'#7FE3FF',10);for(let i=0;i<6;i++){A_L(c,[[0,-120+i*45],[-50,-95+i*45]],'#B3E5FC',5);A_L(c,[[0,-120+i*45],[50,-95+i*45]],'#B3E5FC',5)}c.restore();
  bird(c,40,60,.66,-6,{c:'#B3E5FC',d:'#4FC3F7',pat:'ice',gear:'carpet',beak:'grin',eye:'closed',brow:'none'})},
 puzzle(c){c.save();c.translate(-110,-40);c.rotate(-.2);const pz=(col)=>{c.fillStyle=col;c.beginPath();c.moveTo(-80,-80);c.lineTo(-22,-80);c.arc(0,-86,26,Math.PI*.8,Math.PI*.2,false);c.lineTo(80,-80);c.lineTo(80,-22);c.arc(86,0,26,-Math.PI*.7,Math.PI*.7,false);c.lineTo(80,80);c.lineTo(22,80);c.arc(0,74,24,Math.PI*.2,Math.PI*.8,true);c.lineTo(-80,80);c.lineTo(-80,22);c.arc(-72,0,24,Math.PI*.3,-Math.PI*.3,true);c.closePath();c.fill()};pz('#AB47BC');c.save();c.globalAlpha=.35;A_P(c,[[-70,-70],[-30,-70],[-70,-30]],'#fff');c.restore();c.restore();  bird(c,70,40,.72,-4,{c:'#90A4AE',d:'#546E7A',neck:'#26A69A',beak:'closed',eye:'up',brow:'worried',wing:'tuck'});
  for(const[x,y,s]of[[160,-150,1],[90,-190,.7]]){c.save();c.translate(x,y);c.scale(s,s);c.font='bold 90px Opificio, sans-serif';c.textAlign='center';c.fillStyle='#fff';c.fillText('?',0,30);c.restore()}},
 magpie(c){coin(c,-150,120,30);heartP(c,-80,140,1.1,'#FF3B30');A_P(c,starPts(150,140,30),'#FFC400');eggP(c,190,60,40,56,'#FFF4DE','#7FE3FF');coin(c,-190,50,22);
  A_C(c,-30,175,22,'#1E88E5');A_P(c,[[60,160],[100,120],[110,180]],'#fff');
  bird(c,0,-30,.78,-6,{c:'#263238',d:'#101518',belly:'#fff',gear:'chain',beak:'grin',bk:'#455A64',bkD:'#263238',brow:'none',wing:'tuck'})},
 // --- mastery ---
 hen(c){ // chick in the bottom half of a cracked egg, the top half tipped off
  c.save();c.translate(170,-150);c.rotate(.5);c.fillStyle='#FFF4DE';c.beginPath();c.moveTo(-70,10);c.bezierCurveTo(-70,-90,70,-90,70,10);for(let i=0;i<=6;i++)c.lineTo(70-i*140/6,i%2?-12:10);c.fill();c.restore();
  bird(c,10,-10,.72,-8,{sh:'chick',c:'#FFD54F',d:'#FFA000',bk:'#FF7A1A',bkD:'#E65100',eye:'happy',brow:'none',beak:'open',blush:1,wing:'up'});
  c.fillStyle='#FFF4DE';c.beginPath();c.moveTo(-130,40);for(let i=0;i<=8;i++)c.lineTo(-130+i*32.5,40+(i%2?-26:0));c.bezierCurveTo(130,150,90,200,0,200);c.bezierCurveTo(-90,200,-130,150,-130,40);c.fill();
  for(const[x,y]of[[-60,120],[40,150],[60,90]])A_C(c,x,y,9,'#E9D6AE');
  for(const[x,y,s]of[[-140,-120,.7],[170,-110,.55],[-170,40,.45]])heartP(c,x,y,s,'#FF6E9C')},
 nightOwl(c){for(let i=0;i<22;i++)A_C(c,-220+hash(i+5)*440,-220+hash(i+80)*300,1.5+hash(i+2)*3,'#fff');
  A_C(c,140,-140,50,'#FFF59D');A_C(c,165,-160,46,RAMP.night[1]);
  A_R(c,-200,-40,150,210,'rgba(255,255,255,.3)');A_R(c,-208,-70,166,34,'#8D5A2B');for(let i=0;i<10;i++){const x=-185+hash(i+31)*110,y=-20+hash(i+44)*170;A_C(c,x,y,18,'rgba(255,241,118,.5)');A_C(c,x,y,8,'#FFF176')}
  bird(c,90,50,.68,-4,{sh:'owl',c:'#8D6E63',d:'#5D4037',belly:'#D7CCC8',pupil:'#1A1030',ey:'#FFEB3B',beak:'closed',bk:'#FFB300',brow:'none',eye:'big',gear:'',hat:'nightcap'})},
 seeingStars(c){for(let i=0;i<8;i++){const a=i/8*TAU;A_P(c,starPts(Math.cos(a)*175,Math.sin(a)*70-120,20),'#FFC400')}
  bird(c,0,40,.8,8,{c:'#FF7A1A',d:'#C43E00',eye:'dizzy',brow:'none',beak:'open',wing:'up'})},
 birdsEye(c){c.save();c.rotate(-.1);A_R(c,-200,-170,260,230,'#8D5A2B');A_R(c,-180,-150,220,190,'#B4F7FF');A_P(c,[[-180,40],[-110,-40],[-60,10],[-10,-70],[40,40]],'#43A047');A_C(c,0,-110,24,'#FFC400');
  bird(c,-90,-80,.18,-10,{});c.restore();
  bird(c,120,70,.62,-6,{sh:'pixel',c:'#EC008C',d:'#7A0044',hat:'beret',beak:'grin',brow:'none',eye:'big'});
  A_R(c,200,-40,16,120,'#8D5A2B');A_P(c,[[196,-40],[220,-40],[208,-80]],'#FF3B30')},
 goldenEgg(c){for(let i=0;i<12;i++){c.save();c.globalAlpha=.25;c.rotate(i/12*TAU);A_P(c,[[0,0],[-26,-260],[26,-260]],'#FFF59D');c.restore()}
  eggP(c,-20,10,210,280,'#FFC629');eggP(c,-50,-50,50,90,'rgba(255,255,255,.55)');
  for(const[x,y,col]of[[-170,-140,'#FF3B30'],[160,-150,'#7C4DFF']]){A_E(c,x,y,34,42,col);A_L(c,[[x,y+42],[x+10,y+120]],'#fff',3)}
  bird(c,130,110,.5,-10,{c:'#FF6F61',d:'#C62828',hat:'party',beak:'open',eye:'happy',brow:'none',blush:1});
  for(const[x,y,r]of[[90,-120,22],[-130,90,16],[40,-190,14]])sparkle(c,x,y,r)},
 // --- hoops ---
 firstFlight(c){hoopBack(c,40,0,60,150,'#EC008C');bird(c,0,10,.7,-14,{c:'#29B6F6',d:'#0277BD',hat:'prop',beak:'open',eye:'wide',brow:'high',wing:'up'});hoopFront(c,40,0,60,150,'#EC008C','#FF8FD0');
  speed(c,[[[-200,60],[-140,60]],[[-190,110],[-110,110]]])},
 hoopoe(c){for(const[x,s]of[[-150,.6],[-80,.8]]){hoopBack(c,x,10,40*s,130*s,'#00A2FF');hoopFront(c,x,10,40*s,130*s,'#00A2FF','#80D8FF')}
  hoopBack(c,90,20,55,150,'#EC008C');bird(c,40,30,.66,-10,{c:'#FFAB76',d:'#C77B4A',pat:'zebra',hat:'crest',beak:'closed',bk:INK17,bkD:'#000',wing:'up'});hoopFront(c,90,20,55,150,'#EC008C','#FF8FD0')},
 ringNecked(c){for(const[x,y,s]of[[-170,-120,.5],[-150,140,.45],[170,-140,.42]]){hoopBack(c,x,y,30*s*2,90*s*2,'#FFC400');hoopFront(c,x,y,30*s*2,90*s*2,'#FFC400','#FFF59D')}
  bird(c,0,10,.86,-8,{c:'#7CB342',d:'#33691E',neck:INK17,beak:'grin',bk:'#E53935',bkD:'#B71C1C',wing:'up',brow:'raised'});
  c.strokeStyle='#FFC400';c.lineWidth=14;c.beginPath();c.ellipse(70,70,60,22,-.3,0,TAU);c.stroke()},
 flyingColors(c){const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'];C.forEach((k,i)=>{c.strokeStyle=k;c.lineWidth=20;c.beginPath();c.moveTo(-240,140+i*-0+i*18-60);c.quadraticCurveTo(-100,40+i*18,0,20+i*18);c.stroke()});
  hoopBack(c,90,0,55,140,'#fff');bird(c,40,0,.72,-14,{c:'#f44',pat:'rainbow',d:'#fff',beak:'grin',gear:'shades',wing:'up',brow:'none'});hoopFront(c,90,0,55,140,'#fff','#B4F7FF')},
 // --- versus ---
 beakToBeak(c){A_P(c,[[0,-130],[30,-40],[90,-30],[30,10],[50,90],[0,40],[-50,90],[-30,10],[-90,-30],[-30,-40]],'#FFC400');
  bird(c,-110,40,.62,8,{c:'#EC008C',hat:'band',hatC:'#FFC400',eye:'fierce',brow:'angry',beak:'open',wing:'up'});
  bird(c,110,40,.62,-8,{c:'#29B6F6',d:'#0277BD',hat:'band',hatC:'#FF3B30',eye:'fierce',brow:'angry',beak:'open',wing:'up',flip:1})},
 peckingOrder(c){A_R(c,-60,60,120,170,'#FFC400');A_R(c,-190,110,130,120,'#B0BEC5');A_R(c,60,140,130,90,'#CD7F32');
  c.font='60px Opificio, sans-serif';c.textAlign='center';c.fillStyle='#fff';c.fillText('1',0,150);c.fillText('2',-125,190);c.fillText('3',125,210);
  bird(c,-125,60,.36,-4,{c:'#3DDBB0',d:'#00897B',beak:'closed',brow:'none',eye:'half'});bird(c,125,90,.34,-4,{c:'#29B6F6',d:'#0277BD',beak:'closed',brow:'worried',eye:'up'});
  bird(c,0,-40,.56,-8,{c:'#8E24AA',d:'#4A148C',hat:'cowboy',beak:'grin',brow:'raised',wing:'up'})},
 roost(c){A_R(c,-160,70,320,30,'#8D5A2B');A_R(c,-140,100,20,140,'#5D3A1A');A_R(c,120,100,20,140,'#5D3A1A');
  bird(c,0,-20,.78,-6,{c:'#FFC629',d:'#C98A00',pat:'gold',bk:'#fff',bkD:'#E0E0E0',hat:'crown',beak:'grin',brow:'none',wing:'tuck'});
  for(const[x,y,r]of[[-150,-120,20],[160,-80,16],[120,-180,12]])sparkle(c,x,y,r)},
 // --- more ---
 stillTweeting(c){A_P(c,[[-200,180],[-60,180],[-80,100],[-180,100]],'#9E9E9E');c.font='40px Opificio, sans-serif';c.textAlign='center';c.fillStyle='#616161';c.fillText('RIP',-130,155);
  bird(c,40,-10,.8,-10,{c:'#8BC34A',d:'#4E7A27',pat:'zombie',gear:'bandage',beak:'open',eye:'big',brow:'raised',wing:'up'});
  for(const[x,y]of[[-150,-120],[170,-150]]){c.font='bold 60px Opificio, sans-serif';c.fillStyle='#fff';c.fillText('♪',x,y)}},
 bigBird(c){hoopBack(c,40,0,90,215,'#FFC400');bird(c,0,10,1.05,-10,{sh:'puff',c:'#FFCA28',d:'#F57F17',bk:'#FF7043',bkD:'#D84315',hat:'cap',hatC:'#FF3B30',hatC2:'#B71C1C',beak:'open',eye:'wide',brow:'high',wing:'tri'});hoopFront(c,40,0,90,215,'#FFC400','#FFF59D')},
 hotWings(c){for(const[x,y,s]of[[-130,80,1.2],[0,120,1.5],[130,80,1.2]]){A_P(c,[[x-50*s,y+60],[x-40*s,y-60*s],[x-10*s,y-20*s],[x,y-110*s],[x+20*s,y-30*s],[x+45*s,y-70*s],[x+50*s,y+60]],'#FF6D00');A_P(c,[[x-30*s,y+60],[x-20*s,y-20*s],[x,y-60*s],[x+20*s,y-10*s],[x+30*s,y+60]],'#FFC400')}
  bird(c,0,-40,.74,-12,{c:'#3E2723',d:'#1B0F0C',pat:'lava',bk:'#FF6D00',bkD:'#BF360C',gear:'bandana',bandC:'#FFC400',eye:'fierce',brow:'angry',beak:'grin',wing:'up'})},
 freshFeathers(c){A_P(c,[[-200,-40],[-80,-40],[-70,160],[-210,160]],'#FF4FB7');A_L(c,[[-170,-40],[-160,-100],[-120,-100],[-110,-40]],'#FF4FB7',10);A_P(c,starPts(-140,60,34),'#fff');
  bird(c,80,30,.72,-6,{c:'#3DDBB0',d:'#00897B',hat:'beanie',hatC:'#FF4FB7',hatC2:'#C2185B',gear:'bowtie',bowC:'#FFC400',bowC2:'#E69500',beak:'grin',brow:'none',eye:'happy',blush:1});
  for(const[x,y,r]of[[180,-130,18],[-40,-160,14]])sparkle(c,x,y,r)},
 peacock(c){bird(c,20,40,.74,-4,{c:'#1E88E5',d:'#0D47A1',pat:'peacock',fan:1,hat:'crown',beak:'closed',brow:'none',eye:'half',wing:'tuck'})},
 earlyBird(c){A_C(c,0,170,120,'#FFF59D');for(let i=0;i<9;i++){const a=Math.PI+i/8*Math.PI;A_P(c,[[Math.cos(a-.08)*140,170+Math.sin(a-.08)*140],[Math.cos(a)*200,170+Math.sin(a)*200],[Math.cos(a+.08)*140,170+Math.sin(a+.08)*140]],'#FFF59D')}
  A_R(c,-260,170,520,100,'#6D4C41');
  bird(c,-10,20,.74,-6,{sh:'round',c:'#8D6E63',d:'#5D4037',belly:'#FF7043',beak:'worm',bk:'#FFB300',bkD:'#E69500',brow:'none',eye:'happy',wing:'up'})},
 homingPigeon(c){A_P(c,[[-200,40],[-130,-30],[-60,40]],'#E53935');A_R(c,-190,40,120,100,'#FFF8E1');A_R(c,-145,80,30,60,'#8D5A2B');
  c.save();c.rotate(-.15);A_R(c,90,-150,120,80,'#fff');A_P(c,[[90,-150],[150,-110],[210,-150]],'#E0E0E0');c.restore();
  bird(c,50,40,.72,-8,{c:'#90A4AE',d:'#546E7A',neck:'#7E57C2',hat:'mailcap',beak:'closed',brow:'raised',wing:'up'});
  speed(c,[[[180,120],[230,120]],[[170,160],[220,160]]])},
};

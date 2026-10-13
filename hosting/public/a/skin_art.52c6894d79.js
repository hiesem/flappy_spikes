// skin_art.js: catalogue + canvas art for the 5 customisation layers (bird, accessory, hat, hoop, fire).
// Bird art is drawn in the original 44x36 bird box (body 30x30 at 6,3); shapes vary but the hitbox does not.
const RAR={C:{n:'COMMON',c:'#9A9A9A',p:250},R:{n:'RARE',c:'#1E9BE0',p:750},E:{n:'EPIC',c:'#9B30D9',p:2000},L:{n:'LEGENDARY',c:'#FFB529',p:5000}};
const PINK='#EC008C',SOFT='#FCD9EE',GOLD='#FFB529',PLUM='#7A0044';
const TAU=Math.PI*2;
function oct(x,y,w,h,c){const p=new Path2D();p.moveTo(x+c,y);p.lineTo(x+w-c,y);p.lineTo(x+w,y+c);p.lineTo(x+w,y+h-c);p.lineTo(x+w-c,y+h);p.lineTo(x+c,y+h);p.lineTo(x,y+h-c);p.lineTo(x,y+c);p.closePath();return p}
function poly(pts){const p=new Path2D();pts.forEach(([x,y],i)=>i?p.lineTo(x,y):p.moveTo(x,y));p.closePath();return p}
function fillP(ctx,c,p){ctx.fillStyle=c;ctx.fill(p)}
function rr(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r)}
function circ(ctx,x,y,r,c){ctx.fillStyle=c;ctx.beginPath();ctx.arc(x,y,r,0,TAU);ctx.fill()}
function hash(i){const s=Math.sin(i*127.1+311.7)*43758.5453;return s-Math.floor(s)}

// ---------- catalogue ----------
const it=(id,n,r,o={})=>({id,n,r,...o});
const BIRDS=[
 it('classic','Classic','C',{free:1,sh:'sq',c:PINK,d:'#C2185B'}),
 it('sky','Sky','C',{sh:'sq',c:'#29B6F6',d:'#0277BD'}),
 it('lime','Lime','C',{sh:'sq',c:'#7CB342',d:'#33691E'}),
 it('grape','Grape','C',{sh:'sq',c:'#8E24AA',d:'#4A148C'}),
 it('tangerine','Tangerine','C',{sh:'sq',c:'#FF7A1A',d:'#C43E00'}),
 it('mint','Mint','C',{sh:'sq',c:'#3DDBB0',d:'#00897B'}),
 it('lemon','Lemonade','C',{sh:'sq',c:'#FFE03A',d:'#F29100',bk:'#FF5722',pat:'stripes'}),
 it('slate','Camo','C',{sh:'sq',c:'#7C8B6E',d:'#4B5842',pat:'camo'}),
 it('coral','Coral dots','C',{sh:'sq',c:'#FF6F61',d:'#C62828',pat:'dots'}),
 it('snow','Snow','C',{sh:'sq',c:'#FAFAFA',d:'#B0BEC5',ey:'#37474F'}),
 it('robin','Robin','R',{sh:'round',c:'#8D6E63',d:'#5D4037',belly:'#FF7043'}),
 it('toucan','Toucan','R',{sh:'tall',c:'#263238',d:'#000',belly:'#FFF59D',beak:'toucan'}),
 it('chick','Chick','R',{sh:'chick',c:'#FFD54F',d:'#FFA000',bk:'#FF7A1A'}),
 it('penguin','Penguin','R',{sh:'peng',c:'#263238',d:'#101518',belly:'#fff'}),
 it('owl','Owl','R',{sh:'owl',c:'#A1887F',d:'#6D4C41',belly:'#D7CCC8'}),
 it('duck','Rubber duck','R',{sh:'rduck',c:'#FFD600',d:'#F9A825',bk:'#FF5722',ey:'#212121'}),
 it('flamingo','Flamingo','R',{sh:'round',c:'#F48FB1',d:'#EC407A',beak:'hook'}),
 it('puffer','Puffer','R',{sh:'puff',c:'#FFCA28',d:'#F57F17',bk:'#FF7043'}),
 it('zebra','Zebra','R',{sh:'sq',c:'#FAFAFA',d:'#212121',pat:'zebra'}),
 it('buzz','Buzz','R',{sh:'round',c:'#FFC107',d:'#212121',pat:'bee',bk:'#212121'}),
 it('robo','Robo','E',{sh:'sq',c:'#B0BEC5',d:'#607D8B',pat:'robo',bk:'#78909C',anim:1}),
 it('zombie','Zombie','E',{sh:'sq',c:'#8BC34A',d:'#4E7A27',pat:'zombie'}),
 it('ghost','Ghost','E',{sh:'ghost',c:'#ECEFF1',d:'#B0BEC5',ey:'#263238',anim:1}),
 it('pixel','8-Bit','E',{sh:'pixel',c:PINK,d:PLUM}),
 it('frost','Frost','E',{sh:'sq',c:'#B3E5FC',d:'#4FC3F7',pat:'ice',anim:1}),
 it('magma','Magma','E',{sh:'sq',c:'#3E2723',d:'#1B0F0C',pat:'lava',bk:'#FF6D00',anim:1}),
 it('galaxy','Galaxy','L',{sh:'round',c:'#2A1260',d:'#120634',pat:'galaxy',anim:1}),
 it('golden','Golden','L',{sh:'sq',c:'#FFC629',d:'#C98A00',pat:'gold',bk:'#fff',anim:1}),
 it('rainbow','Rainbow','L',{sh:'sq',c:'#f44',d:'#fff',pat:'rainbow',anim:1}),
 it('phoenix','Phoenix','L',{sh:'round',c:'#FF5722',d:'#BF360C',pat:'phoenix',anim:1}),
];
const NONE=it('none','None','C',{free:1,none:1});
const ACCS=[NONE,
 it('shades','Shades','C'),it('bowtie','Bow tie','C'),it('stache','Mustache','C'),it('scarf','Scarf','C',{anim:1}),it('bandana','Bandana','C'),
 it('hearts','Heart shades','R'),it('monocle','Monocle','R'),it('sneakers','Sneakers','R',{anim:1}),it('windup','Wind-up key','R',{anim:1}),it('carpet','Magic carpet','R',{anim:1}),
 it('chain','Gold chain','E',{anim:1}),it('mask','Hero mask','E'),it('patch','Eye patch','E'),
 it('jetpack','Jetpack','L',{anim:1})];
const HATS=[NONE,
 it('cap','Cap','C'),it('beanie','Beanie','C'),it('party','Party hat','C'),it('band','Sweatband','C'),it('bucket','Bucket hat','C'),
 it('tophat','Top hat','R'),it('cowboy','Cowboy','R'),it('prop','Propeller','R',{anim:1}),it('chef','Chef','R'),it('viking','Viking','R'),
 it('pirate','Pirate','E'),it('wizard','Wizard','E',{anim:1}),
 it('crown','Crown','L',{anim:1}),it('halo','Halo','L',{anim:1})];
const HOOPS=[
 it('pink','Classic','C',{free:1,f:PINK,b:'#B0006B'}),it('sky','Sky','C',{f:'#29B6F6',b:'#0277BD'}),it('lime','Lime','C',{f:'#7CB342',b:'#33691E'}),
 it('violet','Violet','C',{f:'#8E24AA',b:'#4A148C'}),it('night','Midnight','C',{f:'#37474F',b:'#101518'}),
 it('candy','Candy cane','R',{f:'#fff',b:'#C62828',st:'candy'}),it('polka','Polka','R',{f:'#00ACC1',b:'#006064',st:'polka'}),
 it('checker','Finish line','R',{f:'#fff',b:'#212121',st:'checker'}),it('donut','Donut','R',{f:'#F48FB1',b:'#C68642',st:'donut'}),
 it('neon','Neon','E',{f:'#00E5FF',b:'#00838F',st:'neon',anim:1}),it('lava','Lava','E',{f:'#FF6D00',b:'#B71C1C',st:'lava',anim:1}),
 it('ice','Ice','E',{f:'#B3E5FC',b:'#4FC3F7',st:'ice',anim:1}),
 it('rainbow','Rainbow','L',{f:'#f00',b:'#800',st:'rainbow',anim:1}),it('galaxy','Galaxy','L',{f:'#3A1C8C',b:'#120634',st:'galaxy',anim:1}),it('blackhole','Black hole','L',{f:'#000',b:'#000',st:'blackhole',anim:1})];
const FIRES=[
 it('flame','Classic flame','C',{free:1,k:'flame',cols:['#FFF59D','#FFB529','#FF5722','#B71C1C']}),
 it('blue','Blue flame','C',{k:'flame',cols:['#fff','#80DEEA','#039BE5','#01579B']}),
 it('toxic','Toxic','C',{k:'flame',cols:['#F4FF81','#AEEA00','#43A047','#1B5E20']}),
 it('hot','Hot pink','C',{k:'flame',cols:['#fff',SOFT,PINK,PLUM]}),
 it('shadow','Shadow','C',{k:'flame',cols:['#E1BEE7','#9B30D9','#4A148C','#1a0630']}),
 it('sparkle','Sparkles','R',{k:'star'}),it('bubbles','Bubbles','R',{k:'bubble'}),it('hearts','Hearts','R',{k:'heart'}),
 it('laser','Laser','R',{k:'laser'}),it('confetti','Confetti','R',{k:'conf'}),
 it('bolt','Lightning','E',{k:'bolt'}),it('blocks','Pixel blocks','E',{k:'sq'}),it('notes','Music','E',{k:'note'}),
 it('rainbow','Rainbow','L',{k:'ribbon'}),it('echo','Afterimage','L',{k:'echo'})];
const CATS={bird:BIRDS,acc:ACCS,hat:HATS,hoop:HOOPS,fire:FIRES};
const CAT_NAMES={bird:'BIRDS',acc:'GEAR',hat:'HATS',hoop:'HOOPS',fire:'TRAILS'};
for(const k in CATS)for(const x of CATS[k])x.price=x.free?0:RAR[x.r].p+(k==='bird'&&x.r==='C'?-100:0);
const byId=(cat,id)=>CATS[cat].find(x=>x.id===id)||CATS[cat][0];
const TOTAL=Object.values(CATS).reduce((a,l)=>a+l.filter(x=>!x.none).length,0); // 90

// ---------- bird shapes (anchors in the 44x36 box) ----------
const SH={
 sq:{body(){const p=new Path2D();p.rect(6,3,30,30);return p},eye:[28,12],beak:[[36,14],[44,20],[36,26]],tail:[[0,8],[9,14],[0,20]],wing:[12,17,24],top:3,neck:27,bot:33,l:6,r:36,hx:23},
 round:{body(){return oct(5,2,32,32,8)},eye:[28,11],beak:[[35,13],[44,19],[35,25]],tail:[[0,10],[9,15],[0,21]],wing:[11,19,23],top:2,neck:27,bot:34,l:5,r:37,hx:23},
 tall:{body(){const p=new Path2D();p.rect(6,3,30,30);return p},eye:[27,9],beak:[[36,5],[47,9],[44,20],[36,20]],tail:[[0,8],[9,14],[0,20]],wing:[12,19,24],top:3,neck:24,bot:33,l:6,r:36,hx:21},
 chick:{body(){return oct(7,6,28,28,7)},eye:[27,15],beak:[[34,17],[42,21],[34,25]],tail:[[3,15],[11,19],[3,23]],wing:[12,22,22],top:6,neck:29,bot:34,l:7,r:35,hx:22},
 peng:{body(){return oct(7,1,28,34,7)},eye:[27,9],beak:[[33,10],[41,13],[33,16]],tail:[[3,24],[11,27],[3,31]],wing:[11,17,20],top:1,neck:19,bot:35,l:7,r:35,hx:22},
 owl:{body(){const p=new Path2D();p.rect(6,5,30,28);return p},eye:[27,14],beak:[[35,13],[41,17],[35,21]],tail:[[0,10],[9,15],[0,20]],wing:[12,19,24],top:5,neck:28,bot:33,l:6,r:36,hx:21},
 puff:{body(){return oct(8,5,26,26,7)},eye:[27,13],beak:[[33,15],[41,19],[33,23]],tail:[[0,10],[9,15],[0,21]],wing:[12,19,22],top:1,neck:27,bot:35,l:4,r:38,hx:21},
 ghost:{body(){const p=new Path2D();p.moveTo(6,33);p.lineTo(6,17);p.arc(21,17,15,Math.PI,0);p.lineTo(36,33);for(let i=0;i<5;i++){const x=36-i*6;p.quadraticCurveTo(x-1.5,28,x-3,31);p.quadraticCurveTo(x-4.5,35,x-6,33)}p.closePath();return p},eye:[27,13],beak:[[36,15],[43,19],[36,23]],tail:[[1,12],[8,16],[1,20]],wing:[12,19,23],top:2,neck:27,bot:33,l:6,r:36,hx:22},
 // bath-toy rubber duck: head bump forward over a boat body with an upturned tail; l = head back (head-level gear), bl = stern (wind-up key)
 rduck:{body(){return poly([[23,1],[31,1],[36,6],[36,13],[34,17],[39,21],[39,27],[33,34],[11,34],[5,29],[3,21],[1,8],[6,11],[11,18],[18,18],[18,6]])},eye:[30,8],beak:[[33,10],[43,10],[46,12.5],[43,14.5],[45,16.5],[42,18],[33,18]],tail:[[6,22],[10,22],[8,25]],wing:[12,25,26],top:1,neck:19,bot:34,l:18,r:36,hx:27,bl:4},
 pixel:{body(){const p=new Path2D();const rows=[[3,5],[1,7],[0,8],[0,8],[0,8],[0,8],[1,7],[3,5]];rows.forEach(([a,b],j)=>p.rect(5+a*4,2+j*4,(b-a)*4,4));return p},eye:[28,12],beak:[[37,14],[41,14],[41,18],[45,18],[45,22],[37,22]],tail:[[0,10],[5,10],[5,14],[9,14],[9,18],[0,18]],wing:[13,18,25],top:2,neck:28,bot:34,l:5,r:37,hx:21,px:1},
};

function birdBody(ctx,b,t){
 const s=SH[b.sh],body=s.body();
 // behind the body
 if(b.sh==='owl'){fillP(ctx,b.d,poly([[7,1],[13,6],[7,8]]));fillP(ctx,b.d,poly([[35,1],[29,6],[35,8]]))}
 if(b.sh==='puff'){ctx.fillStyle=b.d;for(let i=0;i<14;i++){const a=i/14*TAU+.2,c=Math.cos(a),sn=Math.sin(a);ctx.fill(poly([[21+c*11-sn*2.6,18+sn*11+c*2.6],[21+c*17,18+sn*17],[21+c*11+sn*2.6,18+sn*11-c*2.6]]))}}
 if(b.pat==='phoenix'){for(let i=0;i<3;i++){const f=Math.sin(t*9+i*2)*1.5;fillP(ctx,['#FFB529','#FF7043','#FFEB3B'][i],poly([[14+i*5,5],[11+i*6+f,-6+i*1.5],[19+i*5,4]]))}
  ctx.fill(poly([[6,14],[-6+Math.sin(t*8)*2,9],[-2,16],[-8,21+Math.sin(t*7)*2],[6,22]]))}
 else fillP(ctx,b.d,poly(s.tail));
 if(b.pat==='robo'){ctx.strokeStyle='#607D8B';ctx.lineWidth=1.5;ctx.beginPath();ctx.moveTo(18,3);ctx.lineTo(18,-4);ctx.stroke();circ(ctx,18,-5,2.2,Math.sin(t*6)>0?'#FF1744':'#B71C1C')}
 if(b.sh==='chick'){fillP(ctx,b.d,poly([[19,7],[17,0],[22,6],[24,1],[24,7]]))}
 // body fill
 ctx.save();
 if(b.sh==='ghost')ctx.globalAlpha=.88;
 let fs=b.c;
 if(b.pat==='galaxy'){const g=ctx.createRadialGradient(18,14,2,21,18,18);g.addColorStop(0,'#6A3DE8');g.addColorStop(.6,b.c);g.addColorStop(1,b.d);fs=g}
 if(b.pat==='gold'){const g=ctx.createLinearGradient(6,3,36,33);g.addColorStop(0,'#FFE082');g.addColorStop(.5,'#FFC629');g.addColorStop(1,'#E69500');fs=g}
 if(b.pat==='phoenix'){const g=ctx.createLinearGradient(0,34,0,2);g.addColorStop(0,'#D84315');g.addColorStop(.6,'#FF7043');g.addColorStop(1,'#FFCA28');fs=g}
 if(b.pat==='ice'){const g=ctx.createLinearGradient(6,3,36,33);g.addColorStop(0,'#E1F5FE');g.addColorStop(1,'#81D4FA');fs=g}
 ctx.fillStyle=fs;ctx.fill(body);ctx.clip(body);
 if(b.sh==='rduck'){ctx.fillStyle='#1E88E5';ctx.fillRect(17,2.6,20,3.2);fillP(ctx,'#fff',poly([[20,10],[23,7],[25,7],[22,12]]))}
 const P=b.pat;
 if(b.belly){ctx.fillStyle=b.belly;ctx.fill(b.sh==='peng'?oct(18,14,15,19,5):b.sh==='tall'?poly([[24,15],[36,15],[36,28],[28,26]]):b.sh==='owl'?poly([[14,33],[14,24],[22,19],[30,24],[30,33]]):oct(s.r-19,s.bot-15,18,18,6));if(b.sh==='owl'){ctx.fillStyle=b.d;for(const[x,y]of[[18,25],[24,25],[21,29],[27,29]])ctx.fill(poly([[x-2,y],[x,y+2],[x+2,y]]))}}
 if(P==='zebra'){ctx.fillStyle=b.d;for(let i=-2;i<6;i++)ctx.fill(poly([[i*8,0],[i*8+4,0],[i*8+18,36],[i*8+14,36]]))}
 if(P==='stripes'){ctx.fillStyle=b.d;for(let i=-3;i<7;i++)ctx.fill(poly([[i*7,36],[i*7+3,36],[i*7+21,0],[i*7+18,0]]))}
 if(P==='camo'){for(const[x,y,w,h,c]of[[6,3,10,6,'#4B5842'],[20,6,12,5,'#A3AE87'],[8,14,8,8,'#A3AE87'],[24,14,12,7,'#4B5842'],[14,22,10,6,'#5E6B4F'],[28,25,8,8,'#A3AE87'],[6,27,8,6,'#4B5842'],[16,9,4,4,'#3A4433']]){ctx.fillStyle=c;ctx.fillRect(x,y,w,h)}}
 if(P==='dots'){ctx.fillStyle='#fff';for(let j=0;j<5;j++)for(let i=0;i<5;i++)if((i+j)%2===0)ctx.fillRect(7+i*6.4,4+j*6.4,3.2,3.2)}
 if(P==='bee'){ctx.fillStyle=b.d;ctx.fillRect(12,0,4.5,36);ctx.fillRect(21,0,4.5,36)}
 if(P==='robo'){ctx.strokeStyle='#78909C';ctx.lineWidth=1;ctx.strokeRect(9,6,24,24);ctx.beginPath();ctx.moveTo(6,18);ctx.lineTo(36,18);ctx.stroke();for(const[x,y]of[[9,6],[33,6],[9,30],[33,30]])circ(ctx,x,y,1.2,'#546E7A');ctx.fillStyle='#90A4AE';ctx.fillRect(13,21,10,6)}
 if(P==='zombie'){ctx.fillStyle='#689F38';ctx.fillRect(8,20,9,8);ctx.fillRect(22,5,6,4);ctx.strokeStyle='#33691E';ctx.lineWidth=1.2;ctx.beginPath();ctx.moveTo(12,8);ctx.lineTo(22,26);for(let i=0;i<4;i++){const u=i/3,x=12+u*10,y=8+u*18;ctx.moveTo(x-2.2,y+1.2);ctx.lineTo(x+2.2,y-1.2)}ctx.stroke()}
 if(P==='ice'){ctx.fillStyle='rgba(255,255,255,.55)';ctx.fill(poly([[6,3],[20,3],[6,17]]));ctx.fillStyle='rgba(2,136,209,.18)';ctx.fill(poly([[36,12],[36,33],[18,33]]));ctx.strokeStyle='rgba(255,255,255,.8)';ctx.lineWidth=.8;ctx.beginPath();ctx.moveTo(6,24);ctx.lineTo(20,10);ctx.lineTo(36,22);ctx.stroke()}
 if(P==='lava'){const g=.6+.4*Math.sin(t*4);ctx.strokeStyle=`rgba(255,${110+80*g|0},0,${.7+.3*g})`;ctx.lineWidth=1.6;ctx.beginPath();ctx.moveTo(6,10);ctx.lineTo(14,14);ctx.lineTo(12,22);ctx.lineTo(20,27);ctx.lineTo(18,33);ctx.moveTo(14,14);ctx.lineTo(24,12);ctx.lineTo(30,4);ctx.moveTo(20,27);ctx.lineTo(36,25);ctx.stroke()}
 if(P==='galaxy'){for(let i=0;i<14;i++){const x=6+hash(i)*30,y=3+hash(i+40)*30,tw=.4+.6*Math.abs(Math.sin(t*2+i*1.7));circ(ctx,x,y,.5+hash(i+9)*1.1*tw,`rgba(255,255,255,${tw})`)}}
 if(P==='gold'){const u=((t*.45)%1.6)*60-30;ctx.fillStyle='rgba(255,255,255,.65)';ctx.fill(poly([[u,0],[u+7,0],[u-8,36],[u-15,36]]))}
 if(P==='rainbow'){const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'];for(let i=-1;i<7;i++){ctx.fillStyle=C[((i+Math.floor(t*4))%6+6)%6];ctx.fillRect(0,3+i*5+(t*20%5),44,5.2)}}
 ctx.restore();
}
function birdFace(ctx,b,t,flap){
 const s=SH[b.sh];
 // wing
 const[w0,wy,w1]=s.wing;const wc=b.pat==='rainbow'?'#fff':b.pat==='gold'?'#E69500':b.pat==='galaxy'?'#6A3DE8':b.pat==='phoenix'?'#FFEB3B':b.d;
 if(s.px){ctx.fillStyle=wc;flap?(ctx.fillRect(w0,wy,12,4),ctx.fillRect(w0,wy+4,4,4)):(ctx.fillRect(w0,wy-4,4,4),ctx.fillRect(w0,wy-1,12,4))}
 else fillP(ctx,wc,poly(flap?[[w0,wy],[w1,wy],[w0,wy+9]]:[[w0,wy-8],[w1,wy],[w0,wy]]));
 // eye
 const[ex,ey]=s.eye;
 if(b.sh==='owl'){ctx.fillStyle='#fff';ctx.fillRect(ex-5,ey-5,10,10);ctx.fillStyle='#212121';ctx.fillRect(ex-1,ey-2.5,5,5);ctx.fillStyle='#fff';ctx.fillRect(ex+1.5,ey-2,1.5,1.5);ctx.fillStyle=b.d;ctx.fill(poly([[ex-7,ey-8],[ex+6,ey-6],[ex+6,ey-5],[ex-7,ey-5]]))}
 else if(b.pat==='robo'){ctx.fillStyle='#212121';ctx.fillRect(ex-4,ey-3,9,6);ctx.fillStyle=Math.sin(t*3)>-.8?'#FF1744':'#7f0000';ctx.fillRect(ex-1,ey-1.5,4,3)}
 else if(b.pat==='zombie'){ctx.strokeStyle='#212121';ctx.lineWidth=1.5;ctx.beginPath();ctx.moveTo(ex-2.5,ey-2.5);ctx.lineTo(ex+2.5,ey+2.5);ctx.moveTo(ex+2.5,ey-2.5);ctx.lineTo(ex-2.5,ey+2.5);ctx.stroke()}
 else if(b.sh==='ghost'){ctx.fillStyle=b.ey;ctx.beginPath();ctx.ellipse(ex,ey,2,3.2,0,0,TAU);ctx.fill()}
 else{ctx.fillStyle=b.ey||(b.pat==='rainbow'||b.pat==='galaxy'?'#fff':'#fff');ctx.fillRect(ex-2,ey-2,4,4);if(b.c==='#FAFAFA'||b.c==='#FFE03A'||b.pat==='ice'){ctx.fillStyle='#37474F';ctx.fillRect(ex-1,ey-1,3,3)}}
 // beak
 if(b.beak==='toucan'){const g=ctx.createLinearGradient(32,0,45,0);g.addColorStop(0,'#FFEB3B');g.addColorStop(.7,'#FF9800');g.addColorStop(1,'#E53935');ctx.fillStyle=g;ctx.fill(poly(s.beak));fillP(ctx,'#212121',poly([[42,7],[47,9],[45.8,14],[42,14]]));fillP(ctx,'rgba(0,0,0,.25)',poly([[36,14],[45.3,14],[44,20],[36,20]]))}
 else if(b.beak==='hook'){fillP(ctx,'#fff',poly([[35,13],[42,15],[44,20],[35,21]]));fillP(ctx,'#212121',poly([[42,15],[44,20],[42,23],[39,19]]))}
 else fillP(ctx,b.bk||GOLD,poly(s.beak));
}

// ---------- accessories (back layer, front layer) ----------
function accBack(ctx,id,s,t,flap){
 if(id==='windup'){// brass toy key in the lower back; winds in clockwork half-turns (turn 40 %, rest 60 %), resting face-on
  const k=Math.floor(t*1.2),f=Math.min(1,(t*1.2-k)/.4),a=(k+f*f*(3-2*f))*Math.PI,c=Math.cos(a),sc=Math.sign(c||1)*Math.max(.12,Math.abs(c));
  const x=s.bl??s.l,y=s.bot-8;ctx.fillStyle='#A8741A';ctx.fillRect(x-4,y-1.3,6,2.6);ctx.fillRect(x-5.5,y-2.6,2,5.2);
  ctx.save();ctx.translate(x-5.5,y);ctx.scale(1,sc);const bow=new Path2D();bow.addPath(oct(-12,-7.5,8,7,2));bow.addPath(oct(-12,.5,8,7,2));bow.rect(-4,-1.8,4,3.6);bow.rect(-10,-5.2,4,2.4);bow.rect(-10,2.8,4,2.4);
  ctx.fillStyle=Math.abs(k%2)?'#C98B22':'#F2B33D';ctx.fill(bow,'evenodd');ctx.fillStyle='rgba(255,236,160,.9)';ctx.fillRect(-11,-6.6,5,1.1);ctx.fillRect(-11,1.4,5,1.1);ctx.restore()}
 if(id==='jetpack'){ctx.fillStyle='#90A4AE';rr(ctx,s.l-8,s.neck-17,9,17,2);ctx.fill();ctx.fillStyle='#607D8B';ctx.fillRect(s.l-7,s.neck,7,3);const f=4+Math.random()*4;fillP(ctx,'#FFB529',poly([[s.l-7,s.neck+3],[s.l-3.5,s.neck+3+f+3],[s.l,s.neck+3]]));fillP(ctx,'#FFF59D',poly([[s.l-6,s.neck+3],[s.l-3.5,s.neck+3+f],[s.l-1,s.neck+3]]))}
 if(id==='angel'){ctx.save();ctx.shadowColor='rgba(255,196,0,.95)';ctx.shadowBlur=7;const up=flap?1:-1;ctx.translate(s.l+8,s.top+12);ctx.rotate(up*.35-.2);
  for(let i=0;i<3;i++){ctx.fillStyle=['#FFF8E1','#FFFDF5','#fff'][i];ctx.strokeStyle='#FFD54F';ctx.lineWidth=.8;ctx.beginPath();ctx.ellipse(-9-i*5,-7+i*4.5,12-i*2,4.4,-.5,0,TAU);ctx.fill();ctx.stroke()}ctx.restore()}
 if(id==='scarf'){ctx.fillStyle='#E53935';const w=Math.sin(t*10)*2;ctx.fill(poly([[s.l+2,s.neck-3],[s.l-9,s.neck+1+w],[s.l-11,s.neck+5+w],[s.l+2,s.neck+3]]))}
}
function accFront(ctx,id,s,t,flap){
 const[ex,ey]=s.eye;
 switch(id){
 case'carpet':{const x0=s.l-8,x1=s.r+6,n=10,y=s.bot-.5,wv=i=>Math.sin(t*6-i*.9)*1.6,X=i=>x0+(x1-x0)*i/n;
  ctx.fillStyle='#8E1B3A';ctx.beginPath();for(let i=0;i<=n;i++)ctx.lineTo(X(i),y+wv(i));for(let i=n;i>=0;i--)ctx.lineTo(X(i),y+5+wv(i));ctx.fill();
  ctx.fillStyle=GOLD;for(let i=0;i<n;i++){const xm=(X(i)+X(i+1))/2,ym=y+2.5+(wv(i)+wv(i+1))/2;ctx.fillRect(xm-.9,ym-.9,1.8,1.8)}
  ctx.fillRect(x0-.5,y+wv(0)-.5,(x1-x0)*.08,1);for(const i of[0,n]){const yy=y+wv(i);for(let k=0;k<3;k++)ctx.fillRect(X(i)+(i?0:-2.2),yy+.5+k*1.7,2.2,.9)}
  ctx.fillStyle='rgba(255,255,255,.18)';ctx.beginPath();for(let i=0;i<=n;i++)ctx.lineTo(X(i),y+wv(i));for(let i=n;i>=0;i--)ctx.lineTo(X(i),y+1.2+wv(i));ctx.fill();break}
 case'shades':{const u=1.5,x0=ex-5,y0=ey-3;ctx.fillStyle='#111';ctx.fillRect(s.l+6,y0,x0-s.l-6,u);ctx.fillRect(x0-u,y0,10*u,u);ctx.fillRect(x0,y0+u,8*u,u);ctx.fillRect(x0,y0+2*u,8*u,u);ctx.fillRect(x0+u,y0+3*u,6*u,u);ctx.fillRect(x0+2*u,y0+4*u,4*u,u);
  ctx.fillStyle='#fff';ctx.fillRect(x0+u,y0+u,u,u);ctx.fillRect(x0+2*u,y0+2*u,u,u);ctx.fillRect(x0+4*u,y0+u,u,u);ctx.fillRect(x0+5*u,y0+2*u,u,u);break}
 case'hearts':{const u=1.6,H=['.XX.XX.','XXXXXXX','XXXXXXX','.XXXXX.','..XXX..','...X...'],x0=ex-3.5*u+.5,y0=ey-3*u;ctx.fillStyle='#111';ctx.fillRect(s.l+6,y0+u,x0-s.l-6,u);
  ctx.fillStyle='#111';H.forEach((r,j)=>[...r].forEach((c,i)=>{if(c==='X')ctx.fillRect(x0+i*u-.6*u,y0+j*u-.6*u,2.2*u,2.2*u)}));H.forEach((r,j)=>[...r].forEach((c,i)=>{if(c==='X'){ctx.fillStyle='#FF1F64';ctx.fillRect(x0+i*u,y0+j*u,u+.05,u+.05)}}));ctx.fillStyle='#B0003A';ctx.fillRect(x0+5*u,y0+2*u,u,u);ctx.fillRect(x0+4*u,y0+3*u,u,u);ctx.fillStyle='#fff';ctx.fillRect(x0+u,y0+u,u,u);ctx.fillRect(x0+2*u,y0+u,u*.9,u*.9);break}
 case'monocle':ctx.strokeStyle=GOLD;ctx.lineWidth=1.4;ctx.beginPath();ctx.arc(ex,ey,4.6,0,TAU);ctx.stroke();ctx.fillStyle='rgba(200,230,255,.35)';ctx.fill();ctx.lineWidth=.8;ctx.beginPath();ctx.moveTo(ex-1,ey+4.6);ctx.quadraticCurveTo(ex-3,ey+12,ex-8,ey+13);ctx.stroke();break;
 case'mask':ctx.fillStyle='#212121';ctx.fillRect(s.l,ey-3.5,s.r-s.l,7);ctx.fill(poly([[s.l,ey-3],[s.l-6,ey-6],[s.l-4,ey],[s.l,ey+3]]));ctx.fillStyle='#fff';ctx.fillRect(ex-2,ey-2,4,4);break;
 case'patch':ctx.strokeStyle='#212121';ctx.lineWidth=1.2;ctx.beginPath();ctx.moveTo(s.l,ey-6);ctx.lineTo(s.r,ey+3);ctx.stroke();circ(ctx,ex,ey,4.4,'#212121');break;
 case'stache':ctx.fillStyle='#4E342E';ctx.beginPath();ctx.ellipse(s.r-1,ey+9,4,2.2,.2,0,TAU);ctx.ellipse(s.r+4,ey+9.5,4,2.2,-.2,0,TAU);ctx.fill();break;
 case'bowtie':{const x=s.r-6,y=s.neck;fillP(ctx,'#E53935',poly([[x-5,y-4],[x,y],[x-5,y+4]]));fillP(ctx,'#E53935',poly([[x+5,y-4],[x,y],[x+5,y+4]]));circ(ctx,x,y,1.8,'#B71C1C');break}
 case'scarf':ctx.fillStyle='#E53935';ctx.fillRect(s.l,s.neck-3,s.r-s.l,6);ctx.fillStyle='#fff';for(let x=s.l+3;x<s.r;x+=6)ctx.fillRect(x,s.neck-3,2,6);break;
 case'bandana':{fillP(ctx,'#1E88E5',poly([[s.l+4,s.neck-3],[s.r,s.neck-3],[s.r-10,s.neck+7]]));ctx.fillStyle='#fff';for(const[x,y]of[[s.r-16,s.neck-1],[s.r-9,s.neck],[s.r-12,s.neck+3]])circ(ctx,x,y,.9,'#fff');break}
 case'chain':{ctx.strokeStyle=GOLD;ctx.lineWidth=1.6;ctx.setLineDash([2,1.2]);ctx.beginPath();ctx.moveTo(s.l+6,s.neck-4);ctx.quadraticCurveTo(s.r-8,s.neck+6,s.r-2,s.neck-4);ctx.stroke();ctx.setLineDash([]);
  const sw=Math.sin(t*5)*.8;circ(ctx,s.r-9+sw,s.neck+3,3.4,GOLD);ctx.fillStyle='#fff';ctx.font='bold 4px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('$',s.r-9+sw,s.neck+3.3);break}
 case'sneakers':{const sw=flap?-.5:.4;for(const[k,x]of[[0,s.r-16],[1,s.r-7]]){ctx.save();ctx.translate(x,s.bot);ctx.rotate(sw*(k?1:.6));ctx.fillStyle='#FFB529';ctx.fillRect(-.6,0,1.2,4);ctx.fillStyle='#E53935';rr(ctx,-3,3.5,8,4,[2,3,1,1]);ctx.fill();ctx.fillStyle='#fff';ctx.fillRect(-3,6.5,8,1.5);ctx.restore()}break}
 case'jetpack':ctx.fillStyle='#455A64';ctx.fillRect(s.l,s.neck-14,2.5,12);break;
 }
}
function heart(ctx,x,y,s,c){ctx.save();ctx.translate(x,y);ctx.scale(s/10,s/10);ctx.fillStyle=c;ctx.beginPath();ctx.moveTo(0,4);ctx.bezierCurveTo(-7,-1,-5,-7,0,-3.5);ctx.bezierCurveTo(5,-7,7,-1,0,4);ctx.fill();ctx.restore()}

// ---------- hats (anchored to the head top) ----------
function hat(ctx,id,s,t){
 const x=s.hx,y=s.top;
 switch(id){
 case'cap':ctx.fillStyle='#1E88E5';ctx.beginPath();ctx.arc(x,y+2,10,Math.PI,0);ctx.fill();ctx.fillRect(x,y-1,17,3);circ(ctx,x,y-8,1.6,'#0D47A1');ctx.fillStyle='#fff';ctx.fillRect(x-3,y-6,5,3);break;
 case'beanie':ctx.fillStyle='#E53935';ctx.beginPath();ctx.arc(x,y+2,11,Math.PI,0);ctx.fill();ctx.fillStyle='#fff';ctx.fillRect(x-12,y-1,24,4.5);circ(ctx,x,y-10,3.4,'#fff');break;
 case'party':{ctx.save();ctx.translate(x,y+1);ctx.rotate(.2);const p=poly([[-8,0],[0,-20],[8,0]]);ctx.fillStyle='#29B6F6';ctx.fill(p);ctx.clip(p);ctx.fillStyle='#FFEB3B';for(let i=0;i<4;i++)ctx.fillRect(-10,-4-i*6,20,2.5);ctx.restore();ctx.save();ctx.translate(x,y+1);ctx.rotate(.2);circ(ctx,0,-20,2.6,PINK);ctx.restore();break}
 case'band':ctx.fillStyle='#E53935';ctx.fillRect(s.l,y+2,s.r-s.l,4.5);ctx.fillStyle='#fff';ctx.fillRect(s.l,y+3.5,s.r-s.l,1.4);fillP(ctx,'#E53935',poly([[s.l,y+3],[s.l-8,y+1+Math.sin(t*8)],[s.l-7,y+6],[s.l,y+6.5]]));break;
 case'bucket':ctx.fillStyle='#C5B358';ctx.fill(poly([[x-8,y-9],[x+8,y-9],[x+10,y+1],[x-10,y+1]]));ctx.fillStyle='#A1903A';rr(ctx,x-15,y,30,3.6,2);ctx.fill();ctx.fillRect(x-9,y-3,18,2);break;
 case'tophat':ctx.fillStyle='#212121';ctx.fillRect(x-8,y-16,16,16);ctx.fillRect(x-13,y-1,26,3);ctx.fillStyle=PINK;ctx.fillRect(x-8,y-5,16,3);break;
 case'cowboy':ctx.fillStyle='#8D5A2B';ctx.fill(poly([[x-18,y-7],[x-14,y],[x+14,y],[x+18,y-7],[x+13,y-3],[x-13,y-3]]));ctx.fill(poly([[x-9,y-3],[x-8,y-14],[x-3,y-12],[x,y-14],[x+3,y-12],[x+8,y-14],[x+9,y-3]]));ctx.fillStyle='#5D3A1A';ctx.fillRect(x-9,y-6,18,3);break;
 case'prop':ctx.fillStyle='#E53935';ctx.fillRect(x-10,y-6,7,7);ctx.fillStyle='#FFEB3B';ctx.fillRect(x-3,y-6,6,7);ctx.fillStyle='#1E88E5';ctx.fillRect(x+3,y-6,7,7);ctx.fillStyle='#E53935';ctx.fillRect(x-6,y-9,12,3);ctx.fillStyle='#1E88E5';ctx.fillRect(x+8,y-1,9,2.5);
  ctx.fillStyle='#555';ctx.fillRect(x-.8,y-14,1.6,5);const w=Math.cos(t*22)*12;ctx.fillStyle='#E53935';ctx.fillRect(x-Math.abs(w)-.5,y-15.5,Math.abs(w)*2+1,2.6);ctx.fillStyle='#FFEB3B';ctx.fillRect(x-1.5,y-15.8,3,3.2);break;
 case'chef':ctx.fillStyle='#fff';ctx.strokeStyle='#D0D0D0';ctx.lineWidth=.8;ctx.fillRect(x-8,y-7,16,8);ctx.strokeRect(x-8,y-7,16,8);ctx.fill(oct(x-12,y-19,24,13,4));ctx.stroke(oct(x-12,y-19,24,13,4));ctx.fillRect(x-7.6,y-8,15.2,3);ctx.beginPath();ctx.moveTo(x-4,y-19);ctx.lineTo(x-4,y-12);ctx.moveTo(x+4,y-19);ctx.lineTo(x+4,y-12);ctx.stroke();break;
 case'viking':ctx.fillStyle='#F5F5DC';ctx.fill(poly([[x-9,y-3],[x-16,y-15],[x-13,y-15],[x-12,y-6]]));ctx.fill(poly([[x+9,y-3],[x+16,y-15],[x+13,y-15],[x+12,y-6]]));ctx.fillStyle='#90A4AE';ctx.fill(poly([[x-11,y+1],[x-10,y-7],[x-5,y-11],[x+5,y-11],[x+10,y-7],[x+11,y+1]]));ctx.fillStyle='#607D8B';ctx.fillRect(x-12,y-1,24,3.5);ctx.fillRect(x-1.5,y-11,3,10);for(const dx of[-8,-4,4,8])ctx.fillRect(x+dx-.8,y-.3,1.6,1.6);break;
 case'pirate':ctx.fillStyle='#212121';ctx.fill(poly([[x-17,y+1],[x-13,y-12],[x-5,y-9],[x,y-15],[x+5,y-9],[x+13,y-12],[x+17,y+1]]));ctx.fillStyle=GOLD;ctx.fill(poly([[x-17,y+1],[x-16,y-2],[x+16,y-2],[x+17,y+1]]));ctx.fillStyle='#fff';ctx.fillRect(x-3,y-10,6,5);ctx.fillRect(x-2,y-5,4,1.5);ctx.fillStyle='#212121';ctx.fillRect(x-2,y-9,1.6,1.6);ctx.fillRect(x+.4,y-9,1.6,1.6);break;
 case'wizard':{ctx.fillStyle='#5E35B1';ctx.fill(poly([[x-11,y],[x-4,y-14],[x,y-22],[x+8,y-26],[x+4,y-19],[x+11,y]]));ctx.fillStyle='#4527A0';ctx.fillRect(x-15,y-1,30,3.5);ctx.fillStyle='#FFEB3B';ctx.fillRect(x-10,y-5,20,2.5);
  for(let i=0;i<3;i++){const tw=Math.abs(Math.sin(t*3+i*2));star(ctx,x-4+i*3.5,y-8-i*5,1.4+tw*1.4,'#FFEB3B',t+i)}break}
 case'astro':break;
 case'crown':{ctx.fillStyle=GOLD;ctx.fill(poly([[x-11,y+1],[x-11,y-10],[x-6,y-4],[x,y-13],[x+6,y-4],[x+11,y-10],[x+11,y+1]]));circ(ctx,x,y-3,2,'#E53935');circ(ctx,x-7,y-2,1.4,'#1E88E5');circ(ctx,x+7,y-2,1.4,'#43A047');
  const sh=(t*.6)%2;if(sh<1){star(ctx,x-11+sh*22,y-11+Math.sin(sh*Math.PI)*-2,2.4,'#fff',t)}break}
 case'halo':{const b=Math.sin(t*3)*1.5;ctx.save();ctx.shadowColor='rgba(255,214,0,.9)';ctx.shadowBlur=6;ctx.strokeStyle='#FFD600';ctx.lineWidth=2.6;ctx.beginPath();ctx.ellipse(x,y-9+b,11,3.4,0,0,TAU);ctx.stroke();ctx.restore();break}
 }
}
function star(ctx,x,y,r,c,rot=0){ctx.save();ctx.translate(x,y);ctx.rotate(rot);ctx.fillStyle=c;ctx.beginPath();for(let i=0;i<8;i++){const rr=i%2?r*.38:r,a=i*Math.PI/4;ctx.lineTo(Math.cos(a)*rr,Math.sin(a)*rr)}ctx.fill();ctx.restore()}

// whole bird: look = {bird,acc,hat}; drawn centred at 0,0 in bird units (caller scales)
// draws fn at alpha `dim` as one flat layer (no see-through overlaps inside it); used for try-on previews
const LAY=document.createElement('canvas'),LC=LAY.getContext('2d');
function layer(ctx,dim,fn){if(!dim){fn(ctx);return}const cv=ctx.canvas;if(LAY.width!==cv.width||LAY.height!==cv.height){LAY.width=cv.width;LAY.height=cv.height}
 LC.setTransform(1,0,0,1,0,0);LC.globalAlpha=1;LC.clearRect(0,0,LAY.width,LAY.height);LC.setTransform(ctx.getTransform());fn(LC);
 ctx.save();ctx.setTransform(1,0,0,1,0,0);ctx.globalAlpha*=dim;ctx.drawImage(LAY,0,0);ctx.restore()}
function drawLook(ctx,look,t=0,flap=false,o={}){
 const b=byId('bird',look.bird),s=SH[b.sh],acc=look.acc||'none',h=look.hat||'none';
 ctx.save();ctx.translate(-22,-18);
 if(o.ghost){ctx.globalAlpha=o.ghost}
 const D=o.dim||{};
 layer(ctx,D.acc,c=>accBack(c,acc,s,t,flap));
 layer(ctx,D.bird,c=>{birdBody(c,b,t);birdFace(c,b,t,flap)});
 if(acc==='angel'){ctx.save();ctx.globalAlpha*=.95;ctx.fillStyle='#fff';const[w0,wy,w1]=s.wing;ctx.fill(poly(flap?[[w0,wy],[w1,wy],[w0,wy+9]]:[[w0,wy-8],[w1,wy],[w0,wy]]));ctx.restore()}
 layer(ctx,D.acc,c=>accFront(c,acc,s,t,flap));
 if(h==='astro'){ctx.save();ctx.strokeStyle='rgba(255,255,255,.95)';ctx.lineWidth=1.6;ctx.fillStyle='rgba(179,229,252,.28)';ctx.beginPath();ctx.arc(22,17,23,0,TAU);ctx.fill();ctx.stroke();
  ctx.fillStyle='rgba(255,255,255,.7)';ctx.beginPath();ctx.ellipse(12,6,5,2.4,-.6,0,TAU);ctx.fill();ctx.fillStyle='#ECEFF1';rr(ctx,8,37,28,4,2);ctx.fill();ctx.restore()}
 else layer(ctx,D.hat,c=>hat(c,h,s,t));
 ctx.restore();
}
// mannequin used to show gear and hats on their own
const MANNEQUIN={sh:'sq',c:'#DCDCDC',d:'#C4C4C4',bk:'#CFCFCF',ey:'#fff'};
function drawOnMannequin(ctx,cat,id,t,flap){
 const s=SH.sq;ctx.save();ctx.translate(-22,-18);
 if(cat==='acc')accBack(ctx,id,s,t,flap);
 birdBody(ctx,MANNEQUIN,t);birdFace(ctx,MANNEQUIN,t,flap);
 if(cat==='acc'){if(id==='angel'){ctx.fillStyle='#fff';const[w0,wy,w1]=s.wing;ctx.fill(poly([[w0,wy-8],[w1,wy],[w0,wy]]))}accFront(ctx,id,s,t,flap)}
 else if(id==='astro'){ctx.save();ctx.strokeStyle='#90CAF9';ctx.lineWidth=1.6;ctx.fillStyle='rgba(179,229,252,.35)';ctx.beginPath();ctx.arc(22,17,23,0,TAU);ctx.fill();ctx.stroke();ctx.fillStyle='rgba(255,255,255,.8)';ctx.beginPath();ctx.ellipse(12,6,5,2.4,-.6,0,TAU);ctx.fill();ctx.restore()}
 else hat(ctx,id,s,t);
 ctx.restore();
}
function drawNone(ctx,r){ctx.strokeStyle='#C8C8C8';ctx.lineWidth=r*.16;ctx.beginPath();ctx.arc(0,0,r,0,TAU);ctx.moveTo(-r*.7,r*.7);ctx.lineTo(r*.7,-r*.7);ctx.stroke()}

// ---------- hoops: vertical ring, ry = half opening height; draw back half then bird then front half ----------
function hoopHalf(ctx,id,x,y,ry,t,front,lw=7){
 const h=byId('hoop',id),rx=ry*.26;
 ctx.save();ctx.lineWidth=lw;ctx.lineCap='butt';
 const a0=front?Math.PI/2:-Math.PI/2,a1=front?Math.PI*1.5:Math.PI/2;
 const arc=()=>{ctx.beginPath();ctx.ellipse(x,y,rx,ry,0,a0,a1)};
 const base=front?h.f:h.b;
 switch(h.st){
 case'candy':ctx.strokeStyle=front?'#fff':'#eee';arc();ctx.stroke();ctx.strokeStyle=front?'#E53935':'#B71C1C';ctx.setLineDash([lw*.9,lw*.9]);ctx.lineDashOffset=-t*10;arc();ctx.stroke();break;
 case'checker':ctx.strokeStyle=front?'#fff':'#ccc';arc();ctx.stroke();ctx.strokeStyle='#212121';ctx.setLineDash([lw*.7,lw*.7]);ctx.lineWidth=lw/2;ctx.beginPath();ctx.ellipse(x,y,rx-lw/4,ry-lw/4,0,a0,a1);ctx.stroke();ctx.lineDashOffset=lw*.7;ctx.beginPath();ctx.ellipse(x,y,rx+lw/4,ry+lw/4,0,a0,a1);ctx.stroke();break;
 case'polka':ctx.strokeStyle=front?h.f:h.b;arc();ctx.stroke();ctx.fillStyle='rgba(255,255,255,.9)';for(let i=0;i<9;i++){const a=a0+(i+.5)/9*(a1-a0);circ(ctx,x+Math.cos(a)*rx,y+Math.sin(a)*ry,lw*.2,'rgba(255,255,255,.9)')}break;
 case'donut':ctx.strokeStyle=front?'#D9A066':'#A0703C';arc();ctx.stroke();ctx.strokeStyle=front?'#F48FB1':'#C2185B';ctx.lineWidth=lw*.62;arc();ctx.stroke();if(front){const C=['#fff','#FFEB3B','#29B6F6','#7CB342'];for(let i=0;i<10;i++){const a=a0+(i+.5)/10*(a1-a0);ctx.fillStyle=C[i%4];ctx.save();ctx.translate(x+Math.cos(a)*rx,y+Math.sin(a)*ry);ctx.rotate(i*1.3);ctx.fillRect(-lw*.22,-lw*.07,lw*.44,lw*.14);ctx.restore()}}break;
 case'wood':ctx.strokeStyle=base;arc();ctx.stroke();ctx.strokeStyle='rgba(60,30,5,.45)';ctx.lineWidth=lw*.14;ctx.setLineDash([lw*1.6,lw*.8,lw*.5,lw*.8]);ctx.beginPath();ctx.ellipse(x,y,rx-lw*.15,ry-lw*.15,0,a0,a1);ctx.stroke();break;
 case'neon':{const p=.6+.4*Math.sin(t*5);ctx.shadowColor='#00E5FF';ctx.shadowBlur=lw*(1+p*1.6);ctx.strokeStyle=front?'#84FFFF':'#00ACC1';arc();ctx.stroke();ctx.shadowBlur=0;ctx.lineWidth=lw*.3;ctx.strokeStyle='#fff';arc();ctx.stroke();break}
 case'lava':ctx.strokeStyle=front?'#E65100':'#8D1D00';arc();ctx.stroke();ctx.strokeStyle=front?'#FFD54F':'#FF6D00';ctx.lineWidth=lw*.4;ctx.setLineDash([lw*1.2,lw*1.4,lw*.4,lw]);ctx.lineDashOffset=-t*18;arc();ctx.stroke();break;
 case'ice':ctx.strokeStyle=base;arc();ctx.stroke();ctx.strokeStyle='rgba(255,255,255,.85)';ctx.lineWidth=lw*.25;ctx.beginPath();ctx.ellipse(x-lw*.15,y,rx-lw*.2,ry-lw*.2,0,a0,a1);ctx.stroke();if(front){const a=a0+((t*.5)%1)*(a1-a0);star(ctx,x+Math.cos(a)*rx,y+Math.sin(a)*ry,lw*.7,'#fff',t)}break;
 case'rainbow':{const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'];const n=12;for(let i=0;i<n;i++){ctx.strokeStyle=C[(i+Math.floor(t*6))%6];ctx.globalAlpha=front?1:.75;ctx.beginPath();ctx.ellipse(x,y,rx,ry,0,a0+i/n*(a1-a0),a0+(i+1.05)/n*(a1-a0));ctx.stroke()}break}
 case'galaxy':ctx.strokeStyle=base;arc();ctx.stroke();for(let i=0;i<8;i++){const a=a0+hash(i+(front?3:9))*(a1-a0),tw=Math.abs(Math.sin(t*2.5+i));circ(ctx,x+Math.cos(a)*rx+(hash(i)-.5)*lw*.5,y+Math.sin(a)*ry,lw*.12+tw*lw*.12,`rgba(255,255,255,${.3+.7*tw})`)}break;
 case'blackhole':{if(!front){ctx.save();ctx.beginPath();ctx.ellipse(x,y,rx,ry,0,0,TAU);ctx.fillStyle='#000';ctx.fill();ctx.clip();ctx.translate(x,y);ctx.scale(rx/ry,1);
   for(let arm=0;arm<3;arm++){ctx.beginPath();for(let i=0;i<=40;i++){const u=i/40,r=ry*(1-u)*.98,a=-t*2.2+arm*TAU/3+u*5.5;ctx.lineTo(Math.cos(a)*r,Math.sin(a)*r)}ctx.strokeStyle=arm===0?'rgba(255,255,255,.28)':'rgba(140,140,170,.3)';ctx.lineWidth=ry*.13;ctx.stroke()}
   for(let i=0;i<14;i++){const u=((t*.4+hash(i+31))%1),r=ry*(1-u),a=-t*2.2+hash(i+7)*TAU+u*5.5,tw=1-u;circ(ctx,Math.cos(a)*r,Math.sin(a)*r,ry*.035*(1+tw),`rgba(255,255,255,${.25+.75*tw})`)}
   const g=ctx.createRadialGradient(0,0,0,0,0,ry*.35);g.addColorStop(0,'#000');g.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,ry*.35,0,TAU);ctx.fill();ctx.restore()}
  ctx.lineWidth=lw;ctx.strokeStyle=front?'#000':'#0a0a0a';arc();ctx.stroke();ctx.lineWidth=lw*.22;for(let k=0;k<2;k++){ctx.strokeStyle=k?'rgba(255,255,255,.22)':'rgba(120,120,140,.5)';ctx.setLineDash([lw*1.4,lw*1.1]);ctx.lineDashOffset=-t*(k?26:16)-k*lw;ctx.beginPath();ctx.ellipse(x,y,rx+(k?lw*.22:-lw*.18),ry+(k?lw*.22:-lw*.18),0,a0,a1);ctx.stroke()}ctx.setLineDash([]);
  for(let i=0;i<9;i++){const ph=(t*.35+hash(i+(front?1:5)))%1,a=a0+ph*(a1-a0),tw=Math.abs(Math.sin(t*4+i*1.9)),off=(hash(i+20)-.5)*lw*1.6;if(i%3===0)star(ctx,x+Math.cos(a)*(rx+off*.3),y+Math.sin(a)*(ry+off),lw*(.25+.35*tw),'#fff',t+i);else circ(ctx,x+Math.cos(a)*(rx+off*.3),y+Math.sin(a)*(ry+off),lw*(.06+.08*tw),`rgba(255,255,255,${.4+.6*tw})`)}break}
 default:ctx.strokeStyle=base;arc();ctx.stroke();
 }
 ctx.restore();
}

// ---------- fire / trail particles (screen units; k = px per bird unit) ----------
function Trail(){return{parts:[],acc:0,hist:[]}}
const rand=(a,b)=>a+Math.random()*(b-a);
function trailEmit(st,id,x,y,dt,k,vx=-140){
 const f=byId('fire',id);st.acc+=dt;st.vx=vx*k/2;
 if(f.k==='ribbon'){st.hist.unshift({x,y});if(st.hist.length>120)st.hist.pop();for(const h of st.hist)h.x+=st.vx*dt;return}
 if(f.k==='echo'){st.hist.unshift({x,y,f:(st.acc*6.6)%1<.4});if(st.hist.length>84)st.hist.pop();for(const h of st.hist)h.x+=st.vx*dt;
  if(Math.random()<dt*14)st.parts.push({x:x+rand(-30,0)*k/2,y:y+rand(-12,12)*k/2,vx:rand(-30,0)*k/2,vy:0,life:0,max:.35,s:rand(2,4)*k/2,rot:0,vr:0,k:'sq',col:ECHO_C[Math.random()*4|0]});return}
 const rate=f.k==='laser'?.008:f.k==='flame'?.012:f.k==='comet'?.014:f.k==='bolt'?.05:f.k==='puff'?.03:.04;
 while(st.acc>rate){st.acc-=rate;
  const p={x:x+rand(-2,2)*k,y:y+rand(-4,4)*k,vx:rand(-20,10)*k/2,vy:rand(-12,12)*k/2,life:0,max:.5,s:rand(5,9)*k/2,rot:rand(0,TAU),vr:rand(-4,4),k:f.k};
  switch(f.k){case'flame':p.max=rand(.35,.55);p.vy-=14*k/2;p.cols=f.cols;break;
   case'star':p.max=.7;p.col=[GOLD,'#FF9100',PINK,'#fff'][Math.random()*4|0];p.s*=.9;break;
   case'bubble':p.max=.9;p.vy=-rand(8,24)*k/2;p.s=rand(3,7)*k/2;break;
   case'heart':p.max=.9;p.vy=-rand(10,24)*k/2;p.col=Math.random()<.5?'#FF1F64':PINK;break;
   case'puff':p.max=.9;p.s=rand(4,7)*k/2;p.vy=-6*k/2;break;
   case'laser':if(Math.random()<.12){p.k='lspark';p.max=.3;p.vy=rand(-40,40)*k/2;p.vx=rand(-10,30)*k/2;p.s=rand(1.5,3)*k/2}else{p.max=.6;p.y=y;p.vx=0;p.vy=0;p.ph=performance.now()/90}break;
   case'conf':p.max=.9;p.col=['#FF3B30','#FFCC00','#34C759','#00A2FF',PINK][Math.random()*5|0];p.vy=rand(-10,24)*k/2;break;
   case'bolt':p.max=.22;p.pts=[...Array(6)].map((_,i)=>[-i*7*k/2,rand(-7,7)*k/2]);break;
   case'sq':p.max=.45;p.col=Math.random()<.5?GOLD:PINK;break;
   case'note':p.max=1;p.vy=-rand(12,22)*k/2;p.col=['#9B30D9',PINK,'#1E9BE0'][Math.random()*3|0];p.g=Math.random()<.5?'♪':'♫';break;
   case'comet':p.max=rand(.3,.7);p.col=[GOLD,'#FF9100','#fff','#FFE082'][Math.random()*4|0];p.s=rand(2,5)*k/2;break}
  st.parts.push(p)}
}
const ECHO_C=['#00E5FF','#FF2BD6','#FFE600','#7C4DFF'];const ECHO=document.createElement('canvas'),EC=ECHO.getContext('2d');
function echoDraw(ctx,look,x,y,k,col,a,t,glitch,flap){const W=Math.ceil(90*k),S=2;if(ECHO.width!==W*S){ECHO.width=ECHO.height=W*S}
 EC.setTransform(1,0,0,1,0,0);EC.globalCompositeOperation='source-over';EC.globalAlpha=1;EC.clearRect(0,0,W*S,W*S);EC.setTransform(k*S,0,0,k*S,W*S/2,W*S/2);drawLook(EC,look,t,flap);
 EC.setTransform(1,0,0,1,0,0);EC.globalCompositeOperation='source-atop';EC.globalAlpha=.8;EC.fillStyle=col;EC.fillRect(0,0,W*S,W*S);
 EC.globalAlpha=.35;EC.fillStyle='#fff';for(let yy=0;yy<W*S;yy+=6*S)EC.fillRect(0,yy,W*S,1.5*S);
 ctx.save();ctx.globalAlpha=a;if(glitch){const n=5,sh=W/n;for(let i=0;i<n;i++)ctx.drawImage(ECHO,0,i*sh*S,W*S,sh*S,x-W/2+(Math.random()-.5)*10*k,y-W/2+i*sh,W,sh)}else ctx.drawImage(ECHO,x-W/2,y-W/2,W,W);ctx.restore()}
function trailStep(st,dt){for(const p of st.parts){p.life+=dt;p.x+=(st.vx+p.vx)*dt;p.y+=p.vy*dt;p.rot+=p.vr*dt}st.parts=st.parts.filter(p=>p.life<p.max)}
function lerpC(a,b,u){const pa=parseInt(a.slice(1),16),pb=parseInt(b.slice(1),16);const r=(pa>>16)+(((pb>>16)-(pa>>16))*u),g=((pa>>8)&255)+((((pb>>8)&255)-((pa>>8)&255))*u),bl=(pa&255)+(((pb&255)-(pa&255))*u);return`rgb(${r|0},${g|0},${bl|0})`}
function trailDraw(ctx,st,id,k,head){
 const f=byId('fire',id);
 if(f.k==='ribbon'){const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'],w=2.6*k;const H=st.hist;if(H.length<2)return;
  for(let c=0;c<6;c++){ctx.strokeStyle=C[c];ctx.lineWidth=w+.5;ctx.lineCap='round';ctx.beginPath();H.forEach((h,i)=>{const yy=h.y+(c-2.5)*w;i?ctx.lineTo(h.x,yy):ctx.moveTo(h.x,yy)});ctx.globalAlpha=.95;ctx.stroke()}
  ctx.globalAlpha=1;const e=H[H.length-1];star(ctx,e.x,e.y,3*k,'#fff',performance.now()/300);return}
 if(f.k==='echo'){const H=st.hist,look=st.look||{bird:'classic'},T=performance.now()/1000;
  for(let n=4;n>=1;n--){const h=H[n*20];if(!h)continue;const g=Math.random()<.07;echoDraw(ctx,look,h.x+17*k,h.y,k,ECHO_C[(n+Math.floor(T*3))%4],.78-n*.13,T,g,h.f)}}
 if(f.k==='comet'&&head){const g=ctx.createRadialGradient(head.x,head.y,0,head.x,head.y,22*k);g.addColorStop(0,'rgba(255,240,200,.95)');g.addColorStop(.35,'rgba(255,181,41,.45)');g.addColorStop(1,'rgba(255,214,120,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(head.x,head.y,22*k,0,TAU);ctx.fill()}
 for(const p of st.parts){const u=p.life/p.max;ctx.save();ctx.translate(p.x,p.y);
  switch(p.k){
  case'flame':{const c=u<.25?lerpC(p.cols[0],p.cols[1],u/.25):u<.6?lerpC(p.cols[1],p.cols[2],(u-.25)/.35):lerpC(p.cols[2],p.cols[3],(u-.6)/.4);ctx.globalAlpha=1-u*u;circ(ctx,0,0,p.s*(1.1-u*.6),c);break}
  case'star':ctx.globalAlpha=1-u;star(ctx,0,0,p.s*(1-u*.4)*.8,p.col,p.rot);break;
  case'bubble':ctx.globalAlpha=1-u*.6;ctx.strokeStyle='#4FC3F7';ctx.lineWidth=1.2;ctx.beginPath();ctx.arc(0,0,p.s,0,TAU);ctx.stroke();circ(ctx,-p.s*.35,-p.s*.35,p.s*.25,'rgba(255,255,255,.9)');break;
  case'heart':ctx.globalAlpha=1-u;ctx.rotate(Math.sin(p.rot)*.3);heart(ctx,0,0,p.s*1.6,p.col);break;
  case'puff':ctx.globalAlpha=.55*(1-u);circ(ctx,0,0,p.s*(1+u*1.6),'#9E9E9E');break;
  case'laser':{const hw=(1.7+.5*Math.sin(p.ph))*k*(1-u*.5);ctx.globalAlpha=1-u*u;ctx.fillStyle='rgba(255,23,68,.35)';ctx.fillRect(-1,-hw*2.2,8*k/2+2,hw*4.4);ctx.fillStyle='#FF1744';ctx.fillRect(-1,-hw,8*k/2+2,hw*2);ctx.fillStyle='#fff';ctx.fillRect(-1,-hw*.35,8*k/2+2,hw*.7);break}
  case'lspark':ctx.globalAlpha=1-u;ctx.fillStyle=Math.random()<.5?'#FF1744':'#fff';ctx.fillRect(-p.s/2,-p.s/2,p.s,p.s);break;
  case'conf':ctx.globalAlpha=1-u*u;ctx.rotate(p.rot);ctx.fillStyle=p.col;ctx.fillRect(-p.s*.4,-p.s*.2,p.s*.8,p.s*.4);break;
  case'bolt':ctx.globalAlpha=1-u;ctx.strokeStyle='#00B0FF';ctx.shadowColor='#40C4FF';ctx.shadowBlur=8;ctx.lineWidth=2.6;ctx.beginPath();p.pts.forEach(([a,b],i)=>i?ctx.lineTo(a,b):ctx.moveTo(a,b));ctx.stroke();ctx.lineWidth=.9;ctx.strokeStyle='#fff';ctx.stroke();break;
  case'sq':ctx.globalAlpha=1-u;ctx.rotate(p.rot*.2);ctx.fillStyle=p.col;const z=p.s*(1-u*.5);ctx.fillRect(-z/2,-z/2,z,z);break;
  case'note':{ctx.globalAlpha=1-u;ctx.rotate(Math.sin(p.rot)*.25);const z=p.s/5;ctx.fillStyle=ctx.strokeStyle=p.col;ctx.beginPath();ctx.ellipse(-2*z,4*z,2.4*z,1.8*z,-.4,0,TAU);ctx.fill();ctx.fillRect(.1*z,-5*z,1.1*z,9*z);if(p.g==='♫'){ctx.beginPath();ctx.ellipse(5*z,3*z,2.4*z,1.8*z,-.4,0,TAU);ctx.fill();ctx.fillRect(7.1*z,-6*z,1.1*z,9*z);ctx.fillRect(.1*z,-6*z,8*z,1.6*z)}else ctx.fill(poly([[1.2*z,-5*z],[4.5*z,-2*z],[1.2*z,-2.6*z]]));break}
  case'comet':ctx.globalAlpha=1-u;star(ctx,0,0,p.s,p.col,p.rot);break}
  ctx.restore()}
}
const SKIN={RAR,CATS,CAT_NAMES,TOTAL,byId,drawLook,drawOnMannequin,drawNone,hoopHalf,Trail,trailEmit,trailStep,trailDraw,star,heart,circ,poly,PINK,SOFT,GOLD,PLUM,TAU};

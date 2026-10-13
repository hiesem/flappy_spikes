// emblem_art.js: the 10 level emblems (+ unranked frame) drawn in canvas, Flappy Spikes style:
// flat colours, hard edges, octagon / shield geometry like the birds, spike triangles from the strips.
// Units: plate centre at 0,0; the plate is ~92 wide (the bird at 2x sits on it); wings reach ±108,
// crown up to about -100, ribbon down to about +72. Needs skin_art.js (oct, poly, fillP, circ, star, hash, TAU).
const LEVELS=[
 {n:'EGG',s:10,r:50,plate:'#F6EBD2',rim:'#D9C39A',acc:'#B89A66'},
 {n:'CHICK',s:50,r:100,plate:'#FFE58A',rim:'#FFB300',acc:'#E07B00'},
 {n:'FLEDGLING',s:100,r:150,plate:'#B9F3E1',rim:'#13B48D',acc:'#00796B'},
 {n:'FLAPPER',s:200,r:250,plate:'#C8ECFD',rim:'#1E9BE0',acc:'#01579B'},
 {n:'GLIDER',s:400,r:400,plate:'#EBD3F5',rim:'#9B30D9',acc:'#5E1A8C'},
 {n:'FALCON',s:600,r:600,plate:'#FCD9EE',rim:'#EC008C',acc:'#7A0044'},
 {n:'HAWK',s:800,r:800,plate:'#FFD6D6',rim:'#D32F2F',acc:'#7F1028'},
 {n:'SPIKE ACE',s:1000,r:1000,plate:'#FFF1C9',rim:'#FFB529',acc:'#B07800'},
 {n:'PHOENIX',s:2000,r:2000,plate:'#FFD3A8',rim:'#FF5722',acc:'#B23000'},
 {n:'LEGEND',s:5000,r:5000,plate:'#2A1260',rim:'#FFB529',acc:'#7C4DFF'},
];
const STEEL='#6E7B83',STEEL_D='#4D575D';
function levelFor(best){let l=0;for(let i=0;i<LEVELS.length;i++)if(best>=LEVELS[i].s)l=i+1;return l}

// ---- plate shapes ----
function platePath(L,k=1){
 if(L===1){return oct(-38*k,-50*k,76*k,98*k,24*k)}                       // egg
 if(L>=4&&L<=7){return poly([[-46*k,-38*k],[-38*k,-46*k],[38*k,-46*k],[46*k,-38*k],[46*k,12*k],[0,54*k],[-46*k,12*k]])} // shield
 return oct(-48*k,-48*k,96*k,96*k,26*k)                                  // octagon
}
function bladePts(len,w,tipWob=0){return[[0,-w/2],[len*.72,-w/2],[len+tipWob,0],[len*.72,w/2],[0,w/2]]}
function rot(pts,a,s,ox,oy){const c=Math.cos(a),sn=Math.sin(a);return pts.map(([x,y])=>[ox+s*(x*c-y*sn),oy+(x*sn+y*c)])}

function wings(ctx,L,t,lv){
 const N={3:2,4:3,5:4,6:4,7:5,8:5,9:5,10:6}[L];if(!N)return;
 const S={3:.72,4:.86,5:1,6:1.04,7:1.1,8:1.12,9:1.18,10:1.26}[L];
 for(const s of[-1,1])for(let i=N-1;i>=0;i--){
  const a=-.95+i*(1.05/(N-1||1)),len=(64-i*7)*S,w=(14-i*.8)*S,ox=s*32,oy=-14+i*9*S;
  let c=i%2?lv.acc:lv.rim;
  if(L===10)c=i%2?'#FFE082':'#fff';
  if(L===9){const f=Math.sin(t*9+i*1.7+(s>0?1:0))*3.2;fillP(ctx,i%2?'#FF7A1A':'#FFB529',poly(rot(bladePts(len+4,w+2,f),a,s,ox,oy)));fillP(ctx,'#FFE082',poly(rot(bladePts(len*.62,w*.45,f*.5),a,s,ox+s*6,oy)));continue}
  fillP(ctx,c,poly(rot(bladePts(len,w),a,s,ox,oy)));
  if(L>=7)fillP(ctx,'rgba(255,255,255,.28)',poly(rot([[len*.18,-w/2],[len*.72,-w/2],[len*.86,-w*.18],[len*.18,-w*.18]],a,s,ox,oy)));
 }
}
function spikeRing(ctx,n,r,len,col,colD,t=0,spin=0){
 for(let i=0;i<n;i++){const a=i/n*TAU+spin*t-Math.PI/2,w=TAU/n*.32,c=Math.cos(a),s=Math.sin(a);
  const p=[[Math.cos(a-w)*r,Math.sin(a-w)*r],[c*(r+len),s*(r+len)],[Math.cos(a+w)*r,Math.sin(a+w)*r]];
  fillP(ctx,col,poly(p));fillP(ctx,colD,poly([p[0],p[1],[c*r,s*r]]))}
}
function topSpikes(ctx,n,len,col,colD){ // grey strip spikes standing on the plate top
 const span=n*14;for(let i=0;i<n;i++){const x=-span/2+7+i*14,h=len*(i===(n-1)/2?1.25:1);fillP(ctx,col,poly([[x-7,-40],[x,-40-h],[x+7,-40]]));fillP(ctx,colD,poly([[x,-40-h],[x+7,-40],[x,-40]]))}
}
function flags(ctx,t,lv,L){
 for(const s of[-1,1]){ctx.save();ctx.translate(s*52,-50);ctx.rotate(s*.42);
  ctx.fillStyle=STEEL_D;ctx.fillRect(-1.5,-34,3,40);circ(ctx,0,-35,2.6,'#FFB529');
  const wv=i=>Math.sin(t*5-i*1.3+(s>0?1.5:0))*2.4,cs=L===10?['#FF3B30','#FFCC00','#34C759','#00A2FF']:[lv.rim,lv.acc];
  ctx.scale(s,1);const P=[[1.5,-32],[24,-28+wv(2)],[1.5,-20]];fillP(ctx,cs[0],poly(P));fillP(ctx,cs[1%cs.length],poly([[1.5,-26],[16,-25+wv(1)],[1.5,-20]]));
  if(L===10)star(ctx,10,-27+wv(1),2.6,'#fff',t*2);
  ctx.restore()}
}
function laurel(ctx,L){ // two gold branches hugging the plate's lower half
 const n=L>=8?6:5,c1=L===10?'#FFE082':'#FFB529',c2=L===10?'#FFB529':'#C98A00';
 for(const s of[-1,1]){ctx.strokeStyle=c2;ctx.lineWidth=2;ctx.beginPath();ctx.arc(0,4,56,s<0?Math.PI*.58:Math.PI*.42,s<0?Math.PI*.98:Math.PI*.02,s>0);ctx.stroke();
  for(let i=0;i<n;i++){const u=i/(n-1),a=s<0?Math.PI*(.6+u*.36):Math.PI*(.4-u*.36),x=Math.cos(a)*56,y=Math.sin(a)*56+4;
   ctx.save();ctx.translate(x,y);ctx.rotate(a+(s<0?-.5:.5)+Math.PI/2*(s<0?1:-1)*0);ctx.rotate(s<0?.9:-.9);fillP(ctx,i%2?c2:c1,poly([[0,-8],[3.6,0],[0,4],[-3.6,0]]));ctx.restore()}}
}
function crown(ctx,L,t){
 if(L===9){for(let i=0;i<3;i++){const f=Math.sin(t*10+i*2)*2.5,x=-14+i*14,h=i===1?30:22;fillP(ctx,['#FF7A1A','#FFB529','#FF7A1A'][i],poly([[x-8,-44],[x+f,-44-h],[x+8,-44]]));fillP(ctx,'#FFE082',poly([[x-4,-44],[x+f*.6,-44-h*.55],[x+4,-44]]))}return}
 const big=L===10,w=big?30:24,h=big?26:20,y=-44;
 const P=[[-w,y],[-w,y-h*.75],[-w*.5,y-h*.35],[0,y-h],[w*.5,y-h*.35],[w,y-h*.75],[w,y]];
 fillP(ctx,'#FFB529',poly(P));fillP(ctx,'#E69500',poly([[-w,y],[-w,y-5],[w,y-5],[w,y]]));
 fillP(ctx,'rgba(255,255,255,.35)',poly([[-w,y-h*.75],[-w*.5,y-h*.35],[-w*.5,y-h*.2],[-w,y-h*.55]]));
 const gem=big?'#7C4DFF':'#E53935';fillP(ctx,gem,oct(-5,y-h*.62,10,10,3));circ(ctx,-w*.62,y-2.5,2.2,'#1E88E5');circ(ctx,w*.62,y-2.5,2.2,'#43A047');
 if(big){fillP(ctx,'#7C4DFF',poly([[0,y-h-14],[6,y-h-5],[0,y-h+2],[-6,y-h-5]]));fillP(ctx,'#B39DFF',poly([[0,y-h-14],[6,y-h-5],[0,y-h-5]]));const sp=(t*.7)%2;if(sp<1)star(ctx,-w+sp*2*w,y-h*.8,3.4,'#fff',t*3)}
}
function ribbon(ctx,L,lv){
 const c=L===0?'#BDBDBD':lv.acc,y=L===1?46:L>=4&&L<=7?50:44;
 fillP(ctx,c,poly([[-30,y+2],[-22,y+2],[-22,y+16],[-30,y+16],[-25,y+9]]));fillP(ctx,c,poly([[30,y+2],[22,y+2],[22,y+16],[30,y+16],[25,y+9]]));
 fillP(ctx,'rgba(0,0,0,.25)',poly([[-22,y+2],[-18,y+2],[-22,y+6]]));fillP(ctx,'rgba(0,0,0,.25)',poly([[22,y+2],[18,y+2],[22,y+6]]));
 fillP(ctx,L===0?'#CFCFCF':lv.rim,poly([[-20,y-2],[20,y-2],[20,y+12],[-20,y+12]]));
 ctx.fillStyle=L===0?'#fff':(L===8||L===1||L===2?lv.acc:'#fff');ctx.font='13px Opificio, sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(L===0?'?':String(L),0,y+5.5);
}

// draw the emblem for level L (0 = unranked frame). o: {shine:true, pop:0..1}
function drawEmblem(ctx,L,t=0,o={}){
 const lv=LEVELS[Math.max(0,L-1)];
 if(L===0){const p=oct(-48,-48,96,96,26);ctx.save();ctx.setLineDash([7,5]);ctx.lineWidth=4;ctx.strokeStyle='#CFCFCF';ctx.stroke(p);ctx.restore();ctx.fillStyle='rgba(130,130,130,.07)';ctx.fill(p);ribbon(ctx,0,lv);return}
 // back layer
 if(L>=9){ctx.save();ctx.rotate(t*.35);ctx.globalAlpha=L===10?.32:.24;for(let i=0;i<14;i++){ctx.fillStyle=i%2?'#FFE082':'#FFB529';ctx.beginPath();ctx.moveTo(0,0);ctx.arc(0,0,98,i*TAU/14,(i+.5)*TAU/14);ctx.fill()}ctx.restore()}
 if(L===10){const C=['#FF3B30','#FF9500','#FFCC00','#34C759','#00A2FF','#AF52DE'];for(let i=0;i<6;i++){ctx.strokeStyle=C[(i+Math.floor(t*3))%6];ctx.lineWidth=3;ctx.beginPath();ctx.arc(0,0,68-i*3,0,TAU);ctx.stroke()}}
 if(L>=7)flags(ctx,t,lv,L);
 wings(ctx,L,t,lv);
 if(L>=8)spikeRing(ctx,L===10?16:12,50,15,L===8?STEEL:'#FFB529',L===8?STEEL_D:'#C98A00',t,L===10?.15:0);
 if(L===6||L===7)topSpikes(ctx,L===6?3:5,15,STEEL,STEEL_D);
 // plate
 const outer=platePath(L,1),inner=platePath(L,.84);
 fillP(ctx,lv.rim,outer);
 let pf=lv.plate;
 if(L===9){const g=ctx.createLinearGradient(0,46,0,-46);g.addColorStop(0,'#FFAB76');g.addColorStop(1,'#FFE3B8');pf=g}
 if(L===10){const g=ctx.createRadialGradient(-8,-10,4,0,0,52);g.addColorStop(0,'#5B2DC8');g.addColorStop(.6,'#2A1260');g.addColorStop(1,'#120634');pf=g}
 fillP(ctx,pf,inner);
 ctx.save();ctx.clip(inner);
 if(L===1){ctx.fillStyle=lv.rim;for(let i=0;i<9;i++)ctx.fillRect(-28+hash(i)*56,-38+hash(i+20)*76,3,3);
  ctx.strokeStyle=lv.acc;ctx.lineWidth=2.4;ctx.beginPath();ctx.moveTo(-40,-14);for(let i=0;i<=8;i++)ctx.lineTo(-40+i*10,i%2?-22:-12);ctx.stroke()}
 if(L===10)for(let i=0;i<16;i++){const tw=.35+.65*Math.abs(Math.sin(t*2+i*1.7));circ(ctx,-40+hash(i)*80,-40+hash(i+40)*80,.6+hash(i+9)*1.5*tw,`rgba(255,255,255,${tw})`)}
 if(o.shine!==false){const u=((t%6.4)/6.4)/.28;if(u<1){const x=-110+u*220;ctx.fillStyle='rgba(255,255,255,.38)';ctx.fill(poly([[x,-60],[x+22,-60],[x-8,60],[x-30,60]]))}}
 ctx.restore();
 if(L>=4&&L<=7){ctx.strokeStyle='rgba(255,255,255,.35)';ctx.lineWidth=1.4;ctx.stroke(platePath(L,.74))}
 // front layer
 if(L===2)for(let i=0;i<3;i++){const x=-8+i*8;fillP(ctx,i===1?lv.acc:lv.rim,poly([[x-4,-46],[x+(i-1)*3,-58-(i===1?4:0)],[x+4,-46]]))}
 if(L>=5)laurel(ctx,L);
 if(L>=8)crown(ctx,L,t);
 ribbon(ctx,L,lv);
}

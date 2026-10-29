// Legacy 8-frame candidate inspector. Current 16-frame native sheets use preview_native_walk.cjs.
// NODE_PATH=<bundled node_modules> node tools/review_walk.cjs <4x2-walk.png | 8x8-atlas.png> <out>
const fs=require('fs'), path=require('path'), sharp=require('sharp');
async function eye(png) {
  const {data:d,info:m}=await sharp(png).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const seen=new Uint8Array(m.width*m.height), candidates=[];
  const solid=p=>d[p*4+3]>200&&Math.max(d[p*4],d[p*4+1],d[p*4+2])<55;
  for(let y=80;y<Math.min(m.height,320);y++)for(let x=Math.floor(m.width*.65);x<m.width;x++){
    let p=y*m.width+x;if(seen[p]||!solid(p))continue;
    let q=[p];seen[p]=1;
    for(let j=0;j<q.length;j++){let xx=q[j]%m.width,yy=Math.floor(q[j]/m.width);
      for(let[nx,ny]of[[xx-1,yy],[xx+1,yy],[xx,yy-1],[xx,yy+1]])if(nx>=0&&ny>=0&&nx<m.width&&ny<m.height){let n=ny*m.width+nx;if(!seen[n]&&solid(n)){seen[n]=1;q.push(n);}}
    }
    const xs=q.map(n=>n%m.width),ys=q.map(n=>Math.floor(n/m.width));
    const width=Math.max(...xs)-Math.min(...xs)+1,height=Math.max(...ys)-Math.min(...ys)+1;
    if(q.length>100&&width>=8&&width<=28&&height>=10&&height<=34&&q.length/(width*height)>.5)
      candidates.push({x:xs.reduce((a,b)=>a+b)/q.length,y:ys.reduce((a,b)=>a+b)/q.length,height,area:q.length});
  }
  if(!candidates.length)throw Error('No isolated side-profile eye; annotate this candidate manually');
  return candidates.sort((a,b)=>b.area-a.area)[0];
}
async function main(){
  const [src,out]=process.argv.slice(2);fs.mkdirSync(out,{recursive:true});
  const sidecar=src.replace(/\.png$/,'.json');
  if(fs.existsSync(sidecar)){const layout=JSON.parse(fs.readFileSync(sidecar));if((layout.animations?.walk||layout.walkFrames||[]).length===16)throw Error('Use tools/preview_native_walk.cjs <built artwork folder> <out> for 16-frame native sheets');}
  const m=await sharp(src).metadata(),atlas=m.width===3072&&m.height===2048;
  const cw=atlas?384:m.width/4,ch=atlas?256:m.height/2;
  if(!Number.isInteger(cw)||!Number.isInteger(ch))throw Error('Uneven cells');
  const cuts=[],eyes=[];
  for(let i=0;i<8;i++){
    const n=atlas?i+4:i,cols=atlas?8:4;
    const png=await sharp(src).extract({left:n%cols*cw,top:Math.floor(n/cols)*ch,width:cw,height:ch}).png().toBuffer();
    cuts.push(png);eyes.push(atlas?{x:300,y:135,height:13}:await eye(png));
  }
  const heights=eyes.map(e=>e.height).sort((a,b)=>a-b),scale=13/((heights[3]+heights[4])/2),images=[],info=[];
  for(let i=0;i<8;i++){
    const scaled=await sharp(cuts[i]).resize(Math.round(cw*scale),Math.round(ch*scale)).png().toBuffer();
    const left=Math.round(300-eyes[i].x*scale),top=Math.round(135-eyes[i].y*scale);
    const cutLeft=Math.max(0,-left),cutTop=Math.max(0,-top);
    const cropped=await sharp(scaled).extract({left:cutLeft,top:cutTop,width:Math.min(Math.round(cw*scale)-cutLeft,384-Math.max(0,left)),height:Math.min(Math.round(ch*scale)-cutTop,256-Math.max(0,top))}).png().toBuffer();
    const png=await sharp({create:{width:384,height:256,channels:4,background:'#0000'}}).composite([{input:cropped,left:Math.max(0,left),top:Math.max(0,top)}]).png().toBuffer();
    const raw=await sharp(png).ensureAlpha().raw().toBuffer();let bottom=0;
    for(let y=0;y<256;y++)for(let x=0;x<384;x++)if(raw[(y*384+x)*4+3]>100)bottom=Math.max(bottom,y);
    images.push('data:image/png;base64,'+png.toString('base64'));info.push({frame:i+1,eye:eyes[i],globalScale:scale,groundFix:bottom-232});
  }
  fs.writeFileSync(path.join(out,'registration-review.json'),JSON.stringify({source:src,frames:info},null,2));
  const label=atlas?'CURRENT APP ART — slow timing review':'GENERATED DRAFT — not installed / not approved';
  const html=`<!doctype html><meta charset="utf-8"><title>Slow walk · four paws</title><style>body{font:16px system-ui;background:#20242a;color:#eee;margin:20px}button{padding:8px;margin:4px}canvas{display:block;background:#30363d;margin:10px 0}#banner{color:#ffd38b}small{color:#ccc}</style><h1>Slow walk · four separate paws</h1><p id="banner">${label}</p><p>1.6 s per cycle · 0.2 s per frame · LH → LF → RH → RF. Diagram timings are targets; inspect actual art.</p><button id="play">Pause</button><button id="prev">Previous frame</button><button id="next">Next frame</button><span id="phase"></span><h2>Whole character / all four limbs</h2><canvas id="whole" width="768" height="512"></canvas><h2>Front legs · near and far</h2><canvas id="fore" width="600" height="350"></canvas><h2>Hind legs · near and far</h2><canvas id="hind" width="600" height="350"></canvas><h2>Native 1x, moving at 6 pt/s</h2><small>At rest on the ground, a paw should stay on the same floor mark; source ground correction is applied.</small><canvas id="world" width="480" height="70"></canvas><script>const urls=${JSON.stringify(images)},reg=${JSON.stringify(info)};const images=urls.map(s=>{let i=new Image;i.src=s;return i});let frame=0,paused=false,last=0,elapsed=0;const C=id=>document.getElementById(id).getContext('2d');function draw(){document.getElementById('phase').textContent='frame '+(frame+1)+'/8 · '+(['contact','LH lifts','contact','LF lifts','contact','RH lifts','contact','RF lifts'][frame]);for(let id of['whole','fore','hind','world']){let c=C(id);c.clearRect(0,0,c.canvas.width,c.canvas.height);c.imageSmoothingEnabled=true;if(id==='whole'){c.drawImage(images[frame],0,0,768,512);c.strokeStyle='#888';c.beginPath();c.moveTo(0,464);c.lineTo(768,464);c.stroke()}else if(id==='fore'||id==='hind'){let x=id==='fore'?215:125;c.drawImage(images[frame],x,170,120,70,0,0,600,350)}else{c.strokeStyle='#69717b';for(let x=0;x<480;x+=8){c.beginPath();c.moveTo(x,42);c.lineTo(x,48);c.stroke()}let x=50+(elapsed*6)%350;c.drawImage(images[frame],Math.round(x+9-300*24/180),Math.round(42-232*24/180-reg[frame].groundFix*24/180),51,34)}}}document.getElementById('play').onclick=()=>{paused=!paused;document.getElementById('play').textContent=paused?'Play':'Pause'};document.getElementById('next').onclick=()=>{paused=true;document.getElementById('play').textContent='Play';frame=(frame+1)%8;elapsed+=.2;draw()};document.getElementById('prev').onclick=()=>{paused=true;document.getElementById('play').textContent='Play';frame=(frame+7)%8;elapsed=Math.max(0,elapsed-.2);draw()};function tick(t){if(!paused&&t-last>=200){frame=(frame+1)%8;elapsed+=.2;last=t;draw()}if(paused)last=t;requestAnimationFrame(tick)}Promise.all(images.map(i=>i.decode())).then(()=>{draw();requestAnimationFrame(tick)});</script>`;
  fs.writeFileSync(path.join(out,'review.html'),html);console.log(JSON.stringify({output:out,frames:info}));
}
main().catch(e=>{console.error(e);process.exit(1)});

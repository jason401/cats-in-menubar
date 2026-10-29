// Diagnostic views only; never modifies the production artwork.
// NODE_PATH=<bundled node_modules> node tools/audit_sprite_sheet.cjs <atlas.png> <output-dir>
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
async function main() {
  const [source, out] = process.argv.slice(2);
  fs.mkdirSync(out, {recursive: true});
  const meta = await sharp(source).metadata();
  const sidecar=source.replace(/\.png$/,'.json');
  const layout=fs.existsSync(sidecar)?JSON.parse(fs.readFileSync(sidecar)):{};
  const cols=layout.columns||8, rows=layout.rows||(meta.width===3072&&meta.height===2048?8:16);
  const cw=layout.cellWidth||meta.width/cols,ch=layout.cellHeight||meta.height/rows;
  const count=layout.frameCount||layout.frames?.length||62,capacity=cols*rows,ppp=layout.pixelsPerPoint||7.5;
  if (!meta.hasAlpha || !Number.isInteger(cw) || !Number.isInteger(ch)) throw Error('Expected an alpha atlas with equal cells');
  const cells = [], masks = [], metrics = [];
  for (let i = 0; i < capacity; i++) {
    const png = await sharp(source).extract({left: i%cols*cw, top: Math.floor(i/cols)*ch, width:cw, height:ch}).png().toBuffer();
    cells.push(png);
    const raw = await sharp(png).ensureAlpha().raw().toBuffer();
    const mask = new Uint8Array(cw*ch);
    let left=cw, right=-1, top=ch, bottom=-1, area=0;
    const groundContacts=[];
    for(let y=0;y<ch;y++) for(let x=0;x<cw;x++) if(raw[(y*cw+x)*4+3]>100) {
      mask[y*cw+x]=1;area++;left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);
    }
    if(bottom>=0) for(let x=0;x<cw;x++) if(mask[bottom*cw+x]) groundContacts.push(x);
    masks.push(mask);
    metrics.push({frame:i,left,right,top,bottom,area,groundContacts});
  }
  const difference=(a,b)=>{let union=0,changed=0;for(let p=0;p<masks[a].length;p++){union+=masks[a][p]|masks[b][p];changed+=masks[a][p]^masks[b][p];}return union?Number((100*changed/union).toFixed(2)):0;};
  const sequences={
    walk:[...(layout.animations?.walk||layout.walkFrames||[4,5,6,7,8,9,10,11]),(layout.animations?.walk||layout.walkFrames||[4])[0]],
    run:[12,13,14,15,16,17,18,19,12],
    'rest-ladder':[0,24,25,26,27,28,29,30,31,32,33,34,33,32,31,30,29,28,27,26,25,24,0],
    groom:[26,35,36,37,38,26],
    stretch:[0,39,40,41,42,43,0],
    yawn:[26,44,45,26],
    hunt:[0,46,48,49,50,51,48,46,52,53,52,54,55,56,57,0,24,25,26],
    bat:[46,58,59,46],
    held:[60,61,60],
    turn:[0,20,21,22,23],
  };
  const report={source,dimensions:[meta.width,meta.height],frames:metrics,sequences:{}};
  for(const [name,ids] of Object.entries(sequences)) {
    report.sequences[name]=ids.slice(1).map((b,j)=>({from:ids[j],to:b,silhouetteChangePercent:difference(ids[j],b)}));
    const columns=Math.min(ids.length,8), rows=Math.ceil(ids.length/columns);
    const composites=[];
    for(let j=0;j<ids.length;j++) {
      const x=j%columns*cw,y=Math.floor(j/columns)*(ch+24);
      composites.push({input:cells[ids[j]],left:x,top:y});
      composites.push({input:Buffer.from(`<svg width="${cw}" height="24"><text x="12" y="17" fill="white" font-size="15">${ids[j]}</text><path d="M0 0 H${cw}" stroke="#62666b"/></svg>`),left:x,top:y+ch});
    }
    await sharp({create:{width:columns*cw,height:rows*(ch+24),channels:4,background:'#24282e'}}).composite(composites).png().toFile(path.join(out,name+'-strip.png'));
  }
  fs.writeFileSync(path.join(out,'measurements.json'),JSON.stringify(report,null,2));
  const embedded=cells.slice(0,count).map(b=>'data:image/png;base64,'+b.toString('base64'));
  const playback=Object.fromEntries(Object.entries(sequences).map(([name,ids])=>[name,ids.length>1&&ids[0]===ids[ids.length-1]?ids.slice(0,-1):ids]));
  const html=`<!doctype html><meta charset="utf-8"><title>Cat animation audit</title><style>body{background:#20242a;color:#eee;font:16px system-ui;margin:24px}section{display:inline-block;vertical-align:top;width:480px;margin:10px;padding:14px;border:1px solid #555}canvas{display:block;background:#30363d}button,input{margin:6px}small{color:#ccc}</style><h1>Animation audit · source pixels and native 1x</h1><p>Space: pause. Left/right: step every sequence. No crossfade hides the source drawings.</p><button id="play">Pause</button><input id="speed" type="range" min="1" max="16" value="10"><span id="fps">10 fps</span><main></main><script>const sources=${JSON.stringify(embedded)},seqs=${JSON.stringify(playback)};const images=sources.map(s=>{let i=new Image;i.src=s;return i});let paused=false,step=0,last=0;const views=Object.entries(seqs).map(([name,ids])=>{let s=document.createElement('section');s.innerHTML='<h2>'+name+'</h2><small></small><canvas width="${cw}" height="256"></canvas><canvas width="${cw}" height="50"></canvas>';document.querySelector('main').append(s);return{s,ids,can:s.querySelectorAll('canvas')}});function draw(){for(let v of views){let id=v.ids[step%v.ids.length];v.s.querySelector('small').textContent='frame '+id+' · '+(step%v.ids.length+1)+'/'+v.ids.length;for(let k=0;k<2;k++){let c=v.can[k],x=c.getContext('2d');x.clearRect(0,0,c.width,c.height);x.strokeStyle='#69717b';x.beginPath();x.moveTo(0,k?38:${layout.ground||232});x.lineTo(c.width,k?38:${layout.ground||232});x.stroke();x.drawImage(images[id],0,0,k?${Math.round(cw/ppp)}:${cw},k?${Math.round(ch/ppp)}:${ch})}}}document.querySelector('#play').onclick=()=>{paused=!paused;document.querySelector('#play').textContent=paused?'Play':'Pause'};document.querySelector('#speed').oninput=e=>document.querySelector('#fps').textContent=e.target.value+' fps';document.onkeydown=e=>{if(e.code==='Space'){e.preventDefault();document.querySelector('#play').click()}if(e.code==='ArrowRight'){paused=true;step++;draw()}if(e.code==='ArrowLeft'){paused=true;step=Math.max(0,step-1);draw()}};function tick(t){if(!paused&&t-last>1000/document.querySelector('#speed').value){step++;last=t;draw()}requestAnimationFrame(tick)}Promise.all(images.map(i=>i.decode())).then(()=>{draw();requestAnimationFrame(tick)});</script>`;
  fs.writeFileSync(path.join(out,'review.html'),html);
  console.log(JSON.stringify({output:out,walk:report.sequences.walk,emptyCells:metrics.slice(count).map(x=>x.area)}));
}
main().catch(e=>{console.error(e);process.exit(1)});

/* Pose — guide de pose semi-transparent par-dessus la caméra.
   100% local : rien ne quitte l'appareil. */
'use strict';

const $ = s => document.querySelector(s);
const cam=$('#cam'), ovimg=$('#ovimg'), gesture=$('#gesture'), stage=$('#stage');
const strip=$('#strip'), file=$('#file'), lens=$('#lens');
const preview=$('#preview'), shot=$('#shot'), panel=$('#panel'), msg=$('#msg');
const opacity=$('#opacity'), opacityVal=$('#opacityVal'), count=$('#count');

let poses=[], cur=-1;
const urls=new Map(), thumbs=new Map();
let stream=null, facing='environment', mode='normal', timer=0, busy=false;
let lastShot=null;

/* ---------- toast ---------- */
let toastEl, toastT;
function toast(t){
  if(!toastEl){toastEl=document.createElement('div');toastEl.id='toast';document.body.appendChild(toastEl);}
  toastEl.textContent=t; toastEl.classList.add('on');
  clearTimeout(toastT); toastT=setTimeout(()=>toastEl.classList.remove('on'),2600);
}

/* ---------- IndexedDB ---------- */
const DB='pose-db', ST='poses';
function openDb(){return new Promise((res,rej)=>{
  const r=indexedDB.open(DB,1);
  r.onupgradeneeded=()=>{const d=r.result;if(!d.objectStoreNames.contains(ST))d.createObjectStore(ST,{keyPath:'id'});};
  r.onsuccess=()=>res(r.result); r.onerror=()=>rej(r.error);
});}
function tx(mode,fn){return openDb().then(d=>new Promise((res,rej)=>{
  const t=d.transaction(ST,mode), q=fn(t.objectStore(ST));
  t.oncomplete=()=>res(q?q.result:undefined); t.onerror=()=>rej(t.error);
}));}
const db={
  all:()=>tx('readonly',s=>s.getAll()),
  put:o=>tx('readwrite',s=>s.put(o)),
  del:id=>tx('readwrite',s=>s.delete(id)),
};

/* ---------- poses ---------- */
const newT=()=>({x:0,y:0,s:1,r:0,flip:false});
const P=()=>poses[cur];

function urlFor(pose){
  const key=pose.id+':'+mode;
  if(urls.has(key)) return urls.get(key);
  const blob=(mode==='edges'&&pose.edges)?pose.edges:pose.img;
  const u=URL.createObjectURL(blob); urls.set(key,u); return u;
}
function thumbFor(pose){
  if(!thumbs.has(pose.id)) thumbs.set(pose.id,URL.createObjectURL(pose.img));
  return thumbs.get(pose.id);
}
function dropUrls(id){
  for(const k of [...urls.keys()]){
    if(k.slice(0,id.length+1)===id+':'){ URL.revokeObjectURL(urls.get(k)); urls.delete(k); }
  }
  if(thumbs.has(id)){ URL.revokeObjectURL(thumbs.get(id)); thumbs.delete(id); }
}

function applyT(){
  const t=P()?P().t:newT();
  ovimg.style.transform=
    'translate(calc(-50% + '+t.x+'px), calc(-50% + '+t.y+'px)) rotate('+t.r+'deg) '+
    'scale('+(t.flip?-t.s:t.s)+','+t.s+')';
}

function render(){
  strip.querySelectorAll('.thumb:not(.add)').forEach(n=>n.remove());
  const addBtn=$('#btnAdd');
  poses.forEach((p,i)=>{
    const b=document.createElement('button');
    b.className='thumb'+(i===cur?' sel':'');
    b.style.backgroundImage='url('+thumbFor(p)+')';
    b.addEventListener('click',()=>select(i));
    let lp=null;
    const clear=()=>{ if(lp){clearTimeout(lp);lp=null;} };
    b.addEventListener('pointerdown',()=>{ lp=setTimeout(()=>{lp=null;remove(i);},550); });
    ['pointerup','pointercancel','pointerleave','pointermove'].forEach(e=>b.addEventListener(e,clear));
    strip.insertBefore(b,addBtn);
  });
  const p=P();
  if(p){ ovimg.src=urlFor(p); ovimg.classList.add('on'); applyT(); }
  else { ovimg.classList.remove('on'); ovimg.removeAttribute('src'); }
  $('#btnFlip').classList.toggle('act', !!(p&&p.t.flip));
}
function select(i){ cur=i; localStorage.setItem('pose.cur',String(i)); render(); }

async function remove(i){
  const p=poses[i]; if(!p) return;
  if(!confirm('Supprimer cette pose ?')) return;
  dropUrls(p.id);
  try{ await db.del(p.id); }catch(e){}
  poses.splice(i,1);
  if(cur>=poses.length) cur=poses.length-1;
  render();
}

async function add(list){
  let n=0;
  for(const f of list){
    if(!f.type || f.type.indexOf('image/')!==0) continue;
    const id='p'+Date.now()+Math.random().toString(36).slice(2,7);
    const rec={id,name:f.name||'pose',img:f,edges:null,t:newT()};
    try{ rec.edges=await edgesOf(f); }catch(e){}
    try{ await db.put(rec); }catch(e){}
    poses.push(rec); n++;
  }
  if(!n){ toast('Aucune image reconnue.'); return; }
  select(poses.length-1);
  toast(poses.length===n ? 'Glisse pour déplacer, pince pour redimensionner.' : 'Ajouté.');
}

/* ---------- contours (Sobel) ---------- */
async function edgesOf(blob){
  const bmp=await createImageBitmap(blob);
  const M=1200, sc=Math.min(1,M/Math.max(bmp.width,bmp.height));
  const w=Math.max(3,Math.round(bmp.width*sc)), h=Math.max(3,Math.round(bmp.height*sc));
  const c=document.createElement('canvas'); c.width=w; c.height=h;
  const g=c.getContext('2d',{willReadFrequently:true});
  g.drawImage(bmp,0,0,w,h);
  if(bmp.close) bmp.close();
  const s=g.getImageData(0,0,w,h).data;
  const gray=new Float32Array(w*h);
  for(let i=0,p=0;p<gray.length;i+=4,p++) gray[p]=s[i]*0.299+s[i+1]*0.587+s[i+2]*0.114;
  const out=g.createImageData(w,h), o=out.data;
  for(let y=1;y<h-1;y++) for(let x=1;x<w-1;x++){
    const i=y*w+x;
    const gx=-gray[i-w-1]-2*gray[i-1]-gray[i+w-1]+gray[i-w+1]+2*gray[i+1]+gray[i+w+1];
    const gy=-gray[i-w-1]-2*gray[i-w]-gray[i-w+1]+gray[i+w-1]+2*gray[i+w]+gray[i+w+1];
    let m=Math.hypot(gx,gy)/4;
    m = m<26 ? 0 : Math.min(255,m*1.8);
    const j=i*4; o[j]=255; o[j+1]=255; o[j+2]=255; o[j+3]=m;
  }
  g.putImageData(out,0,0);
  return new Promise(r=>c.toBlob(r,'image/png'));
}

/* ---------- caméra ---------- */
function fail(t){ panel.classList.remove('off'); msg.textContent=t; }

async function start(deviceId){
  if(!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia)
    return fail('Ce navigateur ne donne pas accès à la caméra. Ouvre le lien dans Safari.');
  const local=/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  if(location.protocol!=='https:' && !local)
    return fail('La caméra exige HTTPS. Ouvre la version en https://');
  stop();
  const video = deviceId
    ? {deviceId:{exact:deviceId}, width:{ideal:4096}, height:{ideal:3072}}
    : {facingMode:{ideal:facing}, width:{ideal:4096}, height:{ideal:3072}};
  try{
    stream=await navigator.mediaDevices.getUserMedia({video:video,audio:false});
  }catch(e){
    const m={
      NotAllowedError:'Accès caméra refusé. Réglages iOS → Safari → Caméra → Autoriser, puis recharge.',
      NotFoundError:'Aucune caméra trouvée.',
      NotReadableError:'La caméra est utilisée par une autre app. Ferme-la et réessaie.',
      OverconstrainedError:'Cet objectif ne répond pas. Repasse en objectif auto.'
    };
    return fail(m[e.name] || ('Caméra indisponible : '+e.name));
  }
  cam.srcObject=stream;
  cam.classList.toggle('mirror', facing==='user' && !deviceId);
  try{ await cam.play(); }catch(e){}
  panel.classList.add('off');
  fillLenses();
}
function stop(){ if(stream){ stream.getTracks().forEach(t=>t.stop()); stream=null; } }

async function fillLenses(){
  try{
    const ds=(await navigator.mediaDevices.enumerateDevices())
      .filter(d=>d.kind==='videoinput' && d.label);
    if(ds.length<3){ lens.hidden=true; return; }
    lens.innerHTML='<option value="">Objectif auto</option>'+ds.map(d=>{
      const label=d.label.replace(/camera/i,'').trim()||'Objectif';
      return '<option value="'+d.deviceId+'">'+label+'</option>';
    }).join('');
    lens.hidden=false;
  }catch(e){ lens.hidden=true; }
}

/* ---------- capture ---------- */
let actx=null;
function beep(f){
  try{
    const AC=window.AudioContext||window.webkitAudioContext;
    actx=actx||new AC();
    const o=actx.createOscillator(), g=actx.createGain();
    o.frequency.value=f; o.connect(g); g.connect(actx.destination);
    g.gain.setValueAtTime(0.08,actx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001,actx.currentTime+0.12);
    o.start(); o.stop(actx.currentTime+0.13);
  }catch(e){}
}
function countdown(n){
  busy=true; count.classList.add('on');
  return new Promise(res=>{
    (function tick(){
      count.textContent=String(n); beep(n===1?880:440); n--;
      if(n<0){ count.classList.remove('on'); busy=false; res(); }
      else setTimeout(tick,1000);
    })();
  });
}
function grab(){
  const vw=cam.videoWidth, vh=cam.videoHeight;
  if(!vw||!vh){ toast('Caméra pas encore prête.'); return; }
  // Recadrage identique au object-fit:cover de l'écran : ce qui est cadré est ce qui est gardé.
  const A=stage.clientWidth/stage.clientHeight, B=vw/vh;
  const sw = B>A ? vh*A : vw;
  const sh = B>A ? vh   : vw/A;
  const sx=(vw-sw)/2, sy=(vh-sh)/2;
  const w=Math.round(sw), h=Math.round(sh);
  const c=document.createElement('canvas'); c.width=w; c.height=h;
  const g=c.getContext('2d');
  if(cam.classList.contains('mirror')){ g.translate(w,0); g.scale(-1,1); }
  g.drawImage(cam, sx,sy,sw,sh, 0,0,w,h);
  const fl=$('#flash');
  fl.classList.remove('go'); void fl.offsetWidth; fl.classList.add('go');
  c.toBlob(b=>{
    lastShot=b;
    if(shot.src) URL.revokeObjectURL(shot.src);
    shot.src=URL.createObjectURL(b);
    preview.hidden=false;
  },'image/jpeg',0.95);
}
function shoot(){
  if(busy||!stream) return;
  if(timer>0) countdown(timer).then(grab); else grab();
}
async function save(){
  if(!lastShot) return;
  const f=new File([lastShot],'pose-'+Date.now()+'.jpg',{type:'image/jpeg'});
  if(navigator.canShare && navigator.canShare({files:[f]})){
    try{ await navigator.share({files:[f]}); preview.hidden=true; return; }
    catch(e){ if(e.name==='AbortError') return; }
  }
  const a=document.createElement('a');
  a.href=URL.createObjectURL(f); a.download=f.name; a.click();
  toast('Appui long sur la photo puis « Ajouter aux photos ».');
}

/* ---------- gestes sur le guide ---------- */
const pts=new Map(); let base=null;
const cen=a=>({x:a.reduce((s,p)=>s+p.x,0)/a.length, y:a.reduce((s,p)=>s+p.y,0)/a.length});
const dis=a=>Math.hypot(a[1].x-a[0].x, a[1].y-a[0].y);
const ang=a=>Math.atan2(a[1].y-a[0].y, a[1].x-a[0].x)*180/Math.PI;

function snap(){
  const p=P(); if(!p) return;
  const a=[...pts.values()];
  base={t:{...p.t}, c:cen(a), d:a.length>1?dis(a):0, a:a.length>1?ang(a):0};
}
gesture.addEventListener('pointerdown',e=>{
  try{ gesture.setPointerCapture(e.pointerId); }catch(err){}
  pts.set(e.pointerId,{x:e.clientX,y:e.clientY}); snap();
});
gesture.addEventListener('pointermove',e=>{
  const p=P();
  if(!pts.has(e.pointerId)||!base||!p) return;
  pts.set(e.pointerId,{x:e.clientX,y:e.clientY});
  const a=[...pts.values()], c=cen(a), t=p.t;
  t.x=base.t.x+(c.x-base.c.x);
  t.y=base.t.y+(c.y-base.c.y);
  if(a.length>1 && base.d>8){
    t.s=Math.min(6,Math.max(0.15, base.t.s*(dis(a)/base.d)));
    t.r=base.t.r+(ang(a)-base.a);
  }
  applyT();
});
function endPtr(e){
  if(!pts.delete(e.pointerId)) return;
  if(pts.size) snap();
  else { base=null; const p=P(); if(p) db.put(p).catch(()=>{}); }
}
gesture.addEventListener('pointerup',endPtr);
gesture.addEventListener('pointercancel',endPtr);

let tap=0;
gesture.addEventListener('click',()=>{
  const n=Date.now(), p=P();
  if(n-tap<320 && p){ p.t=newT(); applyT(); db.put(p).catch(()=>{}); toast('Guide recentré.'); }
  tap=n;
});
document.addEventListener('gesturestart',e=>e.preventDefault());
document.addEventListener('dblclick',e=>e.preventDefault());

/* ---------- UI ---------- */
$('#btnStart').addEventListener('click',()=>start(lens.value||null));
$('#btnAdd').addEventListener('click',()=>file.click());
file.addEventListener('change',()=>{ add([...file.files]); file.value=''; });

opacity.addEventListener('input',()=>{
  ovimg.style.opacity=String(opacity.value/100);
  opacityVal.textContent=opacity.value+'%';
  localStorage.setItem('pose.op',opacity.value);
});

$('#btnGrid').addEventListener('click',e=>{
  const on=$('#grid').classList.toggle('on');
  e.currentTarget.classList.toggle('act',on);
  localStorage.setItem('pose.grid',on?'1':'');
});
$('#btnMode').addEventListener('click',e=>{
  mode = mode==='normal'?'edges':'normal';
  e.currentTarget.classList.toggle('act',mode==='edges');
  localStorage.setItem('pose.mode',mode);
  const p=P();
  if(p && mode==='edges' && !p.edges) toast('Contours indisponibles pour cette image.');
  render();
});
$('#btnFlip').addEventListener('click',e=>{
  const p=P(); if(!p) return;
  p.t.flip=!p.t.flip; applyT(); db.put(p).catch(()=>{});
  e.currentTarget.classList.toggle('act',p.t.flip);
});
$('#btnReset').addEventListener('click',()=>{
  const p=P(); if(!p) return;
  p.t=newT(); applyT(); db.put(p).catch(()=>{});
});
$('#btnHide').addEventListener('click',()=>document.body.classList.toggle('hidden-ui'));

$('#btnTimer').addEventListener('click',e=>{
  timer = timer===0?3 : timer===3?10 : 0;
  e.currentTarget.textContent=timer+'s';
});
$('#btnSwap').addEventListener('click',()=>{
  facing = facing==='environment'?'user':'environment';
  lens.value=''; start(null);
});
lens.addEventListener('change',()=>start(lens.value||null));
$('#shutter').addEventListener('click',shoot);
$('#pvRetry').addEventListener('click',()=>{ preview.hidden=true; });
$('#pvSave').addEventListener('click',save);

document.addEventListener('visibilitychange',()=>{
  if(!document.hidden && stream && cam.paused) cam.play().catch(()=>{});
});

/* ---------- boot ---------- */
(async function boot(){
  const op=localStorage.getItem('pose.op')||'45';
  opacity.value=op; ovimg.style.opacity=String(op/100); opacityVal.textContent=op+'%';
  if(localStorage.getItem('pose.grid')){ $('#grid').classList.add('on'); $('#btnGrid').classList.add('act'); }
  mode=localStorage.getItem('pose.mode')||'normal';
  if(mode==='edges') $('#btnMode').classList.add('act');

  try{ poses=(await db.all())||[]; }catch(e){ poses=[]; }
  const saved=parseInt(localStorage.getItem('pose.cur')||'-1',10);
  cur = (saved>=0 && saved<poses.length) ? saved : (poses.length?0:-1);
  render();

  if('serviceWorker' in navigator)
    navigator.serviceWorker.register('sw.js').catch(()=>{});

  const standalone = navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  if(!standalone && /iPhone|iPad/.test(navigator.userAgent))
    msg.textContent='Astuce : bouton Partager puis « Sur l’écran d’accueil » pour l’avoir en plein écran comme une vraie app.';
})();

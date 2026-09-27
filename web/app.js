/* Pose — guide de pose semi-transparent par-dessus la caméra.
   100 % local : aucune requête réseau après l'installation. */
'use strict';

const $ = s => document.querySelector(s);
const cam = $('#cam'), stage = $('#stage'), frame = $('#frame'), guide = $('#guide'), gest = $('#gesture');
const topbar = $('#topbar'), dock = $('#dock');
const tip = $('#tip'), tipText = $('#tipText'), countEl = $('#count'), burstChip = $('#burstChip');
const gridEl = $('#grid'), levelEl = $('#level'), levelBar = $('#levelBar');
const pill = $('#pill'), pillInner = $('#pillInner'), pillImg = $('#pillImg'), pillName = $('#pillName');
const opacity = $('#opacity'), opacityVal = $('#opacityVal');
const btnContour = $('#btnContour'), btnMirror = $('#btnMirror');
const shutter = $('#shutter'), ringC = $('#ringC');
const thumb = $('#thumb'), thumbImg = $('#thumbImg'), thumbBadge = $('#thumbBadge');
const lensesEl = $('#lenses'), file = $('#file');
const sheet = $('#sheet'), sheetHead = $('#sheetHead'), sheetBody = $('#sheetBody'), backdrop = $('#backdrop');
const packGrid = $('#packGrid'), userGrid = $('#userGrid'), btnEdit = $('#btnEdit');
const viewer = $('#viewer'), vTrack = $('#vTrack'), vCount = $('#vCount'), vInfo = $('#vInfo'), vSaveAll = $('#vSaveAll');
const panel = $('#panel'), msg = $('#msg'), btnStart = $('#btnStart');
const toastEl = $('#toast');

const PACK = window.POSE_PACK;
const RATIOS = ['4:5', '3:4', '1:1', '9:16'];
const RATIO_V = { '4:5': 4 / 5, '3:4': 3 / 4, '1:1': 1, '9:16': 9 / 16 };
const RATIO_NOTE = { '4:5': 'Portrait Instagram', '3:4': 'Capteur complet', '1:1': 'Carré', '9:16': 'Story' };
const EASE_OUT = 'cubic-bezier(.23,1,.32,1)';
const EASE_IN_OUT = 'cubic-bezier(.77,0,.175,1)';
const RING = 232.48; // 2π × 37
const reduce = matchMedia('(prefers-reduced-motion: reduce)');

const S = {
  userPoses: [], shots: [], cur: null, bt: {},
  edges: true, op: 0.55, ratio: '4:5', timer: 0, burst: 1, grid: false, level: false,
  facing: 'environment', deviceId: null, stream: null,
  busy: false, counting: false, cancel: false,
  frame: { x: 0, y: 0, w: 0, h: 0 },
  video: { x: 0, y: 0, w: 0, h: 0, sc: 1 },
};

/* ---------- Préférences (stockage facultatif) ---------- */
const pref = {
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : v; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
};

/* ---------- Toast ---------- */
let toastT = 0;
function toast(text) {
  toastEl.textContent = text;
  toastEl.classList.add('on');
  clearTimeout(toastT);
  toastT = setTimeout(() => toastEl.classList.remove('on'), 2400);
}

/* ---------- Dialogue de confirmation ---------- */
function ask({ title, text = '', ok = 'OK', danger = false }) {
  const dlg = $('#dlg'), okB = $('#dlgOk'), noB = $('#dlgCancel');
  $('#dlgTitle').textContent = title;
  $('#dlgText').textContent = text;
  okB.textContent = ok;
  okB.classList.toggle('danger', danger);
  dlg.classList.add('open');
  return new Promise(res => {
    const done = v => {
      dlg.classList.remove('open');
      okB.onclick = noB.onclick = dlg.onclick = null;
      res(v);
    };
    okB.onclick = () => done(true);
    noB.onclick = () => done(false);
    dlg.onclick = e => { if (e.target === dlg) done(false); };
  });
}

/* ---------- IndexedDB ---------- */
let dbp = null;
function openDb() {
  if (dbp) return dbp;
  dbp = new Promise((res, rej) => {
    const r = indexedDB.open('pose-db', 2);
    r.onupgradeneeded = () => {
      const d = r.result;
      if (!d.objectStoreNames.contains('poses')) d.createObjectStore('poses', { keyPath: 'id' });
      if (!d.objectStoreNames.contains('shots')) d.createObjectStore('shots', { keyPath: 'id' });
    };
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  return dbp;
}
function tx(store, mode, fn) {
  return openDb().then(d => new Promise((res, rej) => {
    const t = d.transaction(store, mode), q = fn(t.objectStore(store));
    t.oncomplete = () => res(q ? q.result : undefined);
    t.onerror = t.onabort = () => rej(t.error);
  }));
}
const db = {
  all: s => tx(s, 'readonly', o => o.getAll()),
  put: (s, v) => tx(s, 'readwrite', o => o.put(v)),
  del: (s, k) => tx(s, 'readwrite', o => o.delete(k)),
  clear: s => tx(s, 'readwrite', o => o.clear()),
};

/* ---------- Poses ---------- */
const newT = () => ({ x: 0, y: 0, s: 1, r: 0, flip: false });
const svgUrl = svg => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
const packCache = new Map(), userUrls = new Map();

function packUrl(p, w) {
  const key = p.id + ':' + (w || 480);
  if (!packCache.has(key)) packCache.set(key, svgUrl(window.poseSVG(p.j, w)));
  return packCache.get(key);
}
function userUrl(p, which) {
  const blob = which === 'edges' && p.edges ? p.edges : p.img;
  const key = p.id + ':' + (blob === p.img ? 'img' : 'edges');
  if (!userUrls.has(key)) userUrls.set(key, URL.createObjectURL(blob));
  return userUrls.get(key);
}
function dropUserUrls(id) {
  for (const k of [...userUrls.keys()]) {
    if (k.startsWith(id + ':')) { URL.revokeObjectURL(userUrls.get(k)); userUrls.delete(k); }
  }
}

function curPose() {
  if (!S.cur) return null;
  return S.cur.kind === 'b'
    ? PACK.find(p => p.id === S.cur.id) || null
    : S.userPoses.find(p => p.id === S.cur.id) || null;
}
function curT() {
  const p = curPose();
  if (!p) return null;
  if (S.cur.kind === 'b') return S.bt[p.id] || (S.bt[p.id] = newT());
  return p.t || (p.t = newT());
}
function saveT() {
  if (!S.cur) return;
  if (S.cur.kind === 'b') pref.set('pose.bt', JSON.stringify(S.bt));
  else { const p = curPose(); if (p) db.put('poses', p).catch(() => {}); }
}

function applyT() {
  const t = curT() || newT();
  guide.style.transform =
    `translate(calc(-50% + ${t.x}px), calc(-50% + ${t.y}px)) rotate(${t.r}deg) scale(${t.flip ? -t.s : t.s}, ${t.s})`;
}

function renderGuide() {
  const p = curPose();
  if (!p) {
    guide.classList.remove('on');
    guide.removeAttribute('src');
  } else {
    const src = S.cur.kind === 'b' ? packUrl(p) : userUrl(p, S.edges ? 'edges' : 'img');
    if (guide.getAttribute('src') !== src) guide.src = src;
    guide.classList.add('on');
    applyT();
  }
  renderPill();
  renderGuideTools();
}

function renderPill() {
  const p = curPose();
  if (!p) {
    pillName.textContent = 'Choisir une pose';
    pillImg.removeAttribute('src');
    return;
  }
  const builtin = S.cur.kind === 'b';
  pillName.textContent = builtin ? p.name : 'Référence ' + (S.userPoses.indexOf(p) + 1);
  pillImg.src = builtin ? packUrl(p, 120) : userUrl(p, 'img');
  pillImg.classList.toggle('cover', !builtin);
}

function renderGuideTools() {
  const p = curPose(), t = curT();
  const builtin = !!S.cur && S.cur.kind === 'b';
  // Le pack est déjà en traits : le mode contours ne s'applique qu'aux références importées.
  btnContour.disabled = !p || builtin;
  btnContour.setAttribute('aria-pressed', String(!!p && !builtin && S.edges));
  btnMirror.disabled = !p;
  btnMirror.setAttribute('aria-pressed', String(!!(t && t.flip)));
}

function select(kind, id, opts = {}) {
  const had = guide.classList.contains('on');
  S.cur = { kind, id };
  pref.set('pose.cur', kind + ':' + id);
  renderGuide();

  if (!reduce.matches) {
    if (had) {
      guide.animate([{ opacity: 0, filter: 'blur(6px)' }, { opacity: S.op, filter: 'blur(0px)' }],
        { duration: 240, easing: EASE_OUT });
    }
    const dx = (opts.dir || 0) * 14;
    pillInner.animate(
      [{ opacity: 0, transform: `translateX(${dx}px)`, filter: 'blur(3px)' },
       { opacity: 1, transform: 'none', filter: 'blur(0px)' }],
      { duration: 220, easing: EASE_OUT });
  }

  if (!opts.quiet) {
    const p = curPose();
    showTip(kind === 'b' ? p.tip : 'Glisse pour placer, pince pour ajuster, double-tap pour recentrer.');
  }
}

function orderedPoses() {
  return PACK.map(p => ({ kind: 'b', id: p.id }))
    .concat(S.userPoses.map(p => ({ kind: 'u', id: p.id })));
}
function cyclePose(dir) {
  const list = orderedPoses();
  let i = S.cur ? list.findIndex(x => x.kind === S.cur.kind && x.id === S.cur.id) : -1;
  i = (i + dir + list.length) % list.length;
  select(list[i].kind, list[i].id, { dir });
}

/* ---------- Conseil de pose ---------- */
let tipT = 0;
function showTip(text) {
  tipText.textContent = text;
  tip.classList.add('on');
  clearTimeout(tipT);
  tipT = setTimeout(() => tip.classList.remove('on'), 5200);
}
tip.addEventListener('click', () => { clearTimeout(tipT); tip.classList.remove('on'); });

/* ---------- Contours (Sobel) ---------- */
async function edgesOf(blob) {
  const bmp = await createImageBitmap(blob);
  const M = 1200, sc = Math.min(1, M / Math.max(bmp.width, bmp.height));
  const w = Math.max(3, Math.round(bmp.width * sc)), h = Math.max(3, Math.round(bmp.height * sc));
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.drawImage(bmp, 0, 0, w, h);
  if (bmp.close) bmp.close();
  const s = g.getImageData(0, 0, w, h).data;
  const gray = new Float32Array(w * h);
  for (let i = 0, p = 0; p < gray.length; i += 4, p++) gray[p] = s[i] * .299 + s[i + 1] * .587 + s[i + 2] * .114;
  const out = g.createImageData(w, h), o = out.data;
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
    const i = y * w + x;
    const gx = -gray[i - w - 1] - 2 * gray[i - 1] - gray[i + w - 1] + gray[i - w + 1] + 2 * gray[i + 1] + gray[i + w + 1];
    const gy = -gray[i - w - 1] - 2 * gray[i - w] - gray[i - w + 1] + gray[i + w - 1] + 2 * gray[i + w] + gray[i + w + 1];
    let m = Math.hypot(gx, gy) / 4;
    m = m < 26 ? 0 : Math.min(255, m * 1.8);
    const j = i * 4; o[j] = 255; o[j + 1] = 255; o[j + 2] = 255; o[j + 3] = m;
  }
  g.putImageData(out, 0, 0);
  return new Promise(r => c.toBlob(r, 'image/png'));
}

/* ---------- Cadre ---------- */
function layout() {
  const W = innerWidth, H = innerHeight, r = RATIO_V[S.ratio];
  let w = W, h = W / r;
  if (h > H) { h = H; w = H * r; }
  const top = topbar.getBoundingClientRect().bottom + 4;
  const dockTop = dock.getBoundingClientRect().top + 24; // le haut du dock est un dégradé
  const avail = dockTop - top;
  let y;
  if (S.ratio === '9:16') y = (H - h) / 2;
  else if (h <= avail) y = top + (avail - h) / 2;
  else y = Math.max(0, Math.min(top, (H - h) / 2));
  const x = (W - w) / 2;
  S.frame = { x, y, w, h };
  Object.assign(frame.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' });
  document.documentElement.style.setProperty('--dock-h', (H - dock.getBoundingClientRect().top) + 'px');
  layoutVideo();
}

/* La vidéo couvre le CADRE, pas l'écran : sinon on jette une partie du capteur
   avant même de cadrer (écran plus étroit que le 3:4 du capteur). */
function layoutVideo() {
  const vw = cam.videoWidth, vh = cam.videoHeight, f = S.frame;
  if (!vw || !vh || !f.w) return;
  const sc = Math.max(f.w / vw, f.h / vh), w = vw * sc, h = vh * sc;
  const x = f.x + (f.w - w) / 2, y = f.y + (f.h - h) / 2;
  // Premier placement (ou changement de caméra) : pas d'animation depuis le plein écran.
  const jump = !S.video.w || Math.abs(S.video.w / S.video.h - w / h) > .01;
  if (jump) cam.classList.add('instant');
  S.video = { x, y, w, h, sc };
  Object.assign(cam.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' });
  if (jump) { void cam.offsetWidth; cam.classList.remove('instant'); }
}
cam.addEventListener('loadedmetadata', layoutVideo);
cam.addEventListener('resize', layoutVideo);

/* ---------- Caméra ---------- */
function fail(text) {
  msg.textContent = text;
  btnStart.textContent = 'Réessayer';
  panel.classList.add('open');
}

async function start() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia)
    return fail('Ce navigateur ne donne pas accès à la caméra. Ouvre le lien dans Safari.');
  const local = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  if (location.protocol !== 'https:' && !local)
    return fail('La caméra exige une connexion sécurisée. Ouvre la version en https://');

  stopCam();
  cam.classList.add('switching');
  const size = { width: { ideal: 4096 }, height: { ideal: 3072 } };
  const video = S.deviceId
    ? Object.assign({ deviceId: { exact: S.deviceId } }, size)
    : Object.assign({ facingMode: { ideal: S.facing } }, size);
  try {
    S.stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });
  } catch (e) {
    if (S.deviceId) { S.deviceId = null; return start(); }
    cam.classList.remove('switching');
    const m = {
      NotAllowedError: 'Accès caméra refusé. Réglages iOS → Safari → Appareil photo → Autoriser, puis relance.',
      NotFoundError: 'Aucune caméra trouvée.',
      NotReadableError: 'La caméra est utilisée par une autre app. Ferme-la et réessaie.',
    };
    return fail(m[e.name] || 'Caméra indisponible (' + e.name + ').');
  }
  cam.srcObject = S.stream;
  cam.classList.toggle('mirror', S.facing === 'user');
  try { await cam.play(); } catch (e) {}
  const first = panel.classList.contains('open') || !S.started;
  S.started = true;
  panel.classList.remove('open');
  layout();
  fillLenses();
  keepAwake();
  const p = curPose();
  if (first && p) showTip(S.cur.kind === 'b' ? p.tip : 'Glisse pour placer, pince pour ajuster, double-tap pour recentrer.');
}
cam.addEventListener('loadeddata', () => cam.classList.remove('switching'));

function stopCam() {
  if (S.stream) { S.stream.getTracks().forEach(t => t.stop()); S.stream = null; }
}

/* Objectifs : iOS expose chaque objectif comme une caméra distincte, avec un libellé localisé. */
async function fillLenses() {
  lensesEl.hidden = true;
  if (S.facing !== 'environment') return;
  let ds;
  try { ds = await navigator.mediaDevices.enumerateDevices(); } catch (e) { return; }
  const back = ds.filter(d => d.kind === 'videoinput' && d.label && !/front|avant|facetime/i.test(d.label));
  const ultra = back.find(d => /ultra/i.test(d.label));
  const tele = back.find(d => /t[ée]l[ée]/i.test(d.label));
  const wide = back.find(d => !/ultra|t[ée]l[ée]|dual|double|triple/i.test(d.label));
  const opts = [];
  if (ultra) opts.push({ id: ultra.deviceId, label: '.5' });
  if (wide) opts.push({ id: wide.deviceId, label: '1×' });
  if (tele) opts.push({ id: tele.deviceId, label: 'Télé' });
  if (opts.length < 2) return;

  const track = S.stream && S.stream.getVideoTracks()[0];
  const trackId = S.deviceId || (track && track.getSettings().deviceId);
  const activeId = opts.some(o => o.id === trackId) ? trackId : (wide && wide.deviceId);
  lensesEl.innerHTML = opts.map(o =>
    `<button class="lens${o.id === activeId ? ' on' : ''}" type="button" data-id="${o.id}">${o.label}</button>`).join('');
  lensesEl.hidden = false;
  layout();
}
lensesEl.addEventListener('click', e => {
  const b = e.target.closest('.lens');
  if (!b || b.classList.contains('on')) return;
  S.deviceId = b.dataset.id;
  start();
});

/* Écran allumé pendant la séance : indispensable avec le retardateur. */
let wakeLock = null;
async function keepAwake() {
  try {
    if ('wakeLock' in navigator && !wakeLock) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    }
  } catch (e) {}
}

/* ---------- Son ---------- */
let actx = null;
function audio() {
  try { actx = actx || new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {}
  return actx;
}
function beep(f) {
  const a = audio(); if (!a) return;
  const o = a.createOscillator(), g = a.createGain();
  o.frequency.value = f; o.connect(g); g.connect(a.destination);
  g.gain.setValueAtTime(.08, a.currentTime);
  g.gain.exponentialRampToValueAtTime(.001, a.currentTime + .12);
  o.start(); o.stop(a.currentTime + .13);
}
function click() {
  const a = audio(); if (!a) return;
  const len = Math.floor(a.sampleRate * .05), buf = a.createBuffer(1, len, a.sampleRate), d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 3);
  const src = a.createBufferSource(), f = a.createBiquadFilter(), g = a.createGain();
  f.type = 'bandpass'; f.frequency.value = 2400; g.gain.value = .35;
  src.buffer = buf; src.connect(f); f.connect(g); g.connect(a.destination); src.start();
}

/* ---------- Capture ---------- */
const sleep = ms => new Promise(res => {
  const t0 = performance.now();
  (function chk() {
    if (S.cancel) return res(false);
    if (performance.now() - t0 >= ms) return res(true);
    setTimeout(chk, 40);
  })();
});

function showCount(n) {
  countEl.textContent = n;
  countEl.classList.add('on');
  if (!reduce.matches) {
    countEl.animate([{ opacity: 0, transform: 'scale(1.25)' }, { opacity: 1, transform: 'scale(1)' }],
      { duration: 260, easing: EASE_OUT });
  }
}

async function countdown(n) {
  S.counting = true;
  shutter.classList.add('counting');
  const ring = ringC.animate([{ strokeDashoffset: RING }, { strokeDashoffset: 0 }],
    { duration: n * 1000, easing: 'linear', fill: 'forwards' });
  try {
    for (let s = n; s > 0; s--) {
      showCount(s);
      beep(s === 1 ? 880 : 520);
      if (!(await sleep(1000))) return false;
    }
    return true;
  } finally {
    ring.cancel();
    S.counting = false;
    shutter.classList.remove('counting');
    countEl.classList.remove('on');
  }
}

async function shoot() {
  if (!S.stream || !cam.videoWidth) { toast('Caméra pas encore prête.'); return; }
  if (S.busy) { S.cancel = true; return; } // second appui : annule le décompte ou la rafale
  S.busy = true;
  S.cancel = false;
  try {
    if (S.timer > 0 && !(await countdown(S.timer))) return;
    for (let i = 0; i < S.burst && !S.cancel; i++) {
      if (S.burst > 1) { burstChip.textContent = `${i + 1} / ${S.burst}`; burstChip.classList.add('on'); }
      await takeOne();
      if (i < S.burst - 1 && !(await sleep(380))) break;
    }
  } catch (e) {
    toast('Capture impossible.');
  } finally {
    S.busy = false;
    S.cancel = false;
    burstChip.classList.remove('on');
  }
}

/* Ne garde que ce qui est dans le cadre, à la résolution du capteur. */
function grab() {
  const vw = cam.videoWidth, vh = cam.videoHeight;
  layoutVideo();
  const f = S.frame, v = S.video, sc = v.sc;
  let sx = Math.max(0, (f.x - v.x) / sc), sy = Math.max(0, (f.y - v.y) / sc);
  const sw = Math.min(f.w / sc, vw - sx), sh = Math.min(f.h / sc, vh - sy);
  const mirror = cam.classList.contains('mirror');
  if (mirror) sx = vw - sx - sw;
  const w = Math.round(sw), h = Math.round(sh);
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d');
  if (mirror) { g.translate(w, 0); g.scale(-1, 1); }
  g.drawImage(cam, sx, sy, sw, sh, 0, 0, w, h);
  return new Promise((res, rej) =>
    c.toBlob(b => (b ? res({ blob: b, w, h }) : rej(new Error('toBlob'))), 'image/jpeg', .92));
}

async function takeOne() {
  const { blob, w, h } = await grab();
  flash();
  click();
  const rec = { id: 's' + Date.now() + Math.random().toString(36).slice(2, 6), blob, w, h, t: Date.now() };
  S.shots.push(rec);
  db.put('shots', rec).catch(() => toast('Stockage plein : enregistre ta pellicule.'));
  renderThumb(true);
}

function flash() {
  $('#flash').animate([{ opacity: .45 }, { opacity: 0 }], { duration: 260, easing: 'ease-out' });
}

/* ---------- Pellicule ---------- */
const shotUrls = new Map();
function shotUrl(s) {
  if (!shotUrls.has(s.id)) shotUrls.set(s.id, URL.createObjectURL(s.blob));
  return shotUrls.get(s.id);
}
function dropShotUrl(id) {
  if (shotUrls.has(id)) { URL.revokeObjectURL(shotUrls.get(id)); shotUrls.delete(id); }
}

function renderThumb(animate) {
  const n = S.shots.length;
  thumb.classList.toggle('empty', !n);
  thumbBadge.hidden = n < 2;
  thumbBadge.textContent = n;
  if (!n) { thumbImg.removeAttribute('src'); return; }
  thumbImg.src = shotUrl(S.shots[n - 1]);
  if (animate && !reduce.matches) {
    thumbImg.animate([{ opacity: 0, transform: 'scale(.7)' }, { opacity: 1, transform: 'scale(1)' }],
      { duration: 240, easing: EASE_OUT });
  }
}

let metaRaf = 0;
function vIndex() {
  return Math.min(S.shots.length - 1, Math.max(0, Math.round(vTrack.scrollLeft / Math.max(1, vTrack.clientWidth))));
}
function updateMeta() {
  const i = vIndex(), s = S.shots[i];
  if (!s) return;
  vCount.textContent = `${i + 1} / ${S.shots.length}`;
  const kb = s.blob.size / 1024;
  const size = kb < 1024 ? Math.round(kb) + ' Ko' : (kb / 1024).toFixed(1).replace('.', ',') + ' Mo';
  vInfo.textContent = `${s.w} × ${s.h} · ${size}`;
  vSaveAll.textContent = S.shots.length > 1 ? `Tout enregistrer (${S.shots.length})` : 'Enregistrer';
}
vTrack.addEventListener('scroll', () => {
  cancelAnimationFrame(metaRaf);
  metaRaf = requestAnimationFrame(updateMeta);
}, { passive: true });

function openViewer() {
  if (!S.shots.length) { toast('Pas encore de photo.'); return; }
  vTrack.innerHTML = '';
  for (const s of S.shots) {
    const slide = document.createElement('div');
    slide.className = 'slide';
    const img = new Image();
    img.decoding = 'async';
    img.alt = '';
    img.src = shotUrl(s);
    slide.appendChild(img);
    vTrack.appendChild(slide);
  }
  // S'ouvre depuis la vignette, pas depuis le centre.
  const r = thumb.getBoundingClientRect();
  viewer.style.transformOrigin = `${r.left + r.width / 2}px ${r.top + r.height / 2}px`;
  viewer.classList.add('open');
  viewer.setAttribute('aria-hidden', 'false');
  requestAnimationFrame(() => { vTrack.scrollLeft = vTrack.scrollWidth; updateMeta(); });
}
function closeViewer() {
  viewer.classList.remove('open');
  viewer.setAttribute('aria-hidden', 'true');
}

const pad = n => String(n).padStart(2, '0');
function fileOf(s, i) {
  const d = new Date(s.t);
  const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return new File([s.blob], `Pose_${stamp}${i != null ? '_' + (i + 1) : ''}.jpg`, { type: 'image/jpeg', lastModified: s.t });
}
async function shareFiles(files) {
  if (navigator.canShare && navigator.canShare({ files })) {
    try { await navigator.share({ files }); return 'ok'; }
    catch (e) { return e.name === 'AbortError' ? 'abort' : 'fail'; }
  }
  for (const f of files) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(f);
    a.download = f.name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  }
  return 'download';
}

async function deleteCurrent() {
  const i = vIndex(), s = S.shots[i];
  if (!s) return;
  const ok = await ask({ title: 'Supprimer cette photo ?', text: 'Elle sera retirée de la pellicule de Pose.', ok: 'Supprimer', danger: true });
  if (!ok) return;
  db.del('shots', s.id).catch(() => {});
  dropShotUrl(s.id);
  S.shots.splice(i, 1);
  renderThumb(false);
  if (!S.shots.length) { closeViewer(); return; }
  vTrack.children[i].remove();
  updateMeta();
}

async function clearShots() {
  await db.clear('shots').catch(() => {});
  S.shots.forEach(s => dropShotUrl(s.id));
  S.shots = [];
  renderThumb(false);
  closeViewer();
}

async function saveAll() {
  const n = S.shots.length;
  if (!n) return;
  const r = await shareFiles(S.shots.map((s, i) => fileOf(s, n > 1 ? i : null)));
  if (r === 'fail') { toast('Partage impossible. Supprime quelques photos et réessaie.'); return; }
  if (r === 'abort') return;
  const clear = await ask({
    title: 'Vider la pellicule ?',
    text: n > 1
      ? `Si les ${n} photos sont bien dans ta photothèque, retire-les de Pose pour libérer de la place.`
      : 'Si la photo est bien dans ta photothèque, retire-la de Pose pour libérer de la place.',
    ok: 'Vider', danger: true,
  });
  if (clear) { await clearShots(); toast('Pellicule vidée'); }
}

$('#vClose').addEventListener('click', closeViewer);
$('#vDelete').addEventListener('click', deleteCurrent);
$('#vShare').addEventListener('click', () => { const s = S.shots[vIndex()]; if (s) shareFiles([fileOf(s)]); });
vSaveAll.addEventListener('click', saveAll);
thumb.addEventListener('click', openViewer);

/* ---------- Tiroir des poses ---------- */
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const isSel = (kind, id) => !!S.cur && S.cur.kind === kind && S.cur.id === id;

function renderSheet() {
  packGrid.innerHTML = PACK.map((p, i) =>
    `<button class="pcard${isSel('b', p.id) ? ' sel' : ''}" type="button" data-kind="b" data-id="${p.id}" style="--i:${i}">` +
    `<span class="pimg"><img alt="" src="${packUrl(p, 160)}"></span><span>${esc(p.name)}</span></button>`).join('');
  userGrid.innerHTML =
    `<button class="pcard add" type="button" style="--i:${PACK.length}">` +
    `<span class="pimg"><svg class="i"><use href="#i-image-plus"/></svg></span><span>Importer</span></button>` +
    S.userPoses.map((p, i) =>
      `<button class="pcard user${isSel('u', p.id) ? ' sel' : ''}" type="button" data-kind="u" data-id="${p.id}" style="--i:${PACK.length + i + 1}">` +
      `<span class="pimg"><img alt="" src="${userUrl(p, 'img')}"></span><span>Réf. ${i + 1}</span>` +
      `<i class="del" aria-hidden="true"><svg class="i"><use href="#i-x"/></svg></i></button>`).join('');
  btnEdit.hidden = !S.userPoses.length;
}

function setEdit(on) {
  sheet.classList.toggle('editing', on);
  btnEdit.textContent = on ? 'OK' : 'Modifier';
}

function openSheet() {
  renderSheet();
  setEdit(false);
  sheet.style.transform = '';
  if (!reduce.matches) {
    sheet.classList.add('stagger');
    setTimeout(() => sheet.classList.remove('stagger'), 700);
  }
  sheet.classList.add('open');
  backdrop.classList.add('open');
}
function closeSheet() {
  sheet.style.transform = '';
  sheet.classList.remove('open');
  backdrop.classList.remove('open');
}

sheetBody.addEventListener('click', e => {
  const b = e.target.closest('.pcard');
  if (!b) return;
  if (b.classList.contains('add')) { file.click(); return; }
  const { kind, id } = b.dataset;
  if (kind === 'u' && sheet.classList.contains('editing')) { removeUserPose(id); return; }
  select(kind, id);
  closeSheet();
});
btnEdit.addEventListener('click', () => setEdit(!sheet.classList.contains('editing')));
backdrop.addEventListener('click', closeSheet);

/* Glisser vers le bas pour fermer : distance OU vitesse. Friction vers le haut. */
let sd = null;
sheetHead.addEventListener('pointerdown', e => {
  if (e.target.closest('button')) return;
  sd = { y: e.clientY, t: performance.now(), dy: 0 };
  sheetHead.setPointerCapture(e.pointerId);
  sheet.classList.add('dragging');
});
sheetHead.addEventListener('pointermove', e => {
  if (!sd) return;
  const raw = e.clientY - sd.y;
  sd.dy = raw >= 0 ? raw : -Math.sqrt(-raw) * 2;
  sheet.style.transform = `translateY(${sd.dy}px)`;
});
function endSheetDrag() {
  if (!sd) return;
  const v = sd.dy / Math.max(1, performance.now() - sd.t);
  sheet.classList.remove('dragging');
  if (sd.dy > 110 || (sd.dy > 20 && v > 0.11)) closeSheet();
  else sheet.style.transform = '';
  sd = null;
}
sheetHead.addEventListener('pointerup', endSheetDrag);
sheetHead.addEventListener('pointercancel', endSheetDrag);

async function importFiles(list) {
  let n = 0, last = null;
  for (const f of list) {
    if (!f.type || !f.type.startsWith('image/')) continue;
    const id = 'p' + Date.now() + Math.random().toString(36).slice(2, 7);
    const img = new Blob([f], { type: f.type });
    const rec = { id, name: f.name || 'Référence', img, edges: null, t: newT() };
    try { rec.edges = await edgesOf(img); } catch (e) {}
    try { await db.put('poses', rec); } catch (e) {}
    S.userPoses.push(rec);
    n++;
    last = rec;
  }
  if (!n) { toast('Aucune image reconnue.'); return; }
  closeSheet();
  select('u', last.id);
  toast(n > 1 ? `${n} références ajoutées` : 'Référence ajoutée');
}
file.addEventListener('change', () => { importFiles([...file.files]); file.value = ''; });

async function removeUserPose(id) {
  const ok = await ask({ title: 'Supprimer cette référence ?', text: 'Elle sera retirée de ta bibliothèque de poses.', ok: 'Supprimer', danger: true });
  if (!ok) return;
  db.del('poses', id).catch(() => {});
  dropUserUrls(id);
  S.userPoses = S.userPoses.filter(p => p.id !== id);
  if (isSel('u', id)) select('b', PACK[0].id, { quiet: true });
  else renderPill();
  renderSheet();
  if (!S.userPoses.length) setEdit(false);
}

/* ---------- Pastille de pose : tap = tiroir, balayage = pose suivante ---------- */
let ps = null;
pill.addEventListener('pointerdown', e => {
  ps = { x: e.clientX, t: performance.now(), moved: false };
  pill.setPointerCapture(e.pointerId);
});
pill.addEventListener('pointermove', e => {
  if (!ps) return;
  const dx = e.clientX - ps.x;
  if (Math.abs(dx) > 8) ps.moved = true;
  if (ps.moved) pillInner.style.transform = `translateX(${dx * .35}px)`;
});
pill.addEventListener('pointerup', e => {
  if (!ps) return;
  const dx = e.clientX - ps.x, v = Math.abs(dx) / Math.max(1, performance.now() - ps.t);
  pillInner.style.transform = '';
  if (ps.moved && (Math.abs(dx) > 40 || v > .3)) cyclePose(dx < 0 ? 1 : -1);
  else if (!ps.moved) openSheet();
  ps = null;
});
pill.addEventListener('pointercancel', () => { pillInner.style.transform = ''; ps = null; });

/* ---------- Gestes sur le guide ---------- */
const pts = new Map();
let base = null, moved = false, lastTap = 0;
const cen = a => ({ x: a.reduce((s, p) => s + p.x, 0) / a.length, y: a.reduce((s, p) => s + p.y, 0) / a.length });
const dis = a => Math.hypot(a[1].x - a[0].x, a[1].y - a[0].y);
const ang = a => Math.atan2(a[1].y - a[0].y, a[1].x - a[0].x) * 180 / Math.PI;

function snap() {
  const t = curT();
  if (!t) return;
  const a = [...pts.values()];
  base = { t: { ...t }, c: cen(a), d: a.length > 1 ? dis(a) : 0, a: a.length > 1 ? ang(a) : 0 };
}
gest.addEventListener('pointerdown', e => {
  try { gest.setPointerCapture(e.pointerId); } catch (err) {}
  if (!pts.size) moved = false;
  pts.set(e.pointerId, { x: e.clientX, y: e.clientY, x0: e.clientX, y0: e.clientY });
  snap();
});
gest.addEventListener('pointermove', e => {
  const p = pts.get(e.pointerId), t = curT();
  if (!p || !base || !t) return;
  p.x = e.clientX; p.y = e.clientY;
  if (Math.hypot(p.x - p.x0, p.y - p.y0) > 6) moved = true;
  const a = [...pts.values()], c = cen(a);
  t.x = base.t.x + (c.x - base.c.x);
  t.y = base.t.y + (c.y - base.c.y);
  if (a.length > 1 && base.d > 8) {
    t.s = Math.min(6, Math.max(.15, base.t.s * (dis(a) / base.d)));
    t.r = base.t.r + (ang(a) - base.a);
  }
  applyT();
});
function endPtr(e) {
  if (!pts.delete(e.pointerId)) return;
  if (pts.size) { snap(); return; }
  base = null;
  if (moved) { saveT(); return; }
  const now = performance.now();
  if (now - lastTap < 300) { resetGuide(); lastTap = 0; } else lastTap = now;
}
gest.addEventListener('pointerup', endPtr);
gest.addEventListener('pointercancel', endPtr);

function resetGuide() {
  const t = curT();
  if (!t) return;
  const flip = t.flip;
  Object.assign(t, newT(), { flip });
  if (!reduce.matches) {
    guide.style.transition = `transform 320ms ${EASE_IN_OUT}`;
    setTimeout(() => { guide.style.transition = ''; }, 340);
  }
  applyT();
  saveT();
}

/* ---------- Niveau ---------- */
let lvl = 0, lvlTarget = 0, lvlRaf = 0;
function onMotion(e) {
  const g = e.accelerationIncludingGravity;
  if (!g || g.x == null || g.y == null) return;
  // Téléphone à plat : l'horizon n'a pas de sens.
  if (Math.abs(g.y) < 3.5) { levelEl.classList.add('flat'); return; }
  levelEl.classList.remove('flat');
  // Rapport x / y : indépendant de la convention de signe (iOS et Android l'inversent).
  lvlTarget = Math.atan(g.x / -g.y) * 180 / Math.PI;
  if (!lvlRaf) lvlRaf = requestAnimationFrame(stepLevel);
}
function stepLevel() {
  lvlRaf = 0;
  lvl += (lvlTarget - lvl) * .25;
  const ok = Math.abs(lvl) < 1;
  levelBar.style.transform = `rotate(${ok ? 0 : -lvl}deg)`;
  levelEl.classList.toggle('ok', ok);
  if (Math.abs(lvlTarget - lvl) > .05) lvlRaf = requestAnimationFrame(stepLevel);
}
async function toggleLevel() {
  const btn = $('#btnLevel');
  if (!S.level) {
    const DM = window.DeviceMotionEvent;
    if (DM && typeof DM.requestPermission === 'function') {
      try {
        if ((await DM.requestPermission()) !== 'granted') { toast('Accès aux capteurs refusé.'); return; }
      } catch (e) { toast('Capteurs indisponibles.'); return; }
    }
    if (!DM) { toast('Pas de capteur de mouvement.'); return; }
    addEventListener('devicemotion', onMotion);
    S.level = true;
  } else {
    removeEventListener('devicemotion', onMotion);
    S.level = false;
  }
  levelEl.classList.toggle('on', S.level);
  btn.setAttribute('aria-pressed', String(S.level));
}

/* ---------- Réglages ---------- */
function setOpacity(v) {
  S.op = v / 100;
  guide.style.opacity = S.op;
  opacity.value = v;
  opacity.style.setProperty('--p', ((v - opacity.min) / (opacity.max - opacity.min) * 100) + '%');
  opacityVal.textContent = v + ' %';
}
opacity.addEventListener('input', () => { setOpacity(+opacity.value); pref.set('pose.op', opacity.value); });

function swapLabel(el, text) {
  if (el.textContent === text) return;
  el.textContent = text;
  if (!reduce.matches) {
    el.animate([{ opacity: 0, filter: 'blur(3px)', transform: 'scale(.92)' }, { opacity: 1, filter: 'blur(0px)', transform: 'none' }],
      { duration: 200, easing: EASE_OUT });
  }
}
function setBadge(el, value) {
  if (value) el.textContent = value;
  el.classList.toggle('on', !!value);
}

$('#btnGrid').addEventListener('click', e => {
  S.grid = !S.grid;
  gridEl.classList.toggle('on', S.grid);
  e.currentTarget.setAttribute('aria-pressed', String(S.grid));
  pref.set('pose.grid', S.grid ? '1' : '');
});
$('#btnLevel').addEventListener('click', toggleLevel);

$('#btnRatio').addEventListener('click', () => {
  S.ratio = RATIOS[(RATIOS.indexOf(S.ratio) + 1) % RATIOS.length];
  swapLabel($('#ratioLabel'), S.ratio);
  pref.set('pose.ratio', S.ratio);
  layout();
  toast(`${S.ratio} · ${RATIO_NOTE[S.ratio]}`);
});

$('#btnTimer').addEventListener('click', e => {
  S.timer = S.timer === 0 ? 3 : S.timer === 3 ? 10 : 0;
  e.currentTarget.setAttribute('aria-pressed', String(S.timer > 0));
  setBadge($('#timerBadge'), S.timer ? S.timer : '');
  pref.set('pose.timer', String(S.timer));
  toast(S.timer ? `Retardateur ${S.timer} s` : 'Retardateur désactivé');
});
$('#btnBurst').addEventListener('click', e => {
  S.burst = S.burst === 1 ? 3 : S.burst === 3 ? 5 : 1;
  e.currentTarget.setAttribute('aria-pressed', String(S.burst > 1));
  setBadge($('#burstBadge'), S.burst > 1 ? S.burst : '');
  pref.set('pose.burst', String(S.burst));
  toast(S.burst > 1 ? `Rafale de ${S.burst} photos` : 'Rafale désactivée');
});

btnContour.addEventListener('click', () => {
  S.edges = !S.edges;
  pref.set('pose.edges', S.edges ? '1' : '0');
  const p = curPose();
  if (p && S.edges && S.cur.kind === 'u' && !p.edges) toast('Contours indisponibles pour cette image.');
  renderGuide();
});
btnMirror.addEventListener('click', () => {
  const t = curT();
  if (!t) return;
  t.flip = !t.flip;
  applyT();
  saveT();
  renderGuideTools();
});

$('#btnHide').addEventListener('click', () => document.body.classList.add('bare'));
$('#btnShow').addEventListener('click', () => document.body.classList.remove('bare'));
$('#btnSwap').addEventListener('click', () => {
  S.facing = S.facing === 'environment' ? 'user' : 'environment';
  S.deviceId = null;
  start();
});
shutter.addEventListener('click', shoot);
btnStart.addEventListener('click', start);

// Certaines télécommandes Bluetooth envoient Entrée ; pratique aussi au clavier.
addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (viewer.classList.contains('open')) closeViewer();
    else if (sheet.classList.contains('open')) closeSheet();
    return;
  }
  if ((e.key === 'Enter' || e.key === ' ') && !sheet.classList.contains('open')
      && !viewer.classList.contains('open') && !$('#dlg').classList.contains('open')) {
    e.preventDefault();
    shoot();
  }
});

document.addEventListener('gesturestart', e => e.preventDefault());
document.addEventListener('visibilitychange', () => {
  if (document.hidden) return;
  const track = S.stream && S.stream.getVideoTracks()[0];
  if (S.stream && (!track || track.readyState === 'ended')) start();
  else if (S.stream && cam.paused) cam.play().catch(() => {});
  if (S.stream) keepAwake();
});
addEventListener('resize', layout);

/* ---------- Démarrage ---------- */
(async function boot() {
  setOpacity(+pref.get('pose.op', '55'));
  S.grid = !!pref.get('pose.grid', '');
  gridEl.classList.toggle('on', S.grid);
  $('#btnGrid').setAttribute('aria-pressed', String(S.grid));

  S.ratio = RATIOS.includes(pref.get('pose.ratio', '')) ? pref.get('pose.ratio', '') : '4:5';
  $('#ratioLabel').textContent = S.ratio;

  S.timer = +pref.get('pose.timer', '0') || 0;
  $('#btnTimer').setAttribute('aria-pressed', String(S.timer > 0));
  setBadge($('#timerBadge'), S.timer || '');
  S.burst = +pref.get('pose.burst', '1') || 1;
  $('#btnBurst').setAttribute('aria-pressed', String(S.burst > 1));
  setBadge($('#burstBadge'), S.burst > 1 ? S.burst : '');

  // Ancienne clé « pose.mode » reprise pour ne pas perdre le réglage.
  const legacy = pref.get('pose.mode', '');
  S.edges = pref.get('pose.edges', legacy ? (legacy === 'edges' ? '1' : '0') : '1') === '1';
  try { S.bt = JSON.parse(pref.get('pose.bt', '{}')) || {}; } catch (e) { S.bt = {}; }

  try { S.userPoses = ((await db.all('poses')) || []).sort((a, b) => (a.id < b.id ? -1 : 1)); } catch (e) {}
  try { S.shots = ((await db.all('shots')) || []).sort((a, b) => a.t - b.t); } catch (e) {}

  const saved = pref.get('pose.cur', '');
  const [k, id] = saved.includes(':') ? saved.split(':') : [];
  const exists = k === 'b' ? PACK.some(p => p.id === id) : k === 'u' && S.userPoses.some(p => p.id === id);
  S.cur = exists ? { kind: k, id } : { kind: 'b', id: PACK[0].id };
  renderGuide();
  renderThumb(false);

  frame.classList.add('instant');
  layout();
  requestAnimationFrame(() => frame.classList.remove('instant'));

  const standalone = navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  $('#installHint').hidden = standalone || !/iPhone|iPad/.test(navigator.userAgent);

  // Pas de cache hors-ligne en local : chaque rechargement doit servir le code à jour.
  const dev = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  if ('serviceWorker' in navigator && !dev) {
    navigator.serviceWorker.register('sw.js').then(reg => {
      reg.addEventListener('updatefound', () => {
        const nw = reg.installing;
        if (!nw) return;
        nw.addEventListener('statechange', () => {
          if (nw.state === 'activated' && navigator.serviceWorker.controller) toast('Mise à jour installée · relance l’app');
        });
      });
    }).catch(() => {});
  }

  // Permission déjà accordée : on saute l'écran d'accueil.
  let granted = false;
  try { granted = (await navigator.permissions.query({ name: 'camera' })).state === 'granted'; } catch (e) {}
  if (granted) start();
  else panel.classList.add('open');
})();

const V='pose-v1';
const ASSETS=['./','index.html','style.css','app.js','manifest.webmanifest',
              'icons/icon-180.png','icons/icon-512.png'];

self.addEventListener('install',e=>{
  e.waitUntil(caches.open(V).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys()
    .then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k))))
    .then(()=>self.clients.claim()));
});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET') return;
  e.respondWith(
    caches.match(e.request).then(hit=>hit || fetch(e.request).then(r=>{
      if(r.ok && new URL(e.request.url).origin===location.origin)
        caches.open(V).then(c=>c.put(e.request,r.clone()));
      return r;
    }).catch(()=>caches.match('index.html')))
  );
});

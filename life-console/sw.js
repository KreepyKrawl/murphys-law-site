self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil((async()=>{try{for(const k of await caches.keys())if(k.startsWith('observer-console'))await caches.delete(k)}catch(_){}try{await self.registration.unregister()}catch(_){}try{await self.clients.claim()}catch(_){}})()));

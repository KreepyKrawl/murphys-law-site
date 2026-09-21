(()=>{
  window.CONSOLE_BUILD='0.9.1';
  try {
    if (!window.CSS) window.CSS={};
    if (!window.CSS.escape) window.CSS.escape=s=>String(s).replace(/[^a-zA-Z0-9_-]/g,c=>'\\'+c);
  } catch(e) {}
  try {
    if (!('ResizeObserver' in window)) {
      window.ResizeObserver=class {
        constructor(cb){this.cb=cb;this.items=new Set();this._on=()=>this._emit();addEventListener('resize',this._on)}
        observe(el){this.items.add(el);setTimeout(()=>this._emit(),0)}
        unobserve(el){this.items.delete(el)}
        disconnect(){this.items.clear();removeEventListener('resize',this._on)}
        _emit(){try{this.cb([...this.items].map(target=>({target,contentRect:target.getBoundingClientRect()})),this)}catch(e){}}
      };
    }
  } catch(e) {}
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())).catch(()=>{});
    }
    if ('caches' in window) {
      caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('observer-console')).map(k=>caches.delete(k)))).catch(()=>{});
    }
  } catch(e) {}
  addEventListener('error',e=>{try{document.documentElement.dataset.runtimeError='1';console.error('[console]',e.error||e.message)}catch(_){}});
})();

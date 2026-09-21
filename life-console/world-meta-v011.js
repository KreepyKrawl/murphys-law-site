(()=>{'use strict';
if(!document.body.classList.contains('meta'))return;
const C=window.CONSOLE||{};
const hud=document.createElement('button');
hud.id='metaWorldHud';
hud.type='button';
hud.textContent='WORLD…';
hud.setAttribute('aria-label','Open WORLD sync');
hud.style.cssText='position:fixed;right:12px;top:12px;z-index:9500;height:30px;min-width:78px;padding:0 10px;border:1px solid rgba(255,255,255,.42);background:rgba(0,0,0,.78);color:#fff;font:900 8px ui-monospace,monospace;letter-spacing:.11em;backdrop-filter:blur(8px);box-shadow:0 0 18px rgba(255,255,255,.08)';
hud.onclick=()=>C.world?.open?.('sync');
document.body.append(hud);
const update=()=>{
  const s=C.world?.state;
  if(!s){hud.textContent='WORLD…';return}
  const n=Object.keys(s.pres||{}).length||(s.rt?1:0);
  hud.textContent=s.err?'WORLD!':s.busy?'SYNC…':s.live?`WORLD·${Math.max(1,n)}`:'OFFLINE';
  hud.style.borderColor=s.err?'#ff1830':s.live?'rgba(255,255,255,.72)':'rgba(255,255,255,.25)';
  hud.style.color=s.err?'#ff1830':'#fff';
};
update();setInterval(update,500);
})();

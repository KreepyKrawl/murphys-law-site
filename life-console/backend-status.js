(()=>{
  const setText=(sel,text)=>{const el=document.querySelector(sel);if(el)el.textContent=text};
  const appendSystem=(label,detail,state)=>{
    const frame=document.querySelector('.frame[data-id="systems"] .list');
    if(!frame||frame.querySelector('[data-backend-row]'))return;
    const row=document.createElement('div');
    row.className='row';row.dataset.backendRow='1';
    row.innerHTML=`<span class="bar"></span><div><b>${label}</b><small>${detail}</small></div><em>${state}</em>`;
    frame.append(row);
  };
  const patchTicker=(value,hot=false)=>{
    const track=document.querySelector('#tickerTrack');if(!track)return;
    const item=document.createElement('span');item.className=`tick ${hot?'hot':''}`;
    item.innerHTML=`<strong>BACKEND</strong>${value}`;
    track.prepend(item);
  };
  async function connect(){
    try{
      const boot=await window.LIFE_DB?.bootstrap();
      if(!boot?.payload)throw new Error('No bootstrap state returned');
      document.documentElement.dataset.backend='online';
      appendSystem('Life Console DB',`Supabase · ${boot.payload.version||'online'}`,'ON');
      const state=document.querySelector('.frame[data-id="systems"] .state');if(state)state.textContent='3 ONLINE';
      patchTicker('SUPABASE · ONLINE');
      window.dispatchEvent(new CustomEvent('life-console:backend',{detail:boot}));
      console.info('[Life Console] Supabase connected',boot.payload);
    }catch(err){
      document.documentElement.dataset.backend='offline';
      appendSystem('Life Console DB','connection failed','ERR');
      patchTicker('SUPABASE · OFFLINE',true);
      console.error('[Life Console] Supabase connection failed',err);
    }
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',connect,{once:true});else connect();
})();

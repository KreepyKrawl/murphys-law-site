(()=>{
  const URL='https://ouqnyndcubmhreqbwufe.supabase.co';
  const KEY='sb_publishable_C6DII7cDEneLCI5HT-FeGg_x1Xn6-tg';
  const headers={apikey:KEY,Authorization:`Bearer ${KEY}`,'Content-Type':'application/json'};
  async function request(path,options={}){
    const r=await fetch(`${URL}${path}`,{...options,headers:{...headers,...(options.headers||{})}});
    if(!r.ok){const text=await r.text();throw new Error(`Supabase ${r.status}: ${text}`)}
    if(r.status===204)return null;
    return r.json();
  }
  async function bootstrap(){
    const rows=await request('/rest/v1/console_bootstrap?key=eq.life-console&select=key,payload,updated_at');
    return rows?.[0]||null;
  }
  window.LIFE_DB={url:URL,projectRef:'ouqnyndcubmhreqbwufe',bootstrap,request};
})();

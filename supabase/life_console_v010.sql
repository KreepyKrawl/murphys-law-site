-- LIFE CONSOLE v0.10 — cloud-canonical world model
-- Designed for a single-user/private prototype with cross-device pairing.
-- Public clients never receive table privileges; all reads/writes go through SECURITY DEFINER RPCs
-- gated by a 256-bit world secret. Migrate to Supabase Auth memberships later without changing object IDs.

create extension if not exists pgcrypto;

create table if not exists public.lc_worlds (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Primary World',
  secret_hash bytea not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lc_objects (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.lc_worlds(id) on delete cascade,
  kind text not null default 'object',
  title text not null default 'Untitled',
  state text not null default 'READY',
  source jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists lc_objects_world_updated_idx on public.lc_objects(world_id, updated_at desc);

create table if not exists public.lc_views (
  world_id uuid not null references public.lc_worlds(id) on delete cascade,
  object_id uuid not null references public.lc_objects(id) on delete cascade,
  viewport text not null check (viewport in ('desktop','mobile','meta')),
  view jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (world_id, object_id, viewport)
);

create table if not exists public.lc_links (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.lc_worlds(id) on delete cascade,
  from_object uuid not null references public.lc_objects(id) on delete cascade,
  to_object uuid not null references public.lc_objects(id) on delete cascade,
  relation text not null default 'related',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(world_id, from_object, to_object, relation)
);

create table if not exists public.lc_events (
  id bigint generated always as identity primary key,
  world_id uuid not null references public.lc_worlds(id) on delete cascade,
  object_id uuid references public.lc_objects(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists lc_events_world_created_idx on public.lc_events(world_id, created_at desc);

create table if not exists public.lc_pair_codes (
  code_hash bytea primary key,
  world_id uuid not null references public.lc_worlds(id) on delete cascade,
  secret_plain text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists lc_pair_expiry_idx on public.lc_pair_codes(expires_at);

-- No direct client table access. SECURITY DEFINER RPCs below are the only public surface.
alter table public.lc_worlds enable row level security;
alter table public.lc_objects enable row level security;
alter table public.lc_views enable row level security;
alter table public.lc_links enable row level security;
alter table public.lc_events enable row level security;
alter table public.lc_pair_codes enable row level security;
revoke all on public.lc_worlds, public.lc_objects, public.lc_views, public.lc_links, public.lc_events, public.lc_pair_codes from anon, authenticated;

create or replace function public.lc_world_for_secret(p_secret text)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from public.lc_worlds
  where secret_hash = digest(coalesce(p_secret,''), 'sha256')
  limit 1
$$;
revoke all on function public.lc_world_for_secret(text) from public;

create or replace function public.lc_bootstrap_world(p_secret text, p_name text default 'Primary World')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid;
begin
  if length(coalesce(p_secret,'')) < 48 then
    raise exception 'invalid world secret';
  end if;
  select id into v_world from public.lc_worlds where secret_hash = digest(p_secret,'sha256');
  if v_world is null then
    insert into public.lc_worlds(name,secret_hash)
    values (coalesce(nullif(p_name,''),'Primary World'), digest(p_secret,'sha256'))
    returning id into v_world;
    insert into public.lc_events(world_id,event_type,payload)
    values(v_world,'world_created',jsonb_build_object('version','0.10.0'));
  else
    update public.lc_worlds set updated_at=now() where id=v_world;
  end if;
  return v_world;
end $$;

create or replace function public.lc_world_snapshot(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare v_world uuid;
begin
  v_world := public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  return jsonb_build_object(
    'world_id', v_world,
    'objects', coalesce((select jsonb_agg(to_jsonb(o) order by o.updated_at desc) from public.lc_objects o where o.world_id=v_world and o.archived_at is null),'[]'::jsonb),
    'views', coalesce((select jsonb_agg(to_jsonb(v)) from public.lc_views v where v.world_id=v_world),'[]'::jsonb),
    'links', coalesce((select jsonb_agg(to_jsonb(l)) from public.lc_links l where l.world_id=v_world),'[]'::jsonb),
    'events', coalesce((select jsonb_agg(ej order by created_at desc) from (
       select jsonb_build_object('id',e.id,'object_id',e.object_id,'object_title',o.title,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at) ej, e.created_at
       from public.lc_events e left join public.lc_objects o on o.id=e.object_id
       where e.world_id=v_world order by e.created_at desc limit 150
    ) q),'[]'::jsonb)
  );
end $$;

create or replace function public.lc_save_object(p_secret text, p_object jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid; v_id uuid; v_existing uuid;
begin
  v_world := public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  begin v_id := nullif(p_object->>'id','')::uuid; exception when others then v_id := null; end;
  if v_id is null then v_id := gen_random_uuid(); end if;
  select id into v_existing from public.lc_objects where id=v_id and world_id=v_world;
  if v_existing is null then
    insert into public.lc_objects(id,world_id,kind,title,state,source,payload)
    values(v_id,v_world,coalesce(nullif(p_object->>'kind',''),'object'),coalesce(nullif(p_object->>'title',''),'Untitled'),coalesce(nullif(p_object->>'state',''),'READY'),coalesce(p_object->'source','{}'::jsonb),coalesce(p_object->'payload','{}'::jsonb));
    insert into public.lc_events(world_id,object_id,event_type,payload) values(v_world,v_id,'object_created',jsonb_build_object('kind',p_object->>'kind'));
  else
    update public.lc_objects set
      kind=coalesce(nullif(p_object->>'kind',''),kind),
      title=coalesce(nullif(p_object->>'title',''),title),
      state=coalesce(nullif(p_object->>'state',''),state),
      source=coalesce(p_object->'source',source),
      payload=coalesce(p_object->'payload',payload),
      revision=revision+1, updated_at=now()
    where id=v_id and world_id=v_world;
  end if;
  update public.lc_worlds set updated_at=now() where id=v_world;
  return v_id;
end $$;

create or replace function public.lc_save_view(p_secret text, p_object_id uuid, p_viewport text, p_view jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid;
begin
  v_world:=public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  if p_viewport not in ('desktop','mobile','meta') then raise exception 'invalid viewport'; end if;
  if not exists(select 1 from public.lc_objects where id=p_object_id and world_id=v_world) then raise exception 'object not found'; end if;
  insert into public.lc_views(world_id,object_id,viewport,view) values(v_world,p_object_id,p_viewport,coalesce(p_view,'{}'::jsonb))
  on conflict(world_id,object_id,viewport) do update set view=excluded.view,updated_at=now();
end $$;

create or replace function public.lc_append_event(p_secret text, p_object_id uuid default null, p_event_type text default 'change', p_payload jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid; v_id bigint;
begin
  v_world:=public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  if p_object_id is not null and not exists(select 1 from public.lc_objects where id=p_object_id and world_id=v_world) then raise exception 'object not found'; end if;
  insert into public.lc_events(world_id,object_id,event_type,payload) values(v_world,p_object_id,coalesce(nullif(p_event_type,''),'change'),coalesce(p_payload,'{}'::jsonb)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.lc_archive_object(p_secret text, p_object_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid;
begin
  v_world:=public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  update public.lc_objects set archived_at=now(),updated_at=now(),revision=revision+1 where id=p_object_id and world_id=v_world;
  insert into public.lc_events(world_id,object_id,event_type) values(v_world,p_object_id,'object_archived');
end $$;

create or replace function public.lc_save_link(p_secret text, p_from uuid, p_to uuid, p_relation text default 'related', p_metadata jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid; v_id uuid;
begin
  v_world:=public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  if not exists(select 1 from public.lc_objects where world_id=v_world and id=p_from) or not exists(select 1 from public.lc_objects where world_id=v_world and id=p_to) then raise exception 'object not found'; end if;
  insert into public.lc_links(world_id,from_object,to_object,relation,metadata)
  values(v_world,p_from,p_to,coalesce(nullif(p_relation,''),'related'),coalesce(p_metadata,'{}'::jsonb))
  on conflict(world_id,from_object,to_object,relation) do update set metadata=excluded.metadata
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.lc_issue_pair(p_secret text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_world uuid; v_code text;
begin
  v_world:=public.lc_world_for_secret(p_secret);
  if v_world is null then raise exception 'world not found'; end if;
  delete from public.lc_pair_codes where expires_at < now() or used_at is not null;
  loop
    v_code := upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
    begin
      insert into public.lc_pair_codes(code_hash,world_id,secret_plain,expires_at) values(digest(v_code,'sha256'),v_world,p_secret,now()+interval '5 minutes');
      exit;
    exception when unique_violation then null;
    end;
  end loop;
  return v_code;
end $$;

create or replace function public.lc_claim_pair(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_secret text; v_hash bytea;
begin
  v_hash:=digest(upper(trim(coalesce(p_code,''))),'sha256');
  update public.lc_pair_codes set used_at=now()
  where code_hash=v_hash and used_at is null and expires_at>now()
  returning secret_plain into v_secret;
  if v_secret is null then raise exception 'invalid or expired pair code'; end if;
  return v_secret;
end $$;

-- Grant only functions, never underlying tables.
grant execute on function public.lc_bootstrap_world(text,text) to anon, authenticated;
grant execute on function public.lc_world_snapshot(text) to anon, authenticated;
grant execute on function public.lc_save_object(text,jsonb) to anon, authenticated;
grant execute on function public.lc_save_view(text,uuid,text,jsonb) to anon, authenticated;
grant execute on function public.lc_append_event(text,uuid,text,jsonb) to anon, authenticated;
grant execute on function public.lc_archive_object(text,uuid) to anon, authenticated;
grant execute on function public.lc_save_link(text,uuid,uuid,text,jsonb) to anon, authenticated;
grant execute on function public.lc_issue_pair(text) to anon, authenticated;
grant execute on function public.lc_claim_pair(text) to anon, authenticated;

-- Private file bucket reserved for the authenticated-storage phase. Do not make public.
insert into storage.buckets(id,name,public,file_size_limit)
values('life-console','life-console',false,536870912)
on conflict(id) do update set public=false;

-- Deliberately no anonymous storage policies in v0.10. Remote Drive/web references are cross-view now;
-- raw uploads remain TRANSIENT until an authenticated/signed-upload bridge is enabled.

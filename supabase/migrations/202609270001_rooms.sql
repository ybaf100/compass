-- Apply in the Supabase SQL editor before launching Room mode. Anonymous Auth
-- must be enabled. The publishable key is safe for a client; service keys are not.
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null unique check (invite_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  owner_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  destination_latitude double precision,
  destination_longitude double precision,
  destination_name text,
  destination_updated_by uuid references auth.users(id),
  destination_updated_at timestamptz,
  constraint valid_shared_point check (
    (destination_latitude is null and destination_longitude is null)
    or (destination_latitude between -90 and 90 and
        destination_longitude between -180 and 180)
  )
);

create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  nickname text not null check (char_length(nickname) between 1 and 24),
  latitude double precision,
  longitude double precision,
  accuracy double precision,
  updated_at timestamptz not null default now(),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id),
  constraint valid_member_point check (
    (latitude is null and longitude is null and accuracy is null)
    or (latitude between -90 and 90 and longitude between -180 and 180
        and accuracy between 0 and 10000)
  )
);

create table if not exists public.shared_pings (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  created_by uuid not null references auth.users(id),
  created_by_nickname text not null,
  created_at timestamptz not null default now()
);
create index if not exists shared_pings_room_time
  on public.shared_pings(room_id, created_at desc);

create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.room_members m
    where m.room_id = p_room_id and m.user_id = (select auth.uid())
  );
$$;

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.shared_pings enable row level security;
drop policy if exists room_read on public.rooms;
drop policy if exists member_read on public.room_members;
drop policy if exists ping_read on public.shared_pings;
create policy room_read on public.rooms for select to authenticated
  using (public.is_room_member(id));
create policy member_read on public.room_members for select to authenticated
  using (public.is_room_member(room_id));
create policy ping_read on public.shared_pings for select to authenticated
  using (public.is_room_member(room_id));
-- There are deliberately no direct write policies. All writes go through
-- membership-checking RPCs below, with server timestamps and author IDs.

create or replace function public.create_compass_room(p_nickname text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_i integer;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if char_length(trim(p_nickname)) not between 1 and 24 then
    raise exception 'invalid_nickname';
  end if;
  loop
    v_code := '';
    for v_i in 1..6 loop
      v_code := v_code || substr(v_alphabet,
        1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    begin
      insert into public.rooms(invite_code, owner_id)
        values (v_code, v_user) returning id into v_id;
      exit;
    exception when unique_violation then
      -- Extremely rare invite-code collision; generate another code.
    end;
  end loop;
  insert into public.room_members(room_id, user_id, nickname)
    values (v_id, v_user, trim(p_nickname));
  return jsonb_build_object('room_id', v_id, 'already_joined', false);
end;
$$;

create or replace function public.join_compass_room(p_code text, p_nickname text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_joined boolean;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if char_length(trim(p_nickname)) not between 1 and 24 then
    raise exception 'invalid_nickname';
  end if;
  if upper(trim(p_code)) !~ '^[A-HJ-NP-Z2-9]{6}$' then
    raise exception 'invalid_invite_code';
  end if;
  select id into v_id from public.rooms where invite_code = upper(trim(p_code));
  if v_id is null then raise exception 'room_not_found'; end if;
  select exists(select 1 from public.room_members
    where room_id = v_id and user_id = v_user) into v_joined;
  insert into public.room_members(room_id, user_id, nickname)
    values (v_id, v_user, trim(p_nickname)) on conflict do nothing;
  return jsonb_build_object('room_id', v_id, 'already_joined', v_joined);
end;
$$;

create or replace function public.update_compass_location(
  p_room_id uuid, p_latitude double precision,
  p_longitude double precision, p_accuracy double precision)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_latitude not between -90 and 90 or
     p_longitude not between -180 and 180 or
     p_accuracy not between 0 and 10000 then
    raise exception 'invalid_location';
  end if;
  update public.room_members set latitude = p_latitude,
    longitude = p_longitude, accuracy = p_accuracy, updated_at = now()
    where room_id = p_room_id and user_id = auth.uid();
  if not found then raise exception 'not_room_member'; end if;
end;
$$;

create or replace function public.update_compass_nickname(p_room_id uuid, p_nickname text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if char_length(trim(p_nickname)) not between 1 and 24 then
    raise exception 'invalid_nickname';
  end if;
  update public.room_members set nickname = trim(p_nickname)
    where room_id = p_room_id and user_id = auth.uid();
  if not found then raise exception 'not_room_member'; end if;
end;
$$;

create or replace function public.set_compass_destination(
  p_room_id uuid, p_latitude double precision,
  p_longitude double precision, p_name text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_room_member(p_room_id) then
    raise exception 'not_room_member';
  end if;
  if p_latitude not between -90 and 90 or
     p_longitude not between -180 and 180 then
    raise exception 'invalid_location';
  end if;
  update public.rooms set destination_latitude = p_latitude,
    destination_longitude = p_longitude,
    destination_name = nullif(left(trim(p_name), 80), ''),
    destination_updated_by = auth.uid(), destination_updated_at = now()
    where id = p_room_id;
end;
$$;

create or replace function public.send_compass_ping(
  p_room_id uuid, p_latitude double precision, p_longitude double precision)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_nickname text;
begin
  if p_latitude not between -90 and 90 or
     p_longitude not between -180 and 180 then
    raise exception 'invalid_location';
  end if;
  select nickname into v_nickname from public.room_members
    where room_id = p_room_id and user_id = auth.uid();
  if v_nickname is null then raise exception 'not_room_member'; end if;
  -- Serialize retention among concurrent pings in the same Room.
  perform 1 from public.rooms where id = p_room_id for update;
  insert into public.shared_pings(room_id, latitude, longitude,
    created_by, created_by_nickname)
    values (p_room_id, p_latitude, p_longitude, auth.uid(), v_nickname);
  delete from public.shared_pings where room_id = p_room_id
    and (created_at < now() - interval '30 minutes' or id not in (
      select id from public.shared_pings where room_id = p_room_id
      order by created_at desc, id desc limit 20));
end;
$$;

create or replace function public.leave_compass_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from public.rooms where id = p_room_id for update;
  delete from public.room_members
    where room_id = p_room_id and user_id = auth.uid();
  if not found then return; end if;
  if not exists (select 1 from public.room_members where room_id = p_room_id) then
    delete from public.rooms where id = p_room_id;
  elsif v_owner = auth.uid() then
    update public.rooms set owner_id = (
      select user_id from public.room_members where room_id = p_room_id
      order by joined_at, user_id limit 1)
      where id = p_room_id;
  end if;
end;
$$;

revoke all on function public.is_room_member(uuid) from public, anon;
revoke all on function public.create_compass_room(text) from public, anon;
revoke all on function public.join_compass_room(text,text) from public, anon;
revoke all on function public.update_compass_location(uuid,double precision,double precision,double precision) from public, anon;
revoke all on function public.update_compass_nickname(uuid,text) from public, anon;
revoke all on function public.set_compass_destination(uuid,double precision,double precision,text) from public, anon;
revoke all on function public.send_compass_ping(uuid,double precision,double precision) from public, anon;
revoke all on function public.leave_compass_room(uuid) from public, anon;
grant execute on function public.is_room_member(uuid) to authenticated;
grant execute on function public.create_compass_room(text) to authenticated;
grant execute on function public.join_compass_room(text,text) to authenticated;
grant execute on function public.update_compass_location(uuid,double precision,double precision,double precision) to authenticated;
grant execute on function public.update_compass_nickname(uuid,text) to authenticated;
grant execute on function public.set_compass_destination(uuid,double precision,double precision,text) to authenticated;
grant execute on function public.send_compass_ping(uuid,double precision,double precision) to authenticated;
grant execute on function public.leave_compass_room(uuid) to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'rooms') then
    alter publication supabase_realtime add table public.rooms;
  end if;
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'room_members') then
    alter publication supabase_realtime add table public.room_members;
  end if;
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'shared_pings') then
    alter publication supabase_realtime add table public.shared_pings;
  end if;
end $$;

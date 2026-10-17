alter table public.active_trips
  add column if not exists driver_id text;

create table if not exists public.line_gongs (
  line_id text primary key,
  audio_url text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.prague_stops (
  id text primary key,
  name text not null,
  latitude double precision,
  longitude double precision,
  zone text,
  location_type integer not null default 0,
  parent_station text,
  imported_at timestamptz not null default now()
);

create table if not exists public.prague_lines (
  id text primary key,
  short_name text not null,
  long_name text not null default '',
  route_type integer,
  color text,
  text_color text,
  imported_at timestamptz not null default now()
);

alter table public.line_gongs enable row level security;
alter table public.prague_stops enable row level security;
alter table public.prague_lines enable row level security;

create policy "line gongs are readable" on public.line_gongs
  for select to anon, authenticated using (true);
create policy "prototype admins manage line gongs" on public.line_gongs
  for all to anon, authenticated using (true) with check (true);
create policy "Prague stops are readable" on public.prague_stops
  for select to anon, authenticated using (true);
create policy "prototype admins import Prague stops" on public.prague_stops
  for all to anon, authenticated using (true) with check (true);
create policy "Prague lines are readable" on public.prague_lines
  for select to anon, authenticated using (true);
create policy "prototype admins import Prague lines" on public.prague_lines
  for all to anon, authenticated using (true) with check (true);

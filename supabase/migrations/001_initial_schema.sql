create table if not exists public.active_trips (
  id text primary key,
  line_number text not null,
  stop_index integer not null default 0 check (stop_index >= 0),
  running boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.transit_stops (
  id text primary key,
  source text not null,
  name text not null,
  latitude double precision,
  longitude double precision,
  location_type integer not null default 0,
  parent_station text,
  updated_at timestamptz not null default now()
);

create index if not exists transit_stops_location_idx
  on public.transit_stops (latitude, longitude);

create table if not exists public.transit_routes (
  id text primary key,
  source text not null,
  short_name text not null,
  long_name text not null default '',
  route_type integer,
  color text,
  updated_at timestamptz not null default now()
);

create table if not exists public.route_stops (
  route_id text not null references public.transit_routes(id) on delete cascade,
  stop_id text not null references public.transit_stops(id) on delete cascade,
  stop_sequence integer not null,
  primary key (route_id, stop_id, stop_sequence)
);

create table if not exists public.gtfs_imports (
  source_url text primary key,
  source_name text not null,
  city text not null,
  stop_count integer not null default 0,
  station_count integer not null default 0,
  route_count integer not null default 0,
  imported_at timestamptz not null default now()
);

alter table public.active_trips enable row level security;
alter table public.transit_stops enable row level security;
alter table public.transit_routes enable row level security;
alter table public.route_stops enable row level security;
alter table public.gtfs_imports enable row level security;

create policy "public transport data is readable"
  on public.transit_stops for select to anon, authenticated using (true);
create policy "public routes are readable"
  on public.transit_routes for select to anon, authenticated using (true);
create policy "public route stops are readable"
  on public.route_stops for select to anon, authenticated using (true);
create policy "public import metadata is readable"
  on public.gtfs_imports for select to anon, authenticated using (true);
create policy "active trip is readable"
  on public.active_trips for select to anon, authenticated using (true);

-- Dočasné testovací pravidlo. Před veřejným vydáním bude zápis omezen
-- na přihlášené řidiče a administrátory s příslušnou rolí.
create policy "prototype clients can update active trip"
  on public.active_trips for all to anon, authenticated
  using (true) with check (true);

alter publication supabase_realtime add table public.active_trips;

insert into public.active_trips (id, line_number, stop_index, running)
values ('main', '1', 0, false)
on conflict (id) do nothing;

alter table public.active_trips
  add column if not exists direction text not null default 'forward'
    check (direction in ('forward', 'reverse')),
  add column if not exists delay_minutes integer not null default 0,
  add column if not exists occupancy text not null default 'low'
    check (occupancy in ('low', 'medium', 'full')),
  add column if not exists stop_requested boolean not null default false,
  add column if not exists alert_text text;

alter table public.active_trips
  add column if not exists start_stop_index integer not null default 0
    check (start_stop_index >= 0),
  add column if not exists end_stop_index integer not null default 0
    check (end_stop_index >= start_stop_index);

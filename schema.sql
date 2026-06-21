-- ============================================================
-- WAYPOINT — Database Schema (PostgreSQL / Supabase)
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ---------- Users ----------
create table users (
  id              uuid primary key default gen_random_uuid(),
  email           text unique not null,
  password_hash   text not null,
  display_name    text not null,
  avatar_color    text default '#E2654A',
  home_currency   text default 'USD',
  created_at      timestamptz default now(),
  last_login_at   timestamptz
);

-- ---------- Trips ----------
create table trips (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid references users(id) on delete cascade,
  name            text not null,
  destination_city text not null,
  destination_lat double precision,
  destination_lng double precision,
  start_date      date,
  end_date        date,
  pace            text check (pace in ('relaxed','moderate','packed')) default 'moderate',
  transport_mode  text check (transport_mode in ('walking','driving','transit')) default 'driving',
  budget_cap_cents integer default 0,
  emergency_number text,
  embassy_info    text,
  share_code      text unique,
  is_shared       boolean default false,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index idx_trips_owner on trips(owner_id);
create index idx_trips_share_code on trips(share_code);

-- ---------- Trip members (collaborators) ----------
create table trip_members (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid references trips(id) on delete cascade,
  user_id     uuid references users(id) on delete cascade,
  role        text check (role in ('owner','editor','viewer')) default 'editor',
  color       text,
  joined_at   timestamptz default now(),
  unique(trip_id, user_id)
);

-- ---------- Hotels / home bases (a trip can have multiple, e.g. multi-city) ----------
create table bases (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid references trips(id) on delete cascade,
  name        text not null,
  address     text,
  lat         double precision not null,
  lng         double precision not null,
  check_in    date,
  check_out   date,
  is_primary  boolean default true
);

-- ---------- Celebrity / editorial guide library ----------
create table celebrity_picks (
  id          uuid primary key default gen_random_uuid(),
  celebrity_name text not null,
  city        text not null,
  country     text,
  place_name  text not null,
  category    text,
  lat         double precision,
  lng         double precision,
  note        text,
  source_url  text,
  is_published boolean default true,
  sort_weight integer default 0,
  created_by_admin_id uuid references users(id),
  created_at  timestamptz default now()
);
create index idx_celeb_city on celebrity_picks(city);
create index idx_celeb_celebrity on celebrity_picks(celebrity_name);

-- ---------- Places ----------
create table places (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid references trips(id) on delete cascade,
  added_by        uuid references users(id),
  name            text not null,
  category        text check (category in ('museum','restaurant','bar','festival','landmark','shopping','nightlife','other')) default 'other',
  lat             double precision not null,
  lng             double precision not null,
  address         text,
  notes           text,
  reservation_url text,
  visit_duration_min integer default 60,
  estimated_cost_cents integer default 0,
  priority        integer default 3,           -- 1 (must-do) .. 5 (optional)
  status          text check (status in ('planned','visited','skipped')) default 'planned',
  celebrity_pick_id uuid references celebrity_picks(id),
  day_assignment  integer,                      -- which day of the trip (1-indexed), set by optimizer
  route_position  integer,                      -- order within that day's route
  source_place_id text,                         -- external place ID (e.g. Google Places) for enrichment
  created_at      timestamptz default now()
);
create index idx_places_trip on places(trip_id);

-- ---------- Ride requests (Uber handoff log) ----------
create table ride_requests (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid references trips(id) on delete cascade,
  requested_by    uuid references users(id),
  from_place_id   uuid references places(id),
  to_place_id     uuid references places(id),
  provider        text check (provider in ('uber','lyft','local_taxi')) default 'uber',
  deep_link       text,
  estimated_distance_m integer,
  estimated_duration_s integer,
  status          text check (status in ('initiated','completed','cancelled')) default 'initiated',
  requested_at    timestamptz default now()
);

-- ---------- Route cache (avoid recomputing OSRM/Google calls) ----------
create table route_cache (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid references trips(id) on delete cascade,
  profile         text,                          -- driving | walking | transit
  origin_place_id uuid,
  dest_place_id   uuid,
  distance_m      integer,
  duration_s      integer,
  geometry_geojson jsonb,
  computed_at     timestamptz default now()
);
create index idx_route_cache_trip on route_cache(trip_id);

-- ---------- Reviews / ratings left by users on places ----------
create table place_notes (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid references places(id) on delete cascade,
  user_id     uuid references users(id),
  rating      smallint check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz default now()
);

-- ---------- Partner / affiliate click tracking (for revenue reporting) ----------
create table affiliate_events (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid references trips(id),
  user_id     uuid references users(id),
  partner     text,        -- 'uber','opentable','viator','booking.com', etc.
  place_id    uuid references places(id),
  event_type  text,        -- 'click','booking_confirmed'
  payout_cents integer default 0,
  occurred_at timestamptz default now()
);

-- ---------- Admin audit log ----------
create table admin_audit_log (
  id          uuid primary key default gen_random_uuid(),
  admin_id    uuid references users(id),
  action      text not null,
  target_table text,
  target_id   uuid,
  detail      jsonb,
  created_at  timestamptz default now()
);

-- ---------- Row Level Security (Supabase) ----------
alter table trips enable row level security;
alter table places enable row level security;
alter table trip_members enable row level security;

create policy "trip visible to owner and members"
  on trips for select
  using (
    owner_id = auth.uid()
    or id in (select trip_id from trip_members where user_id = auth.uid())
    or is_shared = true
  );

create policy "places editable by trip members"
  on places for all
  using (
    trip_id in (
      select id from trips where owner_id = auth.uid()
      union
      select trip_id from trip_members where user_id = auth.uid()
    )
  );

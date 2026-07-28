-- ============================================================
-- Banjaluka Tree Map — database schema
-- Target: Supabase (Postgres + PostGIS), free tier
-- ============================================================

create extension if not exists postgis;
create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- Reference table: species
-- Keeping species separate avoids free-text typos ("hrast" vs
-- "Hrast" vs "hrast lužnjak") and lets you attach shared info
-- (e.g. average lifespan, native/invasive) once per species.
-- ------------------------------------------------------------
create table species (
  id            serial primary key,
  latin_name    text not null,
  local_name    text,             -- e.g. "Platan", "Divlji kesten"
  is_native     boolean,
  notes         text
);

-- ------------------------------------------------------------
-- Districts (dijelovi grada) — Borik, Centar, Nova Varoš, Rosulje,
-- Mejdan, Lauš, Budžak, Starčevica, Ada, Petrićevac, Česma, Šeher.
-- ------------------------------------------------------------
create table district (
  id            serial primary key,
  name          text not null unique
);

-- ------------------------------------------------------------
-- Streets / zones — lets you group trees by boulevard, street,
-- park, etc. and query "all trees on Bulevar Živojina Mišića".
-- Nests under a district.
-- ------------------------------------------------------------
create table zone (
  id            serial primary key,
  name          text not null,      -- "Bulevar Živojina Mišića"
  kind          text default 'street',  -- street | park | square | other
  district_id   integer references district(id)
);

-- ------------------------------------------------------------
-- Contributors — volunteers doing the scanning/inventory.
-- Supabase auth.users already gives you an id; this just adds
-- a public-facing profile.
-- ------------------------------------------------------------
create table contributor (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  created_at    timestamptz default now()
);

-- ------------------------------------------------------------
-- The core table: one row per physical tree.
-- ------------------------------------------------------------
create table tree (
  id                uuid primary key default uuid_generate_v4(),

  -- location (PostGIS point, WGS84)
  location          geography(Point, 4326) not null,

  -- classification
  species_id        integer references species(id),
  zone_id           integer references zone(id),
  district_id       integer references district(id),

  -- measurements
  height_m          numeric(5,2),          -- estimated/measured height
  trunk_diameter_cm numeric(6,2),           -- DBH, diameter at breast height
  canopy_width_m    numeric(5,2),

  -- condition
  planted_year      integer,
  health_status      text check (health_status in ('healthy','stressed','diseased','dead','removed')),
  condition_notes   text,

  -- cross-reference to OpenStreetMap, if also mapped there
  osm_node_id       bigint,

  -- provenance
  added_by          uuid references contributor(id),
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

create index tree_location_idx on tree using gist (location);
create index tree_zone_idx on tree (zone_id);
create index tree_district_idx on tree (district_id);
create index tree_species_idx on tree (species_id);

-- ------------------------------------------------------------
-- Photos — many per tree. Files live in Supabase Storage;
-- this table just stores the reference.
-- ------------------------------------------------------------
create table tree_photo (
  id            uuid primary key default uuid_generate_v4(),
  tree_id       uuid references tree(id) on delete cascade,
  storage_path  text not null,      -- path inside the Supabase Storage bucket
  caption       text,
  uploaded_by   uuid references contributor(id),
  created_at    timestamptz default now()
);

-- ------------------------------------------------------------
-- 3D scans — separate table because a tree may get re-scanned
-- over time (growth, seasons) and you want the history.
-- model_url points to a .glb/.gltf file, ideal for <model-viewer>.
-- ------------------------------------------------------------
create table tree_scan (
  id                uuid primary key default uuid_generate_v4(),
  tree_id           uuid references tree(id) on delete cascade,
  model_storage_path text not null,     -- .glb file in Supabase Storage
  method            text check (method in ('photogrammetry','lidar','nerf','other')),
  poly_count        integer,
  scanned_by        uuid references contributor(id),
  scanned_at        timestamptz default now(),
  notes             text
);

create index tree_scan_tree_idx on tree_scan (tree_id);

-- ------------------------------------------------------------
-- Row Level Security — public can read everything, but only
-- signed-in (verified) contributors can insert/edit. Tree
-- editing is intentionally NOT owner-restricted for update
-- (any authenticated user can edit any tree — access is gated
-- upstream by only granting admin/auth accounts to verified
-- people). Delete stays owner-only.
-- ------------------------------------------------------------
alter table tree enable row level security;
alter table tree_photo enable row level security;
alter table tree_scan enable row level security;
alter table contributor enable row level security;
alter table species enable row level security;
alter table zone enable row level security;
alter table district enable row level security;

create policy "public read species" on species for select using (true);
create policy "public read zones" on zone for select using (true);
create policy "public read districts" on district for select using (true);
-- No insert/update/delete policies for species/zone/district: only editable
-- via the Supabase SQL editor (service role), which bypasses RLS. This keeps
-- your reference lists from being edited through the public API by mistake.

create policy "public read trees" on tree for select using (true);
create policy "admin insert trees" on tree for insert
  with check (auth.role() = 'authenticated'::text);
create policy "admin update trees" on tree for update
  using (auth.role() = 'authenticated'::text);
-- Intentionally not owner-restricted: any authenticated (verified) user
-- can edit any tree. Only delete stays owner-only, below.
create policy "owner delete trees" on tree for delete using (auth.uid() = added_by);

create policy "public read photos" on tree_photo for select using (true);
create policy "auth users insert photos" on tree_photo for insert with check (auth.uid() is not null);

create policy "public read scans" on tree_scan for select using (true);
create policy "auth users insert scans" on tree_scan for insert with check (auth.uid() is not null);

create policy "public read contributors" on contributor for select using (true);
create policy "self insert contributor" on contributor for insert with check (auth.uid() = id);

-- ------------------------------------------------------------
-- Storage policies — buckets exist, but need explicit policies
-- for public read and authenticated upload. Run this after
-- creating the 'tree-photos', 'tree-models' and 'leaf-icons' buckets.
-- ------------------------------------------------------------
create policy "public read tree photos" on storage.objects
  for select using (bucket_id = 'tree-photos');
create policy "authenticated upload tree photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'tree-photos');

create policy "public read tree models" on storage.objects
  for select using (bucket_id = 'tree-models');
create policy "authenticated upload tree models" on storage.objects
  for insert to authenticated with check (bucket_id = 'tree-models');

create policy "public read leaf icons" on storage.objects
  for select using (bucket_id = 'leaf-icons');
-- No upload policy: leaf icons are managed manually via the Supabase
-- dashboard, not through the app.

-- ------------------------------------------------------------
-- Convenience view for the frontend: flattens species name,
-- district name, and lat/lng out of the PostGIS geography
-- column, and attaches the most recent scan (if any), so
-- index.html can query one simple view instead of juggling
-- PostGIS functions client-side. security_invoker = on so RLS
-- is evaluated as the querying user, not the view owner.
-- ------------------------------------------------------------
create or replace view tree_map
with (security_invoker = on) as
select
  t.id,
  t.height_m,
  t.trunk_diameter_cm,
  t.planted_year,
  t.health_status,
  t.condition_notes,
  ST_Y(t.location::geometry) as lat,
  ST_X(t.location::geometry) as lng,
  s.latin_name,
  s.local_name,
  d.name as district_name,
  (
    select ts.model_storage_path from tree_scan ts
    where ts.tree_id = t.id
    order by ts.scanned_at desc limit 1
  ) as latest_model_path
from tree t
left join species s on s.id = t.species_id
left join district d on d.id = t.district_id;

grant select on tree_map to anon, authenticated;

-- ------------------------------------------------------------
-- Seed data
-- ------------------------------------------------------------
insert into district (name) values
  ('Borik'), ('Centar'), ('Nova Varoš'), ('Rosulje'), ('Mejdan'),
  ('Lauš'), ('Budžak'), ('Starčevica'), ('Ada'), ('Petrićevac'),
  ('Česma'), ('Šeher');

insert into zone (name, kind) values ('Bulevar Živojina Mišića', 'street');

insert into species (latin_name, local_name, is_native) values
  ('Platanus x acerifolia', 'Platan', false),
  ('Aesculus hippocastanum', 'Divlji kesten', true),
  ('Tilia cordata', 'Lipa', true),
  ('Acer platanoides', 'Javor mlječ', true);

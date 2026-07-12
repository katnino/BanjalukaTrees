# Drveće Banjaluke

https://banjalukatrees.pages.dev/

A tree map of Banjaluka, beginning with
Bulevar Živojina Mišića. Includes:

- `schema.sql` — Postgres/PostGIS schema, ready to run in Supabase
- `index.html` — a working single-file demo (map + tree detail panel +
  3D model viewer)

## 1. Backend (Supabase)

1. A free project at supabase.com (free tier: 500MB database,
   1GB file storage — plenty for a while).
2. In the SQL `schema.sql` creates the tables,
   PostGIS geography column, row-level security policies, and seeds
   boulevard + a few common species.
3. In **Storage** two buckets: `tree-photos` and `tree-models`
   (both public-read).
4. In **Settings → API**, project URL and anon public key.

## 2. Frontend

`index.html` to real data

## 3. Optional: mirror into OpenStreetMap



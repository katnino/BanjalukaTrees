# Drveće Banjaluke — starter kit

A free-stack starting point for a tree map of Banjaluka, beginning with
Bulevar Živojina Mišića. Includes:

- `schema.sql` — Postgres/PostGIS schema, ready to run in Supabase
- `index.html` — a working single-file demo (map + tree detail panel +
  3D model viewer), currently wired to mock data so you can see it run
  immediately with zero setup

## 0. Try it right now

Just open `index.html` in a browser (or double-click it). No build step,
no install. It's using placeholder tree data for six trees along the
boulevard so you can see the whole flow: map pins → click a tree →
detail panel with stats → 3D model viewer (one demo tree has a sample
`.glb` wired up so you can see how the viewer behaves).

## 1. Set up the free backend (Supabase)

1. Create a free project at supabase.com (free tier: 500MB database,
   1GB file storage — plenty for a while).
2. In the SQL editor, run `schema.sql`. This creates the tables,
   PostGIS geography column, row-level security policies, and seeds
   your boulevard + a few common species.
3. In **Storage**, create two buckets: `tree-photos` and `tree-models`
   (both public-read).
4. In **Settings → API**, copy your project URL and anon public key.

## 2. Connect `index.html` to real data

Open `index.html` and find this near the top of the first `<script type="module">` block:

```js
const SUPABASE_URL = 'YOUR_PROJECT_URL';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

Paste in the values from Supabase → Settings → API. That's it — the app
already knows how to fetch from the `tree_map` view (created at the
bottom of `schema.sql`), map it into the shape the UI expects, and
build the model URL from Supabase Storage automatically. Until you
fill these in, the app keeps running on the built-in mock data, so
nothing breaks either way.

If the fetch fails for any reason (wrong key, RLS blocking something),
it falls back to mock data automatically and logs the real error to
the browser console — check there first if trees don't show up.

## 3. Deploy for free

Drag the folder into **Netlify Drop** (netlify.com/drop) or connect the
repo to **Vercel** — both have generous free static-hosting tiers and
this app has no server component, so that's all you need.

## 4. The 3D scanning workflow (for you + volunteers)

Pick per-tree based on available hardware:

| Method | Hardware | Tool (free) | Output |
|---|---|---|---|
| Video → NeRF | Any phone, 20-30s orbit video | Luma AI (free tier) | glTF/GLB |
| Photogrammetry | Any phone, 40-80 overlapping photos | Meshroom / COLMAP (open-source, run on a laptop) | OBJ/GLB |
| LiDAR scan | iPhone/iPad Pro | Polycam or "3D Scanner App" (free tier) | GLB/USDZ |

Whatever the source, convert/export to **`.glb`** — that's what
`<model-viewer>` in `index.html` reads directly, no extra conversion
needed on your end.

Suggested volunteer flow, kept low-friction:
1. Volunteer picks an un-scanned tree from a shared list (a simple
   spreadsheet or a "needs scan" filter on the map works fine at
   first).
2. They film the orbit video or take the photo set, and log the
   `tree_id` it belongs to.
3. You (or anyone comfortable with it) run the video/photos through
   the chosen tool and upload the resulting `.glb` to the
   `tree-models` bucket, then insert a row in `tree_scan`.

Once this gets more than a couple of contributors, it's worth adding a
simple "pending scans" queue table so people don't duplicate work —
happy to sketch that out when you get there.

## 5. Optional: mirror into OpenStreetMap

Tag scanned trees in OSM (`natural=tree`) too, and store the
resulting OSM node id in `tree.osm_node_id`. This gets your basic
inventory onto a public, permanent map independent of your own app,
and free basemap tiles that already include your trees.

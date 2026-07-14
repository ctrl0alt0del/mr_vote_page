# Marvel Rivals Hero Vote

A React SPA for Marvel Rivals hero voting across dynamic categories. The frontend is static and ready for GitHub Pages; ranked-list and tier-list ballots persist in Supabase Postgres.

## Stack

- React + Vite
- Supabase JS client
- Supabase Postgres, RLS, public category CRUD, ranked ballots, and tier ballots
- GitHub Pages deployment with GitHub Actions

## Local Setup

1. Create a free Supabase project.
2. Open the Supabase SQL editor and run `supabase/schema.sql`.
3. Copy `.env.example` to `.env`.
4. Fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Run the app:

```bash
npm install
npm run dev
```

## GitHub Pages

1. Push this project to a GitHub repository.
2. In GitHub, open Settings > Secrets and variables > Actions.
3. Add these repository secrets:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

4. Open Settings > Pages and set Source to GitHub Actions.
5. Push to `main`, or run the workflow manually.

The Vite config uses `base: './'`, so the built app works under a GitHub Pages repository path.

## Supabase Notes

When defining a category, choose whether it is a rank-list poll or tier-list poll, then choose which heroes can participate. Tier-list polls support custom tier names and vertical or horizontal board layout. Presets cover all heroes and each role, and the icon grid allows manual refinement.

Before voting, the user chooses one category. Rank-list polls open a draggable ordered list and store submissions through `submit_ranked_ballot(category_id, voter_key, hero_ids)`. Tier-list polls open custom tier buckets with a draggable hero pool and store submissions through `submit_tier_ballot(category_id, voter_key, hero_ids, tier_keys)`.

The app hides results during voting. For analysis, query `category_rankings`. Ranked polls use average Dowdall scoring. Tier polls are categorical: each hero is assigned to the most common submitted tier, and the displayed percentage is that tier's vote share.

Categories are editable from the browser. The included RLS policies intentionally allow public category create, update, and delete so you can manage categories from the SPA. Add Supabase Auth and stricter policies before sharing the manager controls with untrusted users.

## Updating An Existing Project

If you already ran the earlier schemas, push the pending migrations:

```bash
npx supabase db push
```

The latest migration is `supabase/migrations/20260714130000_custom_tier_modes.sql`.

## Analysis

Run `supabase/analysis.sql` in the Supabase SQL editor to get:

- ranked heroes or most common tier by category
- submitted ballots by category
- highest scoring or highest occurrence heroes by category
- ballot submissions over time

## Roster

`supabase/schema.sql` is seeded with hero IDs, roles, and portrait URLs extracted from the official Marvel Rivals heroes page on 2026-07-08. Re-run the seed section after editing it if the roster changes.

This fan poll is not affiliated with Marvel, NetEase, or Marvel Rivals.

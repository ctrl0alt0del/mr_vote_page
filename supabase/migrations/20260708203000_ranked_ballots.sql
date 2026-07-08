create table if not exists public.ranked_ballots (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (category_id, voter_key)
);

create table if not exists public.ranked_ballot_items (
  ballot_id uuid not null references public.ranked_ballots(id) on delete cascade,
  hero_id uuid not null references public.heroes(id) on delete cascade,
  rank_position integer not null check (rank_position > 0),
  created_at timestamptz not null default now(),
  primary key (ballot_id, hero_id),
  unique (ballot_id, rank_position)
);

alter table public.ranked_ballots enable row level security;
alter table public.ranked_ballot_items enable row level security;

drop policy if exists "Public can read ranked ballots" on public.ranked_ballots;
create policy "Public can read ranked ballots"
on public.ranked_ballots for select
to anon, authenticated
using (true);

drop policy if exists "Public can create ranked ballots" on public.ranked_ballots;
create policy "Public can create ranked ballots"
on public.ranked_ballots for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update ranked ballots" on public.ranked_ballots;
create policy "Public can update ranked ballots"
on public.ranked_ballots for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Public can read ranked ballot items" on public.ranked_ballot_items;
create policy "Public can read ranked ballot items"
on public.ranked_ballot_items for select
to anon, authenticated
using (true);

drop policy if exists "Public can create ranked ballot items" on public.ranked_ballot_items;
create policy "Public can create ranked ballot items"
on public.ranked_ballot_items for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can delete ranked ballot items" on public.ranked_ballot_items;
create policy "Public can delete ranked ballot items"
on public.ranked_ballot_items for delete
to anon, authenticated
using (true);

create or replace function public.submit_ranked_ballot(
  p_category_id uuid, p_voter_key text, p_hero_ids uuid[]
) returns void language plpgsql security definer set search_path = public as $$
declare v_ballot_id uuid;
begin
  insert into public.ranked_ballots (category_id, voter_key, updated_at) values (p_category_id, p_voter_key, now())
  on conflict (category_id, voter_key) do update set updated_at = now() returning id into v_ballot_id;
  delete from public.ranked_ballot_items where ballot_id = v_ballot_id;
  insert into public.ranked_ballot_items (ballot_id, hero_id, rank_position)
  select v_ballot_id, hero_id, rank_position::int from unnest(p_hero_ids) with ordinality as ranked(hero_id, rank_position);
end;
$$;

drop view if exists public.category_rankings;

create view public.category_rankings as
with eligible_counts as (
  select category_id, count(*)::int as eligible_count
  from public.category_heroes
  group by category_id
),
hero_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, count(rbi.hero_id)::int as ballots,
    coalesce(sum(ec.eligible_count - rbi.rank_position + 1), 0)::int as points,
    coalesce(round(avg(rbi.rank_position), 2), 0) as average_rank
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join eligible_counts ec on ec.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  left join public.ranked_ballots rb on rb.category_id = c.id
  left join public.ranked_ballot_items rbi on rbi.ballot_id = rb.id
    and rbi.hero_id = h.id
  group by c.id, c.name, h.id, h.name, h.role, h.image_url
)
select category_id, category_name, hero_id, name, role, image_url,
  ballots, points, average_rank,
  rank() over (
    partition by category_id
    order by points desc, average_rank asc, ballots desc, name asc
  )::int as rank
from hero_scores;

grant select, insert, update on table public.ranked_ballots to anon, authenticated;
grant select, insert, delete on table public.ranked_ballot_items to anon, authenticated;
grant execute on function public.submit_ranked_ballot(uuid, text, uuid[]) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;

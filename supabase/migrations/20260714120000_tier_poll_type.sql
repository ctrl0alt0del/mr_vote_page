alter table public.categories
add column if not exists poll_type text not null default 'ranked';

alter table public.categories
drop constraint if exists categories_poll_type_check;

alter table public.categories
add constraint categories_poll_type_check
check (poll_type in ('ranked', 'tier'));

create table if not exists public.tier_ballots (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (category_id, voter_key)
);

create table if not exists public.tier_ballot_items (
  ballot_id uuid not null references public.tier_ballots(id) on delete cascade,
  hero_id uuid not null references public.heroes(id) on delete cascade,
  tier_key text not null check (tier_key in ('s', 'a', 'b', 'c', 'd')),
  created_at timestamptz not null default now(),
  primary key (ballot_id, hero_id)
);

alter table public.tier_ballots enable row level security;
alter table public.tier_ballot_items enable row level security;

drop policy if exists "Public can read tier ballots" on public.tier_ballots;
create policy "Public can read tier ballots"
on public.tier_ballots for select
to anon, authenticated
using (true);

drop policy if exists "Public can create tier ballots" on public.tier_ballots;
create policy "Public can create tier ballots"
on public.tier_ballots for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update tier ballots" on public.tier_ballots;
create policy "Public can update tier ballots"
on public.tier_ballots for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Public can read tier ballot items" on public.tier_ballot_items;
create policy "Public can read tier ballot items"
on public.tier_ballot_items for select
to anon, authenticated
using (true);

drop policy if exists "Public can create tier ballot items" on public.tier_ballot_items;
create policy "Public can create tier ballot items"
on public.tier_ballot_items for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can delete tier ballot items" on public.tier_ballot_items;
create policy "Public can delete tier ballot items"
on public.tier_ballot_items for delete
to anon, authenticated
using (true);

create or replace function public.submit_tier_ballot(
  p_category_id uuid, p_voter_key text, p_hero_ids uuid[], p_tier_keys text[]
) returns void language plpgsql security definer set search_path = public as $$
declare v_ballot_id uuid;
begin
  if array_length(p_hero_ids, 1) is distinct from array_length(p_tier_keys, 1) then
    raise exception 'Hero and tier arrays must have the same length';
  end if;
  insert into public.tier_ballots (category_id, voter_key, updated_at) values (p_category_id, p_voter_key, now())
  on conflict (category_id, voter_key) do update set updated_at = now() returning id into v_ballot_id;
  delete from public.tier_ballot_items where ballot_id = v_ballot_id;
  insert into public.tier_ballot_items (ballot_id, hero_id, tier_key)
  select v_ballot_id, hero_id, tier_key from unnest(p_hero_ids, p_tier_keys) as tiered(hero_id, tier_key);
end;
$$;

create or replace function public.tier_score(tier_key text)
returns numeric language sql immutable as $$
  select case tier_key when 's' then 1 when 'a' then 0.8 when 'b' then 0.6 when 'c' then 0.4 when 'd' then 0.2 else null end
$$;

create or replace function public.tier_rank(tier_key text)
returns numeric language sql immutable as $$
  select case tier_key when 's' then 1 when 'a' then 2 when 'b' then 3 when 'c' then 4 when 'd' then 5 else null end
$$;

drop view if exists public.category_rankings;

create view public.category_rankings as
with ranked_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, count(rb.id)::int as ballots,
    coalesce(round(sum(1::numeric / rbi.rank_position) / nullif(count(rb.id), 0), 4), 0) as points,
    coalesce(round(avg(rbi.rank_position), 2), 0) as average_rank
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  left join public.ranked_ballots rb on rb.category_id = c.id
  left join public.ranked_ballot_items rbi on rbi.ballot_id = rb.id and rbi.hero_id = h.id
  where c.poll_type = 'ranked'
  group by c.id, c.name, h.id, h.name, h.role, h.image_url
),
tier_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, count(tb.id)::int as ballots,
    coalesce(round(sum(public.tier_score(tbi.tier_key)) / nullif(count(tb.id), 0), 4), 0) as points,
    coalesce(round(avg(public.tier_rank(tbi.tier_key)), 2), 0) as average_rank
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  left join public.tier_ballots tb on tb.category_id = c.id
  left join public.tier_ballot_items tbi on tbi.ballot_id = tb.id and tbi.hero_id = h.id
  where c.poll_type = 'tier'
  group by c.id, c.name, h.id, h.name, h.role, h.image_url
),
hero_scores as (
  select * from ranked_scores
  union all
  select * from tier_scores
)
select category_id, category_name, hero_id, name, role, image_url,
  ballots, points, average_rank,
  rank() over (
    partition by category_id
    order by points desc, average_rank asc, ballots desc, name asc
  )::int as rank
from hero_scores;

grant select, insert, update on table public.tier_ballots to anon, authenticated;
grant select, insert, delete on table public.tier_ballot_items to anon, authenticated;
grant execute on function public.tier_score(text) to anon, authenticated;
grant execute on function public.tier_rank(text) to anon, authenticated;
grant execute on function public.submit_tier_ballot(uuid, text, uuid[], text[]) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;

notify pgrst, 'reload schema';

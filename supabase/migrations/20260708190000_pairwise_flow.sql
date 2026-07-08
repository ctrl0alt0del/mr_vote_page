create table if not exists public.pairwise_comparisons (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  hero_a_id uuid not null references public.heroes(id) on delete cascade,
  hero_b_id uuid not null references public.heroes(id) on delete cascade,
  winner_hero_id uuid not null references public.heroes(id) on delete cascade,
  loser_hero_id uuid not null references public.heroes(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pairwise_hero_order check (hero_a_id < hero_b_id),
  constraint pairwise_distinct_pick check (winner_hero_id <> loser_hero_id),
  constraint pairwise_voter_key_length check (char_length(voter_key) between 24 and 128),
  constraint pairwise_unique_voter_pair unique (voter_key, category_id, hero_a_id, hero_b_id)
);

alter table public.pairwise_comparisons enable row level security;

drop policy if exists "No public pairwise table reads" on public.pairwise_comparisons;
create policy "No public pairwise table reads"
on public.pairwise_comparisons for select
to anon, authenticated
using (false);

drop trigger if exists set_pairwise_updated_at on public.pairwise_comparisons;
create trigger set_pairwise_updated_at
before update on public.pairwise_comparisons
for each row execute function public.touch_updated_at();

create or replace function public.submit_pairwise_choice(
  p_category_id uuid,
  p_winner_hero_id uuid,
  p_loser_hero_id uuid,
  p_voter_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_voter_key is null or char_length(trim(p_voter_key)) < 24 then
    raise exception 'Invalid voter key';
  end if;
  if p_winner_hero_id = p_loser_hero_id then
    raise exception 'Pick two different heroes';
  end if;
  if not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'Unknown category';
  end if;
  insert into public.pairwise_comparisons (
    category_id, hero_a_id, hero_b_id, winner_hero_id, loser_hero_id, voter_key
  )
  values (
    p_category_id,
    least(p_winner_hero_id, p_loser_hero_id),
    greatest(p_winner_hero_id, p_loser_hero_id),
    p_winner_hero_id,
    p_loser_hero_id,
    p_voter_key
  )
  on conflict (voter_key, category_id, hero_a_id, hero_b_id) do update
  set winner_hero_id = excluded.winner_hero_id,
    loser_hero_id = excluded.loser_hero_id;
end;
$$;

create or replace function public.get_next_pairwise_matchup(p_voter_key text)
returns table (
  category_id uuid,
  category_name text,
  category_description text,
  left_hero_id uuid,
  left_name text,
  left_role text,
  left_image_url text,
  right_hero_id uuid,
  right_name text,
  right_role text,
  right_image_url text,
  remaining_in_category integer,
  total_in_category integer,
  remaining_overall integer,
  total_overall integer
)
language sql
security definer
set search_path = public
as $$
with pair_totals as (
  select (count(*) * (count(*) - 1) / 2)::int as total from public.heroes
),
category_pool as (
  select c.id, c.name, c.description, pt.total as total_in_category
  from public.categories c cross join pair_totals pt
  where c.is_active = true
),
category_progress as (
  select cp.*, (cp.total_in_category - count(pc.id))::int as remaining
  from category_pool cp
  left join public.pairwise_comparisons pc on pc.category_id = cp.id
    and pc.voter_key = p_voter_key
  group by cp.id, cp.name, cp.description, cp.total_in_category
),
chosen_category as (
  select * from category_progress where remaining > 0 order by random() limit 1
),
chosen_pair as (
  select h1.id as left_hero_id, h1.name as left_name, h1.role as left_role,
    h1.image_url as left_image_url, h2.id as right_hero_id, h2.name as right_name,
    h2.role as right_role, h2.image_url as right_image_url
  from public.heroes h1
  join public.heroes h2 on h1.id < h2.id
  cross join chosen_category cc
  where not exists (
    select 1 from public.pairwise_comparisons pc
    where pc.voter_key = p_voter_key and pc.category_id = cc.id
      and pc.hero_a_id = h1.id and pc.hero_b_id = h2.id
  )
  order by random() limit 1
),
oriented_pair as (
  select *, random() < 0.5 as flip from chosen_pair
),
overall as (
  select coalesce(sum(remaining), 0)::int as remaining,
    coalesce(sum(total_in_category), 0)::int as total
  from category_progress
)
select cc.id, cc.name, cc.description,
  case when op.flip then op.right_hero_id else op.left_hero_id end,
  case when op.flip then op.right_name else op.left_name end,
  case when op.flip then op.right_role else op.left_role end,
  case when op.flip then op.right_image_url else op.left_image_url end,
  case when op.flip then op.left_hero_id else op.right_hero_id end,
  case when op.flip then op.left_name else op.right_name end,
  case when op.flip then op.left_role else op.right_role end,
  case when op.flip then op.left_image_url else op.right_image_url end,
  cc.remaining, cc.total_in_category,
  overall.remaining, overall.total
from chosen_category cc cross join oriented_pair op cross join overall;
$$;

create or replace view public.category_rankings as
with hero_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url,
    count(pc.id) filter (where pc.winner_hero_id = h.id)::int as wins,
    count(pc.id) filter (where pc.loser_hero_id = h.id)::int as losses
  from public.categories c
  cross join public.heroes h
  left join public.pairwise_comparisons pc on pc.category_id = c.id
    and (pc.winner_hero_id = h.id or pc.loser_hero_id = h.id)
  group by c.id, c.name, h.id, h.name, h.role, h.image_url
)
select category_id, category_name, hero_id, name, role, image_url, wins,
  losses, wins + losses as comparisons,
  round((wins + 1)::numeric / nullif(wins + losses + 2, 0), 4) as score,
  rank() over (
    partition by category_id
    order by (wins - losses) desc, wins desc,
      round((wins + 1)::numeric / nullif(wins + losses + 2, 0), 4) desc,
      name asc
  )::int as rank
from hero_scores;

grant execute on function public.submit_pairwise_choice(uuid, uuid, uuid, text) to anon, authenticated;
grant execute on function public.get_next_pairwise_matchup(text) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;
revoke all on table public.pairwise_comparisons from anon, authenticated;

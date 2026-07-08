create table if not exists public.category_heroes (
  category_id uuid not null references public.categories(id) on delete cascade,
  hero_id uuid not null references public.heroes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (category_id, hero_id)
);

alter table public.category_heroes enable row level security;

drop policy if exists "Public can read category heroes" on public.category_heroes;
create policy "Public can read category heroes"
on public.category_heroes for select
to anon, authenticated
using (true);

drop policy if exists "Public can create category heroes" on public.category_heroes;
create policy "Public can create category heroes"
on public.category_heroes for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can delete category heroes" on public.category_heroes;
create policy "Public can delete category heroes"
on public.category_heroes for delete
to anon, authenticated
using (true);

insert into public.category_heroes (category_id, hero_id)
select c.id, h.id
from public.categories c
cross join public.heroes h
where not exists (
  select 1 from public.category_heroes ch
  where ch.category_id = c.id
)
on conflict do nothing;

drop function if exists public.get_next_pairwise_matchup(text);
drop function if exists public.get_next_pairwise_matchup(text, uuid[]);

create or replace function public.eligible_pair(
  p_category_id uuid,
  p_hero_a_id uuid,
  p_hero_b_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.category_heroes a
    join public.category_heroes b on b.category_id = a.category_id
    where a.category_id = p_category_id
      and a.hero_id = p_hero_a_id
      and b.hero_id = p_hero_b_id
  );
$$;

create or replace function public.compared_pair(
  p_voter_key text,
  p_category_id uuid,
  p_hero_a_id uuid,
  p_hero_b_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pairwise_comparisons pc
    where pc.voter_key = p_voter_key
      and pc.category_id = p_category_id
      and pc.hero_a_id = least(p_hero_a_id, p_hero_b_id)
      and pc.hero_b_id = greatest(p_hero_a_id, p_hero_b_id)
  );
$$;

create or replace function public.get_next_pairwise_matchup(
  p_voter_key text,
  p_category_ids uuid[]
)
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
with eligible_counts as (
  select category_id, count(*)::int as hero_count
  from public.category_heroes
  group by category_id
),
category_pool as (
  select c.id, c.name, c.description,
    (ec.hero_count * (ec.hero_count - 1) / 2)::int as total_in_category
  from public.categories c
  join eligible_counts ec on ec.category_id = c.id
  where c.is_active = true and c.id = any(p_category_ids)
),
category_progress as (
  select cp.*, (cp.total_in_category - count(pc.id))::int as remaining
  from category_pool cp
  left join public.pairwise_comparisons pc on pc.category_id = cp.id
    and pc.voter_key = p_voter_key
    and eligible_pair(cp.id, pc.hero_a_id, pc.hero_b_id)
  group by cp.id, cp.name, cp.description, cp.total_in_category
),
chosen_category as (
  select * from category_progress where remaining > 0 order by random() limit 1
),
chosen_pair as (
  select h1.id as left_hero_id, h1.name as left_name, h1.role as left_role,
    h1.image_url as left_image_url, h2.id as right_hero_id, h2.name as right_name,
    h2.role as right_role, h2.image_url as right_image_url
  from public.category_heroes ch1
  join public.category_heroes ch2 on ch2.category_id = ch1.category_id
    and ch1.hero_id < ch2.hero_id
  join public.heroes h1 on h1.id = ch1.hero_id
  join public.heroes h2 on h2.id = ch2.hero_id
  cross join chosen_category cc
  where ch1.category_id = cc.id
    and not compared_pair(p_voter_key, cc.id, h1.id, h2.id)
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
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  left join public.pairwise_comparisons pc on pc.category_id = c.id
    and (pc.winner_hero_id = h.id or pc.loser_hero_id = h.id)
    and eligible_pair(c.id, pc.hero_a_id, pc.hero_b_id)
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

grant select, insert, delete on table public.category_heroes to anon, authenticated;
grant execute on function public.get_next_pairwise_matchup(text, uuid[]) to anon, authenticated;
grant execute on function public.eligible_pair(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.compared_pair(text, uuid, uuid, uuid) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;

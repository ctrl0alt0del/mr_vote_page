drop function if exists public.get_next_pairwise_matchup(text);
drop function if exists public.get_next_pairwise_matchup(text, uuid[]);

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
with pair_totals as (
  select (count(*) * (count(*) - 1) / 2)::int as total from public.heroes
),
category_pool as (
  select c.id, c.name, c.description, pt.total as total_in_category
  from public.categories c cross join pair_totals pt
  where c.is_active = true and c.id = any(p_category_ids)
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

grant execute on function public.get_next_pairwise_matchup(text, uuid[]) to anon, authenticated;

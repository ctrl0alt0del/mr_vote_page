alter table public.categories
add column if not exists tier_orientation text not null default 'vertical';

alter table public.categories
drop constraint if exists categories_tier_orientation_check;

alter table public.categories
add constraint categories_tier_orientation_check
check (tier_orientation in ('vertical', 'horizontal'));

alter table public.categories
add column if not exists tier_config jsonb not null default
'[{"key":"s","label":"S"},{"key":"a","label":"A"},{"key":"b","label":"B"},{"key":"c","label":"C"},{"key":"d","label":"D"}]'::jsonb;

alter table public.tier_ballot_items
drop constraint if exists tier_ballot_items_tier_key_check;

drop view if exists public.category_rankings;

create view public.category_rankings as
with ranked_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, count(rb.id)::int as ballots,
    coalesce(round(sum(1::numeric / rbi.rank_position) / nullif(count(rb.id), 0), 4), 0) as points,
    coalesce(round(avg(rbi.rank_position), 2), 0) as average_rank,
    'ranked'::text as poll_type, null::text as tier_key, null::text as tier_label,
    null::int as tier_votes, null::int as tier_order
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  left join public.ranked_ballots rb on rb.category_id = c.id
  left join public.ranked_ballot_items rbi on rbi.ballot_id = rb.id and rbi.hero_id = h.id
  where c.poll_type = 'ranked'
  group by c.id, c.name, h.id, h.name, h.role, h.image_url
),
tier_counts as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, tier_item.item ->> 'key' as tier_key,
    tier_item.item ->> 'label' as tier_label, tier_item.ordinality::int as tier_order,
    count(tbi.hero_id)::int as tier_votes
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  cross join lateral jsonb_array_elements(c.tier_config) with ordinality as tier_item(item, ordinality)
  left join public.tier_ballots tb on tb.category_id = c.id
  left join public.tier_ballot_items tbi on tbi.ballot_id = tb.id and tbi.hero_id = h.id and tbi.tier_key = (tier_item.item ->> 'key')
  where c.poll_type = 'tier'
  group by c.id, c.name, h.id, h.name, h.role, h.image_url, tier_item.item, tier_item.ordinality
),
tier_modes as (
  select *, sum(tier_votes) over (partition by category_id, hero_id)::int as total_votes
  from tier_counts
),
tier_scores as (
  select distinct on (category_id, hero_id) category_id, category_name, hero_id,
    name, role, image_url, total_votes as ballots,
    coalesce(round(tier_votes::numeric / nullif(total_votes, 0), 4), 0) as points,
    tier_order::numeric as average_rank, 'tier'::text as poll_type,
    case when total_votes > 0 then tier_key end as tier_key,
    case when total_votes > 0 then tier_label end as tier_label,
    case when total_votes > 0 then tier_votes else 0 end as tier_votes,
    case when total_votes > 0 then tier_order else 9999 end as tier_order
  from tier_modes
  order by category_id, hero_id, tier_votes desc, tier_order asc, name asc
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
    order by tier_order asc nulls last, points desc, average_rank asc, ballots desc, name asc
  )::int as rank,
  poll_type, tier_key, tier_label, tier_votes, tier_order
from hero_scores;

grant select on table public.category_rankings to anon, authenticated;

notify pgrst, 'reload schema';

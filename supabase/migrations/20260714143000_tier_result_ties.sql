drop view if exists public.category_tier_winning_tiers;

create view public.category_tier_winning_tiers as
with tier_counts as (
  select c.id as category_id, h.id as hero_id,
    tier_item.item ->> 'key' as tier_key,
    tier_item.item ->> 'label' as tier_label,
    tier_item.ordinality::int as tier_order,
    count(tbi.hero_id)::int as tier_votes
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
  join public.heroes h on h.id = ch.hero_id
  cross join lateral jsonb_array_elements(c.tier_config) with ordinality as tier_item(item, ordinality)
  left join public.tier_ballots tb on tb.category_id = c.id
  left join public.tier_ballot_items tbi
    on tbi.ballot_id = tb.id
    and tbi.hero_id = h.id
    and tbi.tier_key = (tier_item.item ->> 'key')
  where c.poll_type = 'tier'
  group by c.id, h.id, tier_item.item, tier_item.ordinality
),
tier_modes as (
  select *,
    sum(tier_votes) over (partition by category_id, hero_id)::int as total_votes,
    max(tier_votes) over (partition by category_id, hero_id)::int as winning_votes
  from tier_counts
),
tier_winners as (
  select *,
    count(*) over (partition by category_id, hero_id)::int as winning_tier_count
  from tier_modes
  where total_votes > 0 and tier_votes = winning_votes
)
select category_id, hero_id, tier_key, tier_label, tier_order,
  tier_votes, total_votes as ballots,
  coalesce(round(tier_votes::numeric / nullif(total_votes, 0), 4), 0) as points,
  (winning_tier_count > 1) as tier_is_tied
from tier_winners;

grant select on table public.category_tier_winning_tiers to anon, authenticated;

notify pgrst, 'reload schema';

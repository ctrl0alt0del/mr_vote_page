-- Hero list per category using rank-list score or tier-list mode.
select category_name, rank, name, role, points, tier_label, tier_votes, ballots
from public.category_rankings
order by category_name asc, rank asc, name asc;

-- Submitted ballots by category.
select c.name as category, c.poll_type, coalesce(rb.ballots, 0) + coalesce(tb.ballots, 0) as submitted_ballots
from public.categories c
left join (select category_id, count(*) as ballots from public.ranked_ballots group by category_id) rb on rb.category_id = c.id
left join (select category_id, count(*) as ballots from public.tier_ballots group by category_id) tb on tb.category_id = c.id
order by c.name;

-- Highest scoring ranked heroes or strongest tier-mode heroes by category.
select category_name, name, role, points, tier_label, tier_votes, ballots
from public.category_rankings
where ballots > 0
order by category_name asc, points desc, rank asc;

-- Ballot submissions over time.
select category, poll_type, day, count(*) as ballots
from (
  select c.name as category, c.poll_type, date_trunc('day', rb.updated_at) as day from public.ranked_ballots rb join public.categories c on c.id = rb.category_id
  union all
  select c.name as category, c.poll_type, date_trunc('day', tb.updated_at) as day from public.tier_ballots tb join public.categories c on c.id = tb.category_id
) submitted
group by category, poll_type, day
order by day, category;

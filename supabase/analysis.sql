-- Ranked hero list per category using Dowdall points: 1 / rank position.
select category_name, rank, name, role, points, average_rank, ballots
from public.category_rankings
order by category_name asc, rank asc, name asc;

-- Submitted ballots by category.
select c.name as category, count(rb.id) as submitted_ballots
from public.categories c
left join public.ranked_ballots rb on rb.category_id = c.id
group by c.id, c.name
order by c.name;

-- Highest Dowdall scoring heroes by category.
select category_name, name, role, points, average_rank, ballots
from public.category_rankings
where ballots > 0
order by category_name asc, points desc, average_rank asc;

-- Ballot submissions over time.
select c.name as category, date_trunc('day', rb.updated_at) as day, count(*) as ballots
from public.ranked_ballots rb
join public.categories c on c.id = rb.category_id
group by c.name, day
order by day, c.name;

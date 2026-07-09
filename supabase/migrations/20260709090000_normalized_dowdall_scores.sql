drop view if exists public.category_rankings;

create view public.category_rankings as
with hero_scores as (
  select c.id as category_id, c.name as category_name, h.id as hero_id,
    h.name, h.role, h.image_url, count(rb.id)::int as ballots,
    coalesce(round(sum(1::numeric / rbi.rank_position) / nullif(count(rb.id), 0), 4), 0) as points,
    coalesce(round(avg(rbi.rank_position), 2), 0) as average_rank
  from public.categories c
  join public.category_heroes ch on ch.category_id = c.id
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

grant select on table public.category_rankings to anon, authenticated;

notify pgrst, 'reload schema';

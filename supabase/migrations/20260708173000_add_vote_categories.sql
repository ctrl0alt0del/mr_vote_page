create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.categories (id, name, description, sort_order)
values (
  '11111111-1111-4111-8111-111111111111',
  'Overall Favorite',
  'The default all-heroes poll.',
  0
)
on conflict (id) do nothing;

alter table public.categories enable row level security;

drop policy if exists "Public can read categories" on public.categories;
create policy "Public can read categories"
on public.categories for select
to anon, authenticated
using (true);

drop policy if exists "Public can create categories" on public.categories;
create policy "Public can create categories"
on public.categories for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update categories" on public.categories;
create policy "Public can update categories"
on public.categories for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Public can delete categories" on public.categories;
create policy "Public can delete categories"
on public.categories for delete
to anon, authenticated
using (true);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_category_updated_at on public.categories;
create trigger set_category_updated_at
before update on public.categories
for each row execute function public.touch_updated_at();

alter table public.votes add column if not exists category_id uuid;

update public.votes
set category_id = '11111111-1111-4111-8111-111111111111'
where category_id is null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'votes_category_id_fkey'
  ) then
    alter table public.votes
    add constraint votes_category_id_fkey
    foreign key (category_id)
    references public.categories(id)
    on delete cascade;
  end if;
end;
$$;

alter table public.votes alter column category_id set not null;
alter table public.votes drop constraint if exists votes_voter_key_unique;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'votes_voter_category_unique'
  ) then
    alter table public.votes
    add constraint votes_voter_category_unique
    unique (voter_key, category_id);
  end if;
end;
$$;

drop view if exists public.hero_vote_results;
drop function if exists public.cast_vote(uuid, text);

create or replace view public.hero_vote_results as
select
  c.id as category_id,
  c.name as category_name,
  h.id as hero_id,
  h.name,
  h.role,
  h.image_url,
  count(v.id)::int as votes
from public.categories c
cross join public.heroes h
left join public.votes v on v.hero_id = h.id
  and v.category_id = c.id
where c.is_active = true
group by c.id, c.name, c.sort_order, h.id, h.name, h.role, h.image_url
order by c.sort_order asc, votes desc, h.name asc;

create or replace function public.cast_vote(
  p_hero_id uuid,
  p_category_id uuid,
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
  if not exists (select 1 from public.heroes where id = p_hero_id) then
    raise exception 'Unknown hero';
  end if;
  if not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'Unknown category';
  end if;
  insert into public.votes (hero_id, category_id, voter_key)
  values (p_hero_id, p_category_id, p_voter_key)
  on conflict (voter_key, category_id) do update
  set hero_id = excluded.hero_id;
end;
$$;

grant select, insert, update, delete on table public.categories to anon, authenticated;
grant select on table public.hero_vote_results to anon, authenticated;
grant execute on function public.cast_vote(uuid, uuid, text) to anon, authenticated;

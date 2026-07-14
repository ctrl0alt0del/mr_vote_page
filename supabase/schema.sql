create extension if not exists pgcrypto;

create table if not exists public.heroes (
  id uuid primary key,
  name text not null unique,
  role text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  hero_id uuid not null references public.heroes(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint votes_voter_category_unique unique (voter_key, category_id),
  constraint votes_voter_key_length check (char_length(voter_key) between 24 and 128)
);

alter table public.heroes enable row level security;
alter table public.categories enable row level security;
alter table public.votes enable row level security;

drop policy if exists "Public can read heroes" on public.heroes;
create policy "Public can read heroes"
on public.heroes for select
to anon, authenticated
using (true);

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

insert into public.categories (id, name, description, sort_order)
values (
  '11111111-1111-4111-8111-111111111111',
  'Overall Favorite',
  'The default all-heroes poll.',
  0
)
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  sort_order = excluded.sort_order;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_vote_updated_at on public.votes;
create trigger set_vote_updated_at
before update on public.votes
for each row execute function public.touch_updated_at();

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

grant usage on schema public to anon, authenticated;
grant select on table public.heroes to anon, authenticated;
grant select, insert, update, delete on table public.categories to anon, authenticated;
grant select on table public.hero_vote_results to anon, authenticated;
grant execute on function public.cast_vote(uuid, uuid, text) to anon, authenticated;
revoke all on table public.votes from anon, authenticated;

insert into public.heroes (id, name, role, image_url) values
('ef4511de-a2ff-43f0-b061-d915f0ccb37d', 'ADAM WARLOCK', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_21.png'),
('03af29d0-1a53-4077-9062-8201ed327635', 'ANGELA', 'VANGUARD', 'https://r.res.easebar.com/pic/20250912/cf044a85-7bec-4bc1-8a32-6fcd06c25480.png'),
('84b3b29a-326a-443d-bf18-4ebb9f2948fc', 'BLACK CAT', 'DUELIST', 'https://r.res.easebar.com/pic/20260417/9aad3814-3985-4e14-ab1d-a2813bcf6850.png'),
('fa01bc79-aba9-4559-9a0e-fc4fb5666f0a', 'BLACK PANTHER', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_1.png'),
('baa0fe39-41ff-42f3-b48f-3e453317503a', 'BLACK WIDOW', 'DUELIST', 'https://r.res.easebar.com/pic/20241204/f8f32a42-a17a-482c-8da0-cfe273b7da77.png'),
('4bb813d7-30ab-4c36-bd05-b9d299e4c1e3', 'BLADE', 'DUELIST', 'https://r.res.easebar.com/pic/20250808/8c35438e-3359-4ad9-8d49-2e1c6a29d463.png'),
('b3e3bc0b-0a15-4fa8-8139-e08f7fcd9beb', 'CAPTAIN AMERICA', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_24.png'),
('5b5a8c7a-c9c0-4f4c-89a3-dae465db8c7f', 'CLOAK&DAGGER', 'STRATEGIST', 'https://r.res.easebar.com/pic/20241204/6fe1a0c6-8d0f-4674-872a-f7b54f0dd901.png'),
('4b46591b-a837-43ba-ae41-571de988c190', 'CYCLOPS', 'DUELIST', 'https://r.res.easebar.com/pic/20260612/8cf04b13-2e3c-49bc-8f90-000732c94f43.png'),
('043108d4-fd6b-4884-aee1-1ccbefb79790', 'Daredevil', 'DUELIST', 'https://r.res.easebar.com/pic/20251010/620b1cc1-a00d-4ba3-9867-a7093bc500c6.png'),
('3ef6b679-d1b4-4757-a8ee-0ea53379c754', 'DEADPOOL', 'VANGUARD DUELIST STRATEGIST', 'https://r.res.easebar.com/pic/20260116/2d6d1d2b-281f-4efd-b252-d792a11fce98.png'),
('d579e90a-46a7-45fd-975f-4d63c7755d27', 'DEVIL DINOSAUR', 'VANGUARD', 'https://r.res.easebar.com/pic/20260515/84181e94-e504-48a8-94e2-6002678fb4dd.png'),
('692c786c-08f4-4502-9803-a55f3bc8f83b', 'DOCTOR STRANGE', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_2.png'),
('91b586e3-4d55-455c-bd7d-69fbe0563d26', 'ELSA BLOODSTONE', 'DUELIST', 'https://r.res.easebar.com/pic/20260213/76cb7d5d-e120-496e-acb8-bbd4af0e3313.png'),
('011f4b5b-f020-4187-93f5-8a64df44ad48', 'Emma Frost', 'VANGUARD', 'https://r.res.easebar.com/pic/20250408/f625b9b9-e844-4ccf-b98e-eaff91818258.png'),
('46e47f1b-a312-4686-ae9f-328318c544dd', 'Gambit', 'STRATEGIST', 'https://r.res.easebar.com/pic/20251115/32d9260c-ff1b-45b3-b95e-9e6864aa75f4.png'),
('f29f3cf1-e8dd-4188-acce-e519dd94206d', 'GROOT', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_3.png'),
('e7e0573d-ac83-4d1e-b286-7c7e4c79fc81', 'HAWKEYE', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_27.png'),
('7db8153e-f7fd-4889-b234-af4e06a0cabe', 'HELA', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_5.png'),
('9471f35c-3f81-4ae2-9726-b2944dd431e9', 'HULK', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_19.png'),
('f0ec2612-649f-48bb-a18b-48ef1fe9ba56', 'HUMAN TORCH', 'DUELIST', 'https://r.res.easebar.com/pic/20250220/697bbc3d-7e84-429a-90ee-c01edc8280ce.png'),
('9cc13662-5669-460f-adbf-f53aba63bb46', 'INVISIBLE WOMAN', 'STRATEGIST', 'https://r.res.easebar.com/pic/20250109/671bff2d-a31c-4b54-872d-a74669db3c80.png'),
('c90562b1-0bf1-4f90-94ed-d24a7650a2b0', 'IRON FIST', 'DUELIST', 'https://r.res.easebar.com/pic/20241201/b68a9250-009e-424e-9a76-413d6e7ac70d.png'),
('ef114434-6c2a-48ff-a4f7-05dc278aedde', 'IRON MAN', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_6.png'),
('49e078be-c0c3-4efc-ad01-9c6f4b4f043e', 'JEFF THE LAND SHARK', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_23.png'),
('dc1d68ab-9f3f-465a-80c0-e77bb51a66bc', 'JUBILEE', 'STRATEGIST', 'https://r.res.easebar.com/pic/20260708/48ff52bf-6f30-4350-b883-00f2652015dd.png'),
('c6011abe-8d17-4962-ac88-7232dc3d208f', 'LOKI', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_7.png'),
('1077f07b-2178-49d3-80be-d915de78d17c', 'LUNA SNOW', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_18.png'),
('dd9a323f-da66-4ba8-9e37-1d3e8398a9b4', 'MAGIK', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_12.png'),
('2dffcc89-3280-4d43-907a-646eea9d3a74', 'MAGNETO', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_11.png'),
('bbb138f7-80d3-4db4-a608-4ee2d29c5fc0', 'MANTIS', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_9.png'),
('fccfe09c-c34c-40d6-b546-a34386612729', 'MISTER FANTASTIC', 'DUELIST', 'https://r.res.easebar.com/pic/20250109/65590c45-16ea-44f3-a508-c80a9f5547b9.png'),
('7dc8b934-fe12-49ae-ac3b-7d7c3a688443', 'MOON KNIGHT', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_26.png'),
('afbd915c-3505-4660-9815-bebe2c96370b', 'NAMOR', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_20.png'),
('3929765b-c856-44c9-b97a-eb965f3fbdf6', 'PENI PARKER', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_10.png'),
('f2521fc5-3180-477d-945c-403fa65fd7f5', 'PHOENIX', 'DUELIST', 'https://r.res.easebar.com/pic/20250711/e3658f05-e1f0-451d-902f-12ed100caa3e.png'),
('1c8d092c-74b9-4988-82ba-151a4b4f1308', 'PSYLOCKE', 'DUELIST', 'https://r.res.easebar.com/pic/20241127/74061285-68c2-4095-8ead-32f88791f9c2.png'),
('e1fb7cc4-a1a0-473b-8809-68b04dcc9420', 'ROCKET RACCOON', 'STRATEGIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_8.png'),
('deb6b426-c97e-4449-b345-4d7131336a64', 'Rogue', 'VANGUARD', 'https://r.res.easebar.com/pic/20251212/f443e1cb-5605-4c4e-8d29-24078699d479.png'),
('1d3f08cf-abee-4eb9-b2fd-31ce9947e5a1', 'SCARLET WITCH', 'DUELIST', 'https://r.res.easebar.com/pic/20260615/9b56d391-4042-4447-932b-1e51ee3cdc78.png'),
('feef5830-45b0-435e-8f7b-829241918b4d', 'SPIDER-MAN', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_13.png'),
('4ed51741-f094-46ef-b5ca-bb2025b15c50', 'SQUIRREL GIRL', 'DUELIST', 'https://r.res.easebar.com/pic/20241201/4bb60bec-2314-4ffd-8698-574c00bc16cc.png'),
('f052a66a-d95a-4062-911a-0c4cd35386ac', 'STAR-LORD', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_16.png'),
('93784596-43d9-42f9-bb0c-86a5140f4917', 'STORM', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_17.png'),
('77ad32c5-b42c-405d-afeb-bd452681b8e8', 'THE PUNISHER', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_4.png'),
('10bfa106-6a69-4dac-85f5-8b327e98e566', 'THE THING', 'VANGUARD', 'https://r.res.easebar.com/pic/20250220/48b05dd6-4ddf-431a-b517-ff7634940528.png'),
('fcddbb53-6a99-45f6-9cc8-65c68edd96e0', 'THOR', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_22.png'),
('dddc5632-ed86-4312-b8da-1616183fd909', 'Ultron', 'STRATEGIST', 'https://r.res.easebar.com/pic/20250529/3644db29-a6d9-4497-ba00-0b834aa66a63.png'),
('fa12017d-641d-4734-b459-187c2a6cdeb1', 'VENOM', 'VANGUARD', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_14.png'),
('bff0c7c6-3042-4384-8735-7ec6354baa1e', 'WHITE FOX', 'STRATEGIST', 'https://r.res.easebar.com/pic/20260320/fee6b610-5bc8-4a73-92e0-5d56d983c260.png'),
('7b26015b-e5f2-4d01-983b-885540b6236d', 'WINTER SOLDIER', 'DUELIST', 'https://www.marvelrivals.com/pc/gw/5da825b19a6a/heros/head_25.png'),
('a9b308ab-f0d8-412a-9362-e60091e57ded', 'WOLVERINE', 'DUELIST', 'https://r.res.easebar.com/pic/20241204/6decb3c7-c852-4d5e-811c-a932e3bfc4a8.png')
on conflict (id) do update set
  name = excluded.name,
  role = excluded.role,
  image_url = excluded.image_url;

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
grant execute on function public.get_next_pairwise_matchup(text, uuid[]) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;
revoke all on table public.pairwise_comparisons from anon, authenticated;

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

create table if not exists public.ranked_ballots (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (category_id, voter_key)
);

create table if not exists public.ranked_ballot_items (
  ballot_id uuid not null references public.ranked_ballots(id) on delete cascade,
  hero_id uuid not null references public.heroes(id) on delete cascade,
  rank_position integer not null check (rank_position > 0),
  created_at timestamptz not null default now(),
  primary key (ballot_id, hero_id),
  unique (ballot_id, rank_position)
);

alter table public.ranked_ballots enable row level security;
alter table public.ranked_ballot_items enable row level security;

drop policy if exists "Public can read ranked ballots" on public.ranked_ballots;
create policy "Public can read ranked ballots"
on public.ranked_ballots for select
to anon, authenticated
using (true);

drop policy if exists "Public can create ranked ballots" on public.ranked_ballots;
create policy "Public can create ranked ballots"
on public.ranked_ballots for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update ranked ballots" on public.ranked_ballots;
create policy "Public can update ranked ballots"
on public.ranked_ballots for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Public can read ranked ballot items" on public.ranked_ballot_items;
create policy "Public can read ranked ballot items"
on public.ranked_ballot_items for select
to anon, authenticated
using (true);

drop policy if exists "Public can create ranked ballot items" on public.ranked_ballot_items;
create policy "Public can create ranked ballot items"
on public.ranked_ballot_items for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can delete ranked ballot items" on public.ranked_ballot_items;
create policy "Public can delete ranked ballot items"
on public.ranked_ballot_items for delete
to anon, authenticated
using (true);

create or replace function public.submit_ranked_ballot(
  p_category_id uuid, p_voter_key text, p_hero_ids uuid[]
) returns void language plpgsql security definer set search_path = public as $$
declare v_ballot_id uuid;
begin
  insert into public.ranked_ballots (category_id, voter_key, updated_at) values (p_category_id, p_voter_key, now())
  on conflict (category_id, voter_key) do update set updated_at = now() returning id into v_ballot_id;
  delete from public.ranked_ballot_items where ballot_id = v_ballot_id;
  insert into public.ranked_ballot_items (ballot_id, hero_id, rank_position)
  select v_ballot_id, hero_id, rank_position::int from unnest(p_hero_ids) with ordinality as ranked(hero_id, rank_position);
end;
$$;

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

grant select, insert, update on table public.ranked_ballots to anon, authenticated;
grant select, insert, delete on table public.ranked_ballot_items to anon, authenticated;
grant execute on function public.submit_ranked_ballot(uuid, text, uuid[]) to anon, authenticated;
grant select on table public.category_rankings to anon, authenticated;

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
create policy "Public can read tier ballots" on public.tier_ballots for select to anon, authenticated using (true);

drop policy if exists "Public can create tier ballots" on public.tier_ballots;
create policy "Public can create tier ballots" on public.tier_ballots for insert to anon, authenticated with check (true);

drop policy if exists "Public can update tier ballots" on public.tier_ballots;
create policy "Public can update tier ballots" on public.tier_ballots for update to anon, authenticated using (true) with check (true);

drop policy if exists "Public can read tier ballot items" on public.tier_ballot_items;
create policy "Public can read tier ballot items" on public.tier_ballot_items for select to anon, authenticated using (true);

drop policy if exists "Public can create tier ballot items" on public.tier_ballot_items;
create policy "Public can create tier ballot items" on public.tier_ballot_items for insert to anon, authenticated with check (true);

drop policy if exists "Public can delete tier ballot items" on public.tier_ballot_items;
create policy "Public can delete tier ballot items" on public.tier_ballot_items for delete to anon, authenticated using (true);

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

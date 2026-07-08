create extension if not exists pgcrypto;

create table if not exists public.heroes (
  id uuid primary key,
  name text not null unique,
  role text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  hero_id uuid not null references public.heroes(id) on delete cascade,
  voter_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint votes_voter_key_unique unique (voter_key),
  constraint votes_voter_key_length check (char_length(voter_key) between 24 and 128)
);

alter table public.heroes enable row level security;
alter table public.votes enable row level security;

drop policy if exists "Public can read heroes" on public.heroes;
create policy "Public can read heroes"
on public.heroes for select
to anon, authenticated
using (true);

create or replace function public.touch_vote_timestamp()
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
for each row execute function public.touch_vote_timestamp();

create or replace view public.hero_vote_results as
select
  h.id as hero_id,
  h.name,
  h.role,
  h.image_url,
  count(v.id)::int as votes
from public.heroes h
left join public.votes v on v.hero_id = h.id
group by h.id, h.name, h.role, h.image_url
order by votes desc, h.name asc;

create or replace function public.cast_vote(p_hero_id uuid, p_voter_key text)
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
  insert into public.votes (hero_id, voter_key)
  values (p_hero_id, p_voter_key)
  on conflict (voter_key) do update set hero_id = excluded.hero_id;
end;
$$;

grant usage on schema public to anon, authenticated;
grant select on table public.heroes to anon, authenticated;
grant select on table public.hero_vote_results to anon, authenticated;
grant execute on function public.cast_vote(uuid, text) to anon, authenticated;
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

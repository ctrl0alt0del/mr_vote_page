create or replace function public.submit_ranked_ballot(p_category_id uuid, p_voter_key text, p_hero_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_ballot_id uuid;
begin
  insert into public.ranked_ballots (category_id, voter_key, updated_at)
  values (p_category_id, p_voter_key, now())
  on conflict (category_id, voter_key) do update set updated_at = now()
  returning id into v_ballot_id;
  delete from public.ranked_ballot_items where ballot_id = v_ballot_id;
  insert into public.ranked_ballot_items (ballot_id, hero_id, rank_position)
  select v_ballot_id, hero_id, rank_position::int
  from unnest(p_hero_ids) with ordinality as ranked(hero_id, rank_position);
end;
$$;

grant execute on function public.submit_ranked_ballot(uuid, text, uuid[]) to anon, authenticated;

notify pgrst, 'reload schema';

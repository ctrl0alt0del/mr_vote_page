import { supabase } from './supabase'

export async function fetchSetup() {
  const [heroes, categories, links] = await Promise.all([
    fetchHeroes(),
    fetchCategories(),
    fetchCategoryHeroLinks(),
  ])
  return { categories: attachHeroIds(categories, links, heroes), heroes }
}

export async function fetchHeroes() {
  const { data, error } = await supabase.from('heroes').select('id,name,role,image_url').order('name')
  throwIfError(error)
  return (data ?? []).map(normalizeHero)
}

export async function fetchCategories() {
  const query = supabase.from('categories').select(categoryColumns()).order('sort_order').order('created_at')
  const { data, error } = await query
  throwIfError(error)
  return (data ?? []).map(normalizeCategory)
}

export async function createCategory(values, heroIds) {
  const payload = { ...values, sort_order: Math.floor(Date.now() / 1000) }
  const { data, error } = await supabase.from('categories').insert(payload).select().single()
  throwIfError(error)
  await replaceCategoryHeroes(data.id, heroIds)
  return normalizeCategory(data)
}

export async function updateCategory(id, values, heroIds) {
  const { error } = await supabase.from('categories').update(values).eq('id', id)
  throwIfError(error)
  await replaceCategoryHeroes(id, heroIds)
}

export async function deleteCategory(id) {
  const { error } = await supabase.from('categories').delete().eq('id', id)
  throwIfError(error)
}

export async function submitRankedBallot(categoryId, heroIds, voterKey) {
  const args = { p_category_id: categoryId, p_voter_key: voterKey, p_hero_ids: heroIds }
  const { error } = await supabase.rpc('submit_ranked_ballot', args)
  throwIfError(error)
}

export async function submitTierBallot(categoryId, tierItems, voterKey) {
  const args = tierBallotArgs(categoryId, tierItems, voterKey)
  const { error } = await supabase.rpc('submit_tier_ballot', args)
  throwIfError(error)
}

export async function fetchCategoryRankings(categoryId) {
  const query = supabase.from('category_rankings').select(rankingColumns()).eq('category_id', categoryId).order('rank').order('name')
  const { data, error } = await query
  throwIfError(error)
  return (data ?? []).map(normalizeRanking)
}

async function fetchCategoryHeroLinks() {
  const { data, error } = await supabase.from('category_heroes').select('category_id,hero_id')
  throwIfError(error)
  return data ?? []
}

async function replaceCategoryHeroes(categoryId, heroIds) {
  await deleteCategoryHeroes(categoryId)
  if (!heroIds.length) return
  await insertCategoryHeroes(categoryId, heroIds)
}

async function deleteCategoryHeroes(categoryId) {
  const { error } = await supabase.from('category_heroes').delete().eq('category_id', categoryId)
  throwIfError(error)
}

async function insertCategoryHeroes(categoryId, heroIds) {
  const rows = heroIds.map((heroId) => ({ category_id: categoryId, hero_id: heroId }))
  const { error } = await supabase.from('category_heroes').insert(rows)
  throwIfError(error)
}

function attachHeroIds(categories, links, heroes) {
  return categories.map((category) => ({ ...category, heroIds: heroIdsFor(category.id, links, heroes) }))
}

function heroIdsFor(categoryId, links, heroes) {
  const ids = links.filter((item) => item.category_id === categoryId).map((item) => item.hero_id)
  return ids.length ? ids : heroes.map((hero) => hero.id)
}

function categoryColumns() {
  return 'id,name,description,poll_type,tier_config,tier_orientation,sort_order,created_at'
}

function rankingColumns() {
  return 'category_id,category_name,hero_id,name,role,image_url,ballots,points,average_rank,rank,poll_type,tier_key,tier_label,tier_votes,tier_order'
}

function normalizeCategory(row) {
  return { description: row.description ?? '', heroIds: [], id: row.id, name: row.name, pollType: row.poll_type ?? 'ranked', sortOrder: row.sort_order ?? 0, tierConfig: normalizeTierConfig(row.tier_config), tierOrientation: row.tier_orientation ?? 'vertical' }
}

function normalizeHero(row) {
  return { id: row.id, imageUrl: row.image_url, name: row.name, role: row.role }
}

function normalizeRanking(row) {
  return { averageRank: row.average_rank, ballots: row.ballots, id: row.hero_id, imageUrl: row.image_url, name: row.name, points: Number(row.points ?? 0), pollType: row.poll_type ?? 'ranked', rank: row.rank, role: row.role, tierKey: row.tier_key, tierLabel: row.tier_label, tierOrder: row.tier_order, tierVotes: row.tier_votes ?? 0 }
}

function tierBallotArgs(categoryId, tierItems, voterKey) {
  return { p_category_id: categoryId, p_hero_ids: tierItems.map((item) => item.heroId), p_tier_keys: tierItems.map((item) => item.tierKey), p_voter_key: voterKey }
}

function normalizeTierConfig(value) {
  if (!Array.isArray(value) || value.length < 2) return defaultTierConfig()
  const tiers = value.map((tier, index) => normalizeTier(tier, index)).filter((tier) => tier.label)
  return tiers.length >= 2 ? tiers : defaultTierConfig()
}

function normalizeTier(tier, index) {
  return { key: tier.key || `tier-${index + 1}`, label: String(tier.label ?? '').trim() }
}

function defaultTierConfig() {
  return ['S', 'A', 'B', 'C', 'D'].map((label) => ({ key: label.toLowerCase(), label }))
}

function throwIfError(error) {
  if (error) throw error
}

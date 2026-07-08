const heroKey = 'marvel-rivals-poll-hero'
const voterKey = 'marvel-rivals-poll-voter'

export function getVoterKey() {
  const current = readStorage(voterKey)
  if (current) return current
  const next = createVoterKey()
  writeStorage(voterKey, next)
  return next
}

export function getStoredHeroId(categoryId) {
  if (!categoryId) return ''
  return readStorage(makeHeroKey(categoryId))
}

export function storeHeroId(categoryId, heroId) {
  writeStorage(makeHeroKey(categoryId), heroId)
}

function makeHeroKey(categoryId) {
  return `${heroKey}:${categoryId}`
}

function createVoterKey() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()
  return `${Date.now()}-${randomPart()}-${randomPart()}`
}

function randomPart() {
  return Math.random().toString(36).slice(2)
}

function readStorage(key) {
  try {
    return globalThis.localStorage?.getItem(key) ?? ''
  } catch {
    return ''
  }
}

function writeStorage(key, value) {
  try {
    globalThis.localStorage?.setItem(key, value)
  } catch {
    return undefined
  }
}

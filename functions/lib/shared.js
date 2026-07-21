const { HttpsError } = require("firebase-functions/v2/https");

// Every villager's starting vote weight (concept doc §5) — mirrors
// LocalGameRepository's `_startingVoteWeight`.
const STARTING_VOTE_WEIGHT = 3;

function requireString(value, field) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function requirePositiveInt(value, field) {
  if (!Number.isInteger(value) || value < 1) {
    throw new HttpsError("invalid-argument", `${field} must be a positive integer.`);
  }
  return value;
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return request.auth;
}

// Fisher-Yates — used for the mafia draw, same as
// LocalGameRepository._activateGame's `..shuffle(Random())`.
function shuffle(items) {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
}

// Trimmed + lowercased + deduped, so "Tiger"/" tiger "/"TIGER" all match and
// order never matters — mirrors LocalGameRepository's `_normalizeWords`
// exactly (restricted-case passphrase comparison).
function normalizeWords(words) {
  return [...new Set((words || []).map((w) => String(w).trim().toLowerCase()).filter((w) => w))];
}

function sameWords(a, b) {
  const setA = new Set(a);
  const setB = new Set(b);
  if (setA.size !== setB.size) return false;
  return [...setA].every((w) => setB.has(w));
}

// Single-value sibling of normalizeWords — used as the doc id for the
// locations_countries/locations_cities/locations_companies lookup
// collections, so "Acme Corp"/"ACME"/"acme corp." all converge on the
// same doc instead of fragmenting into near-duplicates.
function normalizeWord(value) {
  return String(value || "").trim().toLowerCase();
}

module.exports = {
  STARTING_VOTE_WEIGHT,
  requireString,
  requirePositiveInt,
  requireAuth,
  shuffle,
  normalizeWords,
  sameWords,
  normalizeWord,
};

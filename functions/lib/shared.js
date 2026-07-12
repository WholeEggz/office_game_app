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

module.exports = {
  STARTING_VOTE_WEIGHT,
  requireString,
  requirePositiveInt,
  requireAuth,
  shuffle,
};

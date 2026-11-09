// PWC IOM Space Adventure — leaderboard API (Netlify Functions v2 + Netlify Blobs).
//
// Implements the contract consumed by assets/ui/LeaderboardClient.gd:
//
//   GET  /api/leaderboard?mode=<mode>&limit=<n>  -> {"entries":[...],"total_players":n}
//   GET  /api/rank?mode=<mode>&score=<n>         -> {"rank":n,"total_players":n}
//   POST /api/submit                             -> {"rank":n,"total_players":n,"entry":{...},"neighbours":[...]}
//
// Entry shape (what ShipmindLeaderboard.gd reads): player_name, score, rank,
// created_at (ISO-8601 UTC; entries younger than 900s render as "ACTIVE").
// `submission_id` is stored but never returned — it exists so the client's
// offline queue can retry safely: submissions are deduped on it.

import { getStore } from "@netlify/blobs";

const MAX_ENTRIES = 1000; // board trim size per mode
const MAX_SEEN = 5000; // dedupe memory (FIFO) per mode
const MAX_NAME = 24;
const MAX_SCORE = 10_000_000;
const MAX_SECONDS = 86_400;

const CORS = {
  "content-type": "application/json",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type",
};

const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: CORS });

const bad = (error, status = 400) => json(status, { error });

// --- input sanitising ---------------------------------------------------------

function cleanMode(raw) {
  const m = String(raw ?? "default").trim().toLowerCase();
  return /^[a-z0-9_-]{1,32}$/.test(m) ? m : "default";
}

// The testing-round reset: POST /api/reset with {"key": "..."} clears every
// board. The key must match the site's PWC_RESET_KEY env var - unset, the
// endpoint refuses, so production ships inert.
async function resetBoards(store) {
  return store.list().then(async (result) => {
    let cleared = 0;
    const keys = [];
    for (const entry of result.blobs) {
      if (!entry.key.startsWith("board:")) continue;
      await store.delete(entry.key);
      keys.push(entry.key);
      cleared += 1;
    }
    return { cleared, keys };
  });
}

async function postReset(store, req) {
  let body;
  try {
    body = await req.json();
  } catch {
    return bad("body must be JSON");
  }
  const expected = (Netlify.env.get("PWC_RESET_KEY") || "").trim();
  if (expected === "") return bad("no reset key is configured for this site", 403);
  if (String(body?.key ?? "") !== expected) return bad("reset key does not match", 403);
  const result = await resetBoards(store);
  return json(200, { cleared: true, boards_removed: result.cleared, keys: result.keys });
}

function cleanName(raw) {
  const name = String(raw ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_NAME);
  return name || "PILOT";
}

function cleanScore(raw) {
  const n = Math.round(Number(raw));
  if (!Number.isFinite(n)) return null;
  return Math.min(Math.max(n, 0), MAX_SCORE);
}

function cleanSeconds(raw) {
  const n = Math.round(Number(raw ?? 0));
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(n, MAX_SECONDS);
}

// --- blob store (one JSON blob per mode) --------------------------------------
// shape: { entries: [{player_name, score, created_at, submission_id, email}], seen: {id: {t, e}} }

async function loadBoard(store, mode) {
  const board = await store.get(`board:${mode}`, { type: "json" });
  if (board && Array.isArray(board.entries)) {
    if (!board.seen || typeof board.seen !== "object") board.seen = {};
    return board;
  }
  return { entries: [], seen: {} };
}

const saveBoard = (store, mode, board) => store.setJSON(`board:${mode}`, board);

function sorted(entries) {
  return entries.sort(
    (a, b) => b.score - a.score || String(a.created_at).localeCompare(String(b.created_at))
  );
}

// rank = 1-based position; ties share the slot of the earlier submission.
const withRanks = (entries) => entries.map((e, i) => ({ ...e, rank: i + 1 }));

const projectedRank = (entries, score) =>
  1 + entries.filter((e) => e.score > score).length;

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Stored with the entry, never echoed: publicEntry's whitelist keeps it off
// every response.
const cleanEmail = (v) => {
  const s = String(v ?? "")
    .trim()
    .slice(0, 120);
  if (s === "") return "";
  return EMAIL_RE.test(s) ? s : null;
};

const publicEntry = ({ player_name, score, created_at, rank }) => ({
  player_name,
  score,
  created_at,
  ...(rank !== undefined ? { rank } : {}),
});

// --- handlers -----------------------------------------------------------------

async function getLeaderboard(store, url) {
  const mode = cleanMode(url.searchParams.get("mode"));
  let limit = Math.round(Number(url.searchParams.get("limit") ?? 50));
  if (!Number.isFinite(limit) || limit < 1) limit = 50;
  limit = Math.min(limit, 100);

  const board = await loadBoard(store, mode);
  const entries = withRanks(sorted(board.entries))
    .slice(0, limit)
    .map(publicEntry);
  return json(200, { entries, total_players: board.entries.length });
}

async function getRank(store, url) {
  const mode = cleanMode(url.searchParams.get("mode"));
  const score = cleanScore(url.searchParams.get("score"));
  if (score === null) return bad("score must be an integer");

  const board = await loadBoard(store, mode);
  return json(200, {
    rank: projectedRank(board.entries, score),
    total_players: board.entries.length,
  });
}

async function postSubmit(store, req) {
  let body;
  try {
    body = await req.json();
  } catch {
    return bad("body must be JSON");
  }

  const submissionId = String(body?.submission_id ?? "").slice(0, 64);
  if (!submissionId) return bad("submission_id is required");

  const score = cleanScore(body?.score);
  if (score === null) return bad("score must be an integer");

  const mode = cleanMode(body?.mode);
  const email = cleanEmail(body?.email);
  if (email === null) return bad("email address is not valid");
  const entry = {
    player_name: cleanName(body?.name),
    score,
    created_at: new Date().toISOString(),
    submission_id: submissionId,
    email,
  };

  const board = await loadBoard(store, mode);

  // Idempotency: the client queues offline and retries on the next launch,
  // so the same submission_id must never create a second row.
  const prior = board.seen[submissionId];
  if (prior?.e) {
    const ranked = withRanks(sorted(board.entries));
    const onBoard = ranked.find((e) => e.submission_id === submissionId);
    const rank = onBoard ? onBoard.rank : projectedRank(board.entries, prior.e.score);
    return json(200, {
      rank,
      total_players: board.entries.length,
      entry: publicEntry({ ...prior.e, rank }),
      neighbours: [],
    });
  }

  board.entries.push(entry);
  sorted(board.entries);
  if (board.entries.length > MAX_ENTRIES) board.entries.length = MAX_ENTRIES;

  board.seen[submissionId] = { t: Date.now(), e: { ...entry } };
  const seenIds = Object.keys(board.seen);
  if (seenIds.length > MAX_SEEN) {
    seenIds
      .sort((a, b) => board.seen[a].t - board.seen[b].t)
      .slice(0, seenIds.length - MAX_SEEN)
      .forEach((id) => delete board.seen[id]);
  }

  await saveBoard(store, mode, board);

  const ranked = withRanks(board.entries);
  const idx = ranked.findIndex((e) => e.submission_id === submissionId);
  const from = Math.max(0, idx - 2);
  const neighbours = ranked
    .slice(from, idx + 3)
    .filter((e) => e.submission_id !== submissionId)
    .map(publicEntry);

  return json(200, {
    rank: idx + 1,
    total_players: board.entries.length,
    entry: publicEntry(ranked[idx]),
    neighbours,
  });
}

// --- routing ------------------------------------------------------------------

export default async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  const url = new URL(req.url);
  const store = getStore({ name: "leaderboard", consistency: "strong" });

  try {
    if (url.pathname === "/api/leaderboard" && req.method === "GET")
      return await getLeaderboard(store, url);
    if (url.pathname === "/api/rank" && req.method === "GET")
      return await getRank(store, url);
    if (url.pathname === "/api/submit" && req.method === "POST")
      return await postSubmit(store, req);
    if (url.pathname === "/api/reset" && req.method === "POST")
      return await postReset(store, req);
    return bad("not found", 404);
  } catch (err) {
    return bad(`server error: ${err?.message ?? "unknown"}`, 500);
  }
};

export const config = { path: "/api/*" };

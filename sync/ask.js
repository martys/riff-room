// "Ask for a song": a family member types a request in the app; Claude (Anthropic API, with web search) finds a free
// public-domain file of the piece, or writes the tune out itself; this Worker downloads and checks the file and sends
// the song back to the app, which adds it to the family's songs.
//
// Needs the secret ANTHROPIC_API_KEY on this Worker (Cloudflare dashboard → Workers → riff-room → Settings → Variables
// and Secrets). Optional vars: ASK_MODEL, ASK_DAILY_LIMIT (requests per family per day, default 15).
// Only families with a sync code that has saved data may ask, so strangers can't spend the key's credit.

const SYSTEM = `You find songs for Riff Room, a family piano-learning app (falling notes, both hands, a real piano).
A family member asks for a song. Return it so the app can add it.

COPYRIGHT
- Only music that is free to use: public-domain compositions (composer died 70+ years ago or published before 1930),
  traditional and folk songs, or your own simple arrangement of such music.
- If the requested melody is still under copyright (modern pop, film and game music, most songs after ~1930), do NOT write
  out or link its melody. Return an error with a short, friendly explanation and suggest 2-3 free-to-use pieces with a
  similar feel.

HOW TO ANSWER
1. Look for a ready file first, using web search: a direct download of the piece as MIDI (.mid/.midi) or MusicXML
   (.musicxml/.xml/.mxl) from a free source. The Mutopia Project (www.mutopiaproject.org) is the best source: its piece
   pages list direct .mid files under https://www.mutopiaproject.org/ftp/... . Only give URLs you actually saw in results;
   never invent URLs. Up to 4 candidates, best first. Avoid IMSLP downloads (they need a click-through).
2. ALSO write the tune yourself in "notes" (it is used if no file works, and for easy versions):
   - beats are quarter notes; each note is [start_beat, length_beats, ["G4"], "R" or "L"]; several notes may start together.
   - note names: letter, optional # or b, octave; middle C is C4. Right hand = tune, mostly between C4 and C6.
     Left hand = simple bass (one or two notes per bar) between C2 and C4, or leave it out for a "right hand" request.
   - write out the WHOLE tune with every section and repeat in order, unless only a part was asked for. Get the rhythm right.
     Check it note by note against what you know and what you found; a wrong note taught as right is worse than none.
   - at most 600 notes. Keep it playable for the level asked (easy = one note at a time in the right hand).
3. If the request says easy / simple / melody / right hand, or the file you found is a big concert arrangement, set
   "prefer": "notes"; otherwise "prefer": "file".

FINAL ANSWER: end with exactly one block, nothing after it:
<song>{"title": "...", "credit": "source and licence, e.g. 'Mutopia Project, public domain' or 'traditional, arranged by Claude'",
 "prefer": "file" | "notes", "file_urls": ["https://..."], "bpm": 96, "time": "3/4", "hand": "right hand" | "both hands",
 "notes": [[0, 1, ["Bb4"], "R"], ...]}</song>
or, when you can't help: <song>{"error": "short friendly message for the family"}</song>`;

export async function ask(req, env, cors) {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405, cors);
  const code = (req.headers.get("X-Family") || "").trim().toLowerCase();
  if (code.length < 12) return json({ error: "Set up the family code first (tap the player's name → Family code)." }, 401, cors);
  const fam = await sha256(code);
  if (!(await env.RIFF.get("family:" + fam))) return json({ error: "That family code has no saved data yet. Play a song first so it syncs, then try again." }, 403, cors);
  if (!env.ANTHROPIC_API_KEY) return json({ error: "The song finder isn't switched on yet: the Anthropic API key is missing on the server.", code: "not_configured" }, 503, cors);

  let body; try { body = await req.json(); } catch { return json({ error: "bad json" }, 400, cors); }
  const query = String(body.query || "").trim().slice(0, 300);
  if (query.length < 2) return json({ error: "Type the name of a song." }, 400, cors);
  const note = String(body.note || "").trim().slice(0, 400), previous = String(body.previous || "").trim().slice(0, 120);

  // a simple daily limit per family
  const limit = +env.ASK_DAILY_LIMIT || 15, dayKey = `ask:${fam}:${new Date().toISOString().slice(0, 10)}`;
  const used = +(await env.RIFF.get(dayKey)) || 0;
  if (used >= limit) return json({ error: `That's ${limit} song requests today. Try again tomorrow.` }, 429, cors);
  await env.RIFF.put(dayKey, String(used + 1), { expirationTtl: 2 * 86400 });

  let prompt = `Song request: ${query}`;
  if (previous) prompt += `\n\nThe family already tried your earlier version "${previous}" and said: ${note || "it isn't right"}. Fix that.`;
  else if (note) prompt += `\n\nExtra wishes: ${note}`;

  let result;
  try { result = await callClaude(env, prompt); } catch (e) { return json({ error: "The song finder couldn't finish: " + e.message }, 502, cors); }
  if (result.error) return json({ error: result.error }, 200, cors);

  const base = { title: String(result.title || query).slice(0, 60), credit: String(result.credit || "").slice(0, 160),
    bpm: +result.bpm || 90, time: String(result.time || "4/4"), hand: String(result.hand || "both hands") };
  const notes = Array.isArray(result.notes) ? cleanNotes(result.notes) : [];

  if (result.prefer !== "notes" || !notes.length) {
    for (const u of (result.file_urls || []).slice(0, 4)) {
      const f = await fetchMusicFile(String(u));
      if (f) return json({ ...base, kind: f.kind, data: f.b64, source: u }, 200, cors);
    }
  }
  if (notes.length) return json({ ...base, kind: "notes", notes }, 200, cors);
  return json({ error: "Couldn't find a usable file or write the tune. Try adding the composer's name, or ask for an easy melody." }, 200, cors);
}

async function callClaude(env, prompt) {
  const messages = [{ role: "user", content: prompt }];
  const apiBase = env.ANTHROPIC_BASE || "https://api.anthropic.com";
  for (let round = 0; round < 5; round++) {
    const r = await fetch(apiBase + "/v1/messages", {
      method: "POST",
      headers: { "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: env.ASK_MODEL || "claude-sonnet-5-5", max_tokens: 16000, system: SYSTEM, messages,
        tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 6 }] }),
    });
    if (!r.ok) { const t = await r.text(); throw new Error(`Anthropic API ${r.status}: ${t.slice(0, 200)}`); }
    const msg = await r.json();
    if (msg.stop_reason === "pause_turn") { messages.push({ role: "assistant", content: msg.content }); continue; }
    const text = (msg.content || []).filter(b => b.type === "text").map(b => b.text).join("");
    const m = text.match(/<song>([\s\S]*?)<\/song>/);
    if (!m) throw new Error("no answer block");
    try { return JSON.parse(m[1]); } catch { throw new Error("answer wasn't valid JSON"); }
  }
  throw new Error("took too long");
}

const NOTE = /^[A-G](#|b)?-?\d$/;
function cleanNotes(arr) {
  return arr.slice(0, 1200).map(n => Array.isArray(n) && n.length >= 3 ? [+n[0], +n[1], (Array.isArray(n[2]) ? n[2] : [n[2]]).map(String).filter(x => NOTE.test(x)), n[3] === "L" ? "L" : "R"] : null)
    .filter(n => n && isFinite(n[0]) && n[0] >= 0 && isFinite(n[1]) && n[1] > 0 && n[1] <= 32 && n[2].length);
}

async function fetchMusicFile(u) {
  let url; try { url = new URL(u); } catch { return null; }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  try {
    const r = await fetch(url.toString(), { redirect: "follow", signal: AbortSignal.timeout(15000), headers: { "User-Agent": "RiffRoom/1.0 (family piano app)" } });
    if (!r.ok) return null;
    const buf = new Uint8Array(await r.arrayBuffer());
    if (buf.length < 30 || buf.length > 3_000_000) return null;
    const head = new TextDecoder().decode(buf.subarray(0, 400));
    let kind = null;
    if (head.startsWith("MThd")) kind = "midi";
    else if (buf[0] === 0x50 && buf[1] === 0x4b) kind = "mxl";
    else if (/^\s*(﻿)?</.test(head) && /score-partwise|score-timewise|<!DOCTYPE score/.test(new TextDecoder().decode(buf.subarray(0, 4000)))) kind = "musicxml";
    if (!kind) return null;
    let bin = ""; for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
    return { kind, b64: btoa(bin) };
  } catch { return null; }
}

function json(obj, status, headers) {
  return new Response(JSON.stringify(obj), { status, headers: { ...headers, "Content-Type": "application/json" } });
}
async function sha256(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("");
}

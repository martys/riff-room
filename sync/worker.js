// Riff Room sync: stores one JSON document per family, keyed by a hash of the family code.
// GET  /data  (header X-Family: <code>)            -> { version, data }
// PUT  /data  (header X-Family, body { base, data }) -> { version } or 409 { version, data } if someone saved first
export default {
  async fetch(req, env) {
    const origin = req.headers.get("Origin") || "";
    const allowed = (env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean);
    const cors = {
      "Access-Control-Allow-Methods": "GET, PUT, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, X-Family",
      "Access-Control-Max-Age": "86400",
      "Vary": "Origin",
    };
    if (!allowed.length || allowed.includes(origin)) cors["Access-Control-Allow-Origin"] = origin || "*";
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    const url = new URL(req.url);
    if (url.pathname !== "/data") return json({ error: "not found" }, 404, cors);

    const code = (req.headers.get("X-Family") || "").trim().toLowerCase();
    if (code.length < 12) return json({ error: "family code too short" }, 401, cors);
    const key = "family:" + await sha256(code);

    if (req.method === "GET") {
      const cur = await env.RIFF.get(key, "json");
      return json(cur ? { version: cur.version, data: cur.data } : { version: 0, data: null }, 200, cors);
    }

    if (req.method === "PUT") {
      const text = await req.text();
      if (text.length > 2_000_000) return json({ error: "too big" }, 413, cors);
      let body; try { body = JSON.parse(text); } catch { return json({ error: "bad json" }, 400, cors); }
      if (!body || typeof body.data !== "object" || typeof body.base !== "number") return json({ error: "bad body" }, 400, cors);
      const cur = await env.RIFF.get(key, "json");
      const version = cur ? cur.version : 0;
      if (body.base !== version) return json({ error: "conflict", version, data: cur && cur.data }, 409, cors);
      const next = { version: version + 1, saved: Date.now(), data: body.data };
      await env.RIFF.put(key, JSON.stringify(next));
      return json({ version: next.version }, 200, cors);
    }

    return json({ error: "method not allowed" }, 405, cors);
  },
};

function json(obj, status, headers) {
  return new Response(JSON.stringify(obj), { status, headers: { ...headers, "Content-Type": "application/json" } });
}

async function sha256(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("");
}

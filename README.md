# Riff Room

A family piano app: falling notes, levels and stars, sheet music, recording, and a Kawai CA401 over MIDI.

- `public/index.html` is the whole app (one file). `index.html` at the root is the same file for GitHub Pages.
- `sync/worker.js` is the Cloudflare Worker that serves the app and stores each family's progress at `/data`.

## Deploy to Cloudflare (once)

1. Create the storage: `npx wrangler login`, then `npx wrangler kv namespace create RIFF`.
   (Or in the dashboard: Storage & Databases → KV → Create, name it `RIFF`.)
2. Put the namespace id into `wrangler.toml` in place of `PASTE_THE_KV_NAMESPACE_ID_HERE`.
3. Either run `npx wrangler deploy` from the repo root, or connect the repo for automatic deploys:
   Workers & Pages → Create → Import a repository → `martys/riff-room`, deploy command `npx wrangler deploy`.
   With the repo connected, every push to `main` deploys.

The app is then at `https://riff-room.<your-subdomain>.workers.dev`. Sync switches on automatically there
(the app checks for a `.workers.dev` address; add a custom domain to `SYNC_HOSTS` in the app if you use one).

## Sync

Open "Who's playing?", create a family code on one device, type the same code on the others.
The code is never stored on the server; data is filed under its SHA-256 hash.
Saves carry a version number; if two devices save at once, the app merges (best stars and scores win,
newest settings win, recordings are kept) and saves again.
Anyone with the family code can read and change the family's progress.

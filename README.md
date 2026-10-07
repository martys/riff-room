# Riff Room

A family piano app: falling notes, levels and stars, sheet music, recording, and a Kawai CA401 over MIDI.

- `public/index.html` is the whole app (one file). `index.html` at the root is the same file for GitHub Pages.
- `sync/worker.js` is the Cloudflare Worker that serves the app and stores each family's progress at `/data`.

## Deploy to Cloudflare (once)

1. Storage is already created (KV namespace `riff-room-RIFF`, id in `wrangler.toml`).
2. Either run `npx wrangler deploy` from the repo root, or connect the repo for automatic deploys:
   Workers & Pages → Create → Import a repository → `martys/riff-room`, deploy command `npx wrangler deploy`.
   With the repo connected, every push to `main` deploys.

The app is at `https://pianoriffs.app` (custom domain, set in `wrangler.toml`), and also at `https://riff-room.<your-subdomain>.workers.dev`. Sync switches on automatically there
(the app checks for a `.workers.dev` address; add a custom domain to `SYNC_HOSTS` in the app if you use one).

## Sync

Open "Who's playing?", create a family code on one device, type the same code on the others.
The code is never stored on the server; data is filed under its SHA-256 hash.
Saves carry a version number; if two devices save at once, the app merges (best stars and scores win,
newest settings win, recordings are kept) and saves again.
Anyone with the family code can read and change the family's progress.

## iPad app

`ios/` holds a small native wrapper (CoreMIDI bridge + Bluetooth MIDI pairing). See `ios/README.md` to build it on a Mac.

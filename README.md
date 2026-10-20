# 9router-termux

Run **9Router** (npm package `9router` v0.5.104) — the self-hosted
OpenAI-compatible router + dashboard on port 20128 — natively on Android
via Termux.

9Router is a pure Node.js app (no native binary to compile), so this "port"
is an installer that makes its runtime behaviour sane on a phone, plus the
notes from dissecting the package.

## Install (on the phone, in Termux)

Download `install-9router-termux.sh` from this repo, then:

```sh
bash install-9router-termux.sh
```

The installer:

1. Checks/installs Node.js from Termux packages (Node ≥ 18; Termux ships
   22/24, which also provides the built-in `node:sqlite`).
2. Installs the pinned package: `npm install -g 9router@0.5.104`.
3. Verifies the CLI runs.
4. **Android heap patch:** upstream spawns the server with
   `--max-old-space-size=6144` (a desktop-sized 6 GB cap). The installer
   rewrites that flag in the installed `cli.js` to 512 MB
   (`NODE_HEAP_MB=1024 bash install-9router-termux.sh` to override).
   Re-run the installer after any reinstall/update to re-apply it.
5. Runs a bounded smoke test on `127.0.0.1:20128`
   (skip with `SKIP_SMOKE=1`).

## Run

```sh
9router --no-browser --host 127.0.0.1
```

- Dashboard: http://127.0.0.1:20128 — fresh-install password is `123456`,
  **change it**.
- OpenAI-compatible endpoint: http://127.0.0.1:20128/v1
- Data lives in `~/.9router` (SQLite DB in `~/.9router/db/`).
- Binding to `127.0.0.1` keeps it phone-only; upstream's default host is
  `0.0.0.0` (LAN-visible) — only use that deliberately.
- Never use `--tray` on Termux (desktop systray; its binary is not built
  for Android).

## What to expect on Android (by design, not errors)

- `better-sqlite3` is deliberately not bundled and has no Android prebuild,
  so 9Router falls back to the built-in `node:sqlite` / bundled sql.js.
  It is a speed optimisation only; the app works without it.
- The postinstall "runtime warm-up" may print warnings — it is non-fatal
  by design and the CLI retries runtime setup on first start.

See [TERMUX-NOTES.md](TERMUX-NOTES.md) for the full package dissection and
the reasoning behind each decision.

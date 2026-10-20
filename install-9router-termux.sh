#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# 9Router on Termux - native install script
#
# 9Router (npm package "9router", pinned v0.5.104) is a self-hosted
# OpenAI-compatible router + dashboard on port 20128. It is a Node.js app:
# there is no native binary to compile - the "port" is making its runtime
# dependency behaviour sane on Android/Termux.
#
# What this script does:
#   1. Installs Node.js from Termux packages if missing or < 18
#      (Termux ships Node 22/24 LTS -> also gives us built-in node:sqlite)
#   2. npm install -g 9router@0.5.104
#   3. Verifies the CLI runs
#   4. Android patch: caps the server heap (see below)
#   5. Bounded smoke test: starts the server on 127.0.0.1:20128, waits for
#      the dashboard to answer HTTP, then stops it again.
#      Skip with:  SKIP_SMOKE=1 bash install-9router-termux.sh
#
# Android heap patch: upstream cli.js spawns the server with
# --max-old-space-size=6144 (a desktop-sized 6 GB heap cap). On a phone that
# lets the server eat RAM until Android kills it. This installer rewrites
# that one flag in the installed cli.js to NODE_HEAP_MB (default 512).
# NODE_OPTIONS cannot do this - the explicit spawn flag wins. The patch is
# lost when the package is reinstalled/updated; just re-run this installer
# (or the sed from TERMUX-NOTES.md) to re-apply it. Override the value with:
#   NODE_HEAP_MB=1024 bash install-9router-termux.sh
#
# Expected on Android (by design of the package, NOT errors):
#   - better-sqlite3 has no Android prebuild, so 9Router falls back to the
#     built-in node:sqlite / bundled sql.js. That is a speed optimisation
#     only; the app works without it.
#   - The postinstall "runtime warm-up" may print warnings. It is non-fatal
#     (the package's postinstall always exits 0) and cli.js retries the
#     runtime setup on first start.
#   - The system-tray component targets desktop macOS/Linux. It is opt-in
#     via --tray; this script never enables it.
# ============================================================================
set -u

PIN_VERSION="0.5.104"
PORT="20128"
HOST="127.0.0.1"
NODE_HEAP_MB="${NODE_HEAP_MB:-512}"
SMOKE_LOG="$HOME/9router-smoke.log"

say()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!] %s\n' "$*"; }
die()  { printf '\n  [x] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
say "1/5 Node.js check"
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  ok "node found: $(node --version)"
else
  NODE_MAJOR=0
  warn "node not found"
fi

if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  say "Installing Node.js from Termux packages"
  pkg update -y || die "pkg update failed"
  pkg install -y nodejs || die "pkg install nodejs failed"
  hash -r
  command -v node >/dev/null 2>&1 || die "node still not on PATH after install"
  ok "installed: $(node --version)"
fi
command -v npm >/dev/null 2>&1 || die "npm not found (it ships with Termux nodejs)"

# ---------------------------------------------------------------------------
say "2/5 Installing 9router@$PIN_VERSION (npm -g)"
npm install -g "9router@$PIN_VERSION" || die "npm install -g 9router failed (see npm output above)"
hash -r

# ---------------------------------------------------------------------------
say "3/5 Verifying the CLI"
command -v 9router >/dev/null 2>&1 || die "9router binary not on PATH after install"
ok "9router --version: $(9router --version 2>/dev/null || echo '(no output)')"

# ---------------------------------------------------------------------------
say "4/5 Capping server heap at ${NODE_HEAP_MB} MB (Android patch)"
CLI_JS="$(npm root -g)/9router/cli.js"
if [ -f "$CLI_JS" ] && grep -q -- "--max-old-space-size=" "$CLI_JS"; then
  sed -i "s/--max-old-space-size=[0-9]*/--max-old-space-size=$NODE_HEAP_MB/" "$CLI_JS"
  if grep -q -- "--max-old-space-size=$NODE_HEAP_MB" "$CLI_JS"; then
    ok "patched $CLI_JS -> --max-old-space-size=$NODE_HEAP_MB"
  else
    warn "patch did not stick in $CLI_JS - heap cap left as upstream default"
  fi
else
  warn "no --max-old-space-size flag found in $CLI_JS (upstream changed?) - no patch applied"
fi

# ---------------------------------------------------------------------------
if [ "${SKIP_SMOKE:-0}" = "1" ]; then
  say "5/5 Smoke test skipped (SKIP_SMOKE=1)"
else
  say "5/5 Smoke test on http://$HOST:$PORT (first start can take ~1-3 min)"
  : > "$SMOKE_LOG"
  if command -v setsid >/dev/null 2>&1; then
    setsid 9router --no-browser --host "$HOST" --port "$PORT" >"$SMOKE_LOG" 2>&1 < /dev/null &
  else
    9router --no-browser --host "$HOST" --port "$PORT" >"$SMOKE_LOG" 2>&1 < /dev/null &
  fi
  SMOKE_PID=$!

  probe() {
    node -e "fetch('http://$HOST:$PORT/').then(r=>process.exit([200,301,302,307,308].includes(r.status)?0:1)).catch(()=>process.exit(1))" 2>/dev/null
  }

  UP=0
  for i in $(seq 1 36); do
    if probe; then UP=1; break; fi
    if ! kill -0 "$SMOKE_PID" 2>/dev/null; then break; fi
    printf '.'
    sleep 5
  done
  printf '\n'

  # Stop the smoke server (whole tree: CLI + spawned app server).
  kill "$SMOKE_PID" 2>/dev/null
  pkill -f "node_modules/9router" 2>/dev/null
  sleep 2
  pkill -9 -f "node_modules/9router" 2>/dev/null

  if [ "$UP" = "1" ]; then
    ok "dashboard answered on http://$HOST:$PORT"
  else
    warn "server did not answer within the probe window."
    warn "Last log lines (full log: $SMOKE_LOG):"
    tail -20 "$SMOKE_LOG" 2>/dev/null | sed 's/^/    /'
    warn "This does not mean the install failed - run it manually (below)"
    warn "and paste the output for debugging."
  fi
fi

# ---------------------------------------------------------------------------
cat <<EOF

============================================================
 9Router installed. To run it:

   9router --no-browser --host 127.0.0.1

 Dashboard : http://127.0.0.1:$PORT
 Endpoint  : http://127.0.0.1:$PORT/v1   (OpenAI-compatible)
 Password  : 123456 on a fresh install - CHANGE IT in the dashboard
 Data dir  : ~/.9router  (SQLite DB in ~/.9router/db/)

 Notes:
 - Server heap is capped at ${NODE_HEAP_MB} MB by the installer patch
   (upstream default: 6144 MB). If you see "heap out of memory" crashes
   under load, raise it:  NODE_HEAP_MB=1024 bash install-9router-termux.sh
 - Binding to 127.0.0.1 keeps it phone-only. The upstream default host is
   0.0.0.0 (LAN-visible) - only use that if you really need LAN access.
 - Add --skip-update if you want to stay pinned to v$PIN_VERSION.
 - Do NOT use --tray on Termux (desktop systray; its binary is not built
   for Android).
============================================================
EOF

#!/bin/sh
set -eu
sandbox=$(mktemp -d)
export XDG_CONFIG_HOME="$sandbox/config" XDG_STATE_HOME="$sandbox/state" XDG_DATA_HOME="$sandbox/data" XDG_CACHE_HOME="$sandbox/cache" XDG_RUNTIME_DIR="$sandbox/run"
export HERDR_SESSION="todo-agents-test-$$" HERDR_BIN_PATH
HERDR_BIN_PATH=$(command -v "${HERDR:-herdr}")
export HERDR_ENV=1 TODO_TEST_LAUNCHES="$sandbox/launches.jsonl"
unset HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_CONFIG_PATH
mkdir -p "$XDG_CONFIG_HOME/herdr" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
cat > "$XDG_CONFIG_HOME/herdr/config.toml" <<CONFIG
onboarding = false
[terminal]
default_shell = "/bin/sh"
[worktrees]
directory = "$sandbox/worktrees (test)"
[update]
version_check = false
manifest_check = false
CONFIG
cleanup() {
  "$HERDR_BIN_PATH" server stop >/dev/null 2>&1 || true
  wait "$server_pid" 2>/dev/null || true
  rm -rf "$sandbox"
}
"$HERDR_BIN_PATH" server >"$sandbox/server.log" 2>&1 &
server_pid=$!
trap cleanup EXIT
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if "$HERDR_BIN_PATH" workspace list >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.2
done
if [ "$ready" = 0 ]; then cat "$sandbox/server.log"; exit 1; fi
"${NVIM:-nvim}" --headless -u NONE -i NONE -l tests/run.lua
"${NVIM:-nvim}" --headless -u NONE -i NONE -l tests/reopen.lua

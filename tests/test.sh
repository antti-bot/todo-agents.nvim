#!/bin/sh
set -eu
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export XDG_STATE_HOME="$sandbox/state" XDG_DATA_HOME="$sandbox/data" XDG_CACHE_HOME="$sandbox/cache" CODEX_HOME="$sandbox/codex"
"${NVIM:-nvim}" --headless -u NONE -i NONE -l tests/run.lua

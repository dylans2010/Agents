#!/bin/sh
set -eu
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
exec python3 "$REPO_ROOT/scripts/sync-system-assets.py" "$@"

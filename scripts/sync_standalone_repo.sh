#!/usr/bin/env bash

set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
target_dir="${1:-}"

if [[ -z "$target_dir" ]]; then
  echo "usage: $0 /path/to/ex_did_repo" >&2
  exit 1
fi

if [[ ! -d "$target_dir/.git" ]]; then
  echo "target is not a git checkout: $target_dir" >&2
  exit 1
fi

rsync -a --delete \
  --exclude '.git/' \
  --exclude '_build/' \
  --exclude 'deps/' \
  --exclude 'doc/' \
  --exclude 'cover/' \
  --exclude 'scripts/upstream_parity/node_modules/' \
  --exclude 'scripts/upstream_parity/.npm/' \
  --exclude 'scripts/upstream_parity/.cache/' \
  --exclude 'test/fixtures/upstream/tmp/' \
  --exclude 'test/fixtures/upstream/debug/' \
  "$source_dir"/ "$target_dir"/

echo "Synced ex_did into $target_dir"
echo "Next:"
echo "  cd $target_dir"
echo "  git status"
echo "  mix test"

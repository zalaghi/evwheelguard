#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/set-github-username.sh YOUR_GITHUB_USERNAME_OR_ORG" >&2
  exit 2
fi

OWNER="$1"

find . -type f \
  \( -name '*.md' -o -name '*.toml' -o -name '*.sh' -o -name '*.service' \) \
  -not -path './.git/*' \
  -print0 | xargs -0 sed -i "s#zalaghi#$OWNER#g"

echo "Updated GitHub owner to: $OWNER"
echo "Review changes, commit, and push."

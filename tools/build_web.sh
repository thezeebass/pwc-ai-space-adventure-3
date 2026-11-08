#!/bin/zsh
# Build the web_pwa export and stamp a fresh build version into the loading shell.
#
# Rule: every build goes through this script, so the version number always
# updates. The version is derived from git, so it is reproducible and tells
# you exactly which commit a phone is running.
#
# Usage: tools/build_web.sh [--deploy | --deploy-b] [deploy message]
#   --deploy    ship to the main site (what the client sees)
#   --deploy-b  ship to the parallel B site (in-progress testing)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="/opt/homebrew/bin/godot"
OUT="$REPO/build/web"

cd "$REPO"

# Refuse to stamp a dirty tree: the version must map to a real commit.
if ! git diff-index --quiet HEAD --; then
  echo "build_web: working tree has uncommitted changes - commit first," >&2
  echo "  or the version number would not describe a real build." >&2
  exit 1
fi

HASH="$(git rev-parse --short HEAD)"
COUNT="$(git rev-list --count HEAD)"
STAMP="$(date '+%Y%m%d-%H%M')"
VERSION="b${COUNT}-${HASH}-${STAMP}"
echo "build_web: version $VERSION"

rm -rf "$OUT"
mkdir -p "$OUT"

"$GODOT" --headless --path "$REPO" --export-release web_pwa "$OUT/index.html" \
  > /tmp/godot_export.log 2>&1 || { tail -20 /tmp/godot_export.log; exit 1; }

# Stamp the version into the shell. The placeholder lives in web/pwc_loading_shell.html.
sed -i '' "s/__BUILD_VERSION__/$VERSION/g" "$OUT/index.html"
grep -q "BUILD $VERSION" "$OUT/index.html" \
  || { echo "build_web: version stamp missing from index.html" >&2; exit 1; }

# Network-first navigation so installed PWAs always launch the newest build.
python3 "$REPO/tools/patch_sw.py" "$OUT/index.service.worker.js" || exit 1

# Headers required for the audio/XR threading (docs/platforms.md).
cat > "$OUT/netlify.toml" <<'EOF'
[[headers]]
  for = "/*"
  [headers.values]
    Cross-Origin-Opener-Policy = "same-origin"
    Cross-Origin-Embedder-Policy = "require-corp"
EOF
## The deploy CLI reads netlify.toml from the working directory, not from the
## deploy folder, so the headers must sit at the repo root too.
cp "$OUT/netlify.toml" "$REPO/netlify.toml"

## The uplink (the leaderboard API) ships WITH the site: netlify/functions
## holds its source, and bundling needs the dependencies installed.
if [ ! -d "$REPO/netlify/functions/node_modules" ]; then
  (cd "$REPO/netlify/functions" && npm install --silent)
fi

echo "build_web: done - $OUT ($(stat -f %z "$OUT/index.pck") bytes pck)"

if [[ "${1:-}" == "--deploy" || "${1:-}" == "--deploy-b" ]]; then
  if [[ "$1" == "--deploy-b" ]]; then
    SITE_ID="1e4fb986-4792-4d78-b964-79a6bb840741"   # pwc-iom-space-b
  else
    SITE_ID="ba9bc1fe-3b42-4b08-ac8a-ef114cdab0c0"   # pwc-iom-space
  fi
  shift || true
  ## --functions is load-bearing: a static-only deploy REPLACES the site's
  ## functions, and the uplink goes dark - which is how it was lost on -l.
  netlify deploy --prod --site "$SITE_ID" --dir "$OUT" \
    --functions netlify/functions \
    --message "web_pwa $VERSION ${1:-}" 2>&1 | grep -E "Deployed|Unique|error" || true
fi

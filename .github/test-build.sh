#!/usr/bin/env bash
# A build of a branch other than main, started by hand, goes into the draft release "Test build" in
# place of the last one: a way to try it on a phone before it's out. Drafts show only to the owner of
# the repository, so nobody else sees it. Files of the same name are replaced.
#   bash .github/test-build.sh Mixtape-*.apk
set -euo pipefail

notes="Built from ${GITHUB_REF_NAME} at ${GITHUB_SHA::7}. A draft only you can see; the next test build replaces it."

# files of the same kind (.apk, .ipa) from an older version go first, so the draft holds the newest
tidy() {
  local keep=" " kinds=" "
  for f in "$@"; do
    keep+="$(basename "$f") "
    kinds+="${f##*.} "
  done
  for old in $(gh release view test-build --json assets --jq '.assets[].name' 2>/dev/null || true); do
    case "$kinds" in *" ${old##*.} "*) ;; *) continue ;; esac
    case "$keep" in *" $old "*) continue ;; esac
    gh release delete-asset test-build "$old" -y >/dev/null || true
  done
}

# the Android and the iPhone build can both get here at once: whoever comes second adds to it
for attempt in 1 2 3 4 5; do
  if gh release view test-build >/dev/null 2>&1; then
    tidy "$@"
    gh release edit test-build --target "$GITHUB_SHA" --notes "$notes" >/dev/null &&
      gh release upload test-build "$@" --clobber && exit 0
  else
    gh release create test-build "$@" --draft --target "$GITHUB_SHA" --title "Test build" --notes "$notes" && exit 0
  fi
  sleep 20
done
exit 1

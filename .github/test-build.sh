#!/usr/bin/env bash
# A build of a branch other than main, started by hand, goes into the draft release "Test build" in
# place of the last one: a way to try it on a phone before it's out. Drafts show only to the owner of
# the repository, so nobody else sees it. Files of the same name are replaced.
#   bash .github/test-build.sh Mixtape-*.apk
set -euo pipefail

notes="Built from ${GITHUB_REF_NAME} at ${GITHUB_SHA::7}. A draft only you can see; the next test build replaces it."

# the Android and the iPhone build can both get here at once: whoever comes second adds to it
for attempt in 1 2 3 4 5; do
  if gh release view test-build >/dev/null 2>&1; then
    gh release edit test-build --target "$GITHUB_SHA" --notes "$notes" >/dev/null &&
      gh release upload test-build "$@" --clobber && exit 0
  else
    gh release create test-build "$@" --draft --target "$GITHUB_SHA" --title "Test build" --notes "$notes" && exit 0
  fi
  sleep 20
done
exit 1

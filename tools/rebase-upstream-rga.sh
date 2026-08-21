#!/usr/bin/env bash
set -euo pipefail

branch="linux-rga-multi"
upstream_url="https://github.com/JeffyCN/mirrors.git"
push=0

case "${1:-}" in
    "") ;;
    --push) push=1 ;;
    -h|--help)
        cat <<'MSG'
Usage: tools/rebase-upstream-rga.sh [--push]

Fetch JeffyCN/mirrors:linux-rga-multi and rebase the local StableKite
linux-rga-multi commits onto it. No merge commit is created.

Without --push, the rebased branch remains local for review/testing.
With --push, the result is pushed with --force-with-lease.
MSG
        exit 0
        ;;
    *)
        echo "Usage: $0 [--push]" >&2
        exit 2
        ;;
esac

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Run this inside a Git checkout." >&2
    exit 1
fi

current_branch=$(git symbolic-ref --quiet --short HEAD || true)
if [[ "$current_branch" != "$branch" ]]; then
    echo "Expected branch '$branch', got '${current_branch:-detached HEAD}'." >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree/index is not clean. Commit or stash changes first." >&2
    exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    echo "Remote 'origin' is missing." >&2
    exit 1
fi

if git remote get-url upstream >/dev/null 2>&1; then
    configured=$(git remote get-url upstream)
    if [[ "$configured" != "$upstream_url" && "$configured" != "${upstream_url%.git}" ]]; then
        echo "Remote 'upstream' points to unexpected URL: $configured" >&2
        echo "Expected: $upstream_url" >&2
        exit 1
    fi
else
    git remote add upstream "$upstream_url"
fi

before=$(git rev-parse HEAD)
printf 'local before: %s\n' "$before"

git fetch --no-tags upstream \
    "+refs/heads/${branch}:refs/remotes/upstream/${branch}"

upstream_tip=$(git rev-parse "refs/remotes/upstream/${branch}")
printf 'upstream tip: %s\n' "$upstream_tip"

if git merge-base --is-ancestor "$upstream_tip" HEAD; then
    echo "Local branch already contains the current upstream tip; no rebase needed."
else
    old_base=$(git merge-base HEAD "$upstream_tip")
    printf 'old merge-base: %s\n' "$old_base"
    git rebase "$upstream_tip"
fi

after=$(git rev-parse HEAD)
printf 'local after:  %s\n' "$after"

merge_count=$(git rev-list --count --merges "${upstream_tip}..HEAD")
printf 'StableKite-only merge commits: %s\n' "$merge_count"
if [[ "$merge_count" != "0" ]]; then
    echo "Refusing to continue: merge commits exist above upstream." >&2
    exit 1
fi

if ((push)); then
    git push --force-with-lease origin "${branch}:${branch}"
    echo "Rebased branch pushed with --force-with-lease."
else
    cat <<'MSG'
Rebase check complete. Review/test this tree, then either run:
  tools/rebase-upstream-rga.sh --push
or push the already-reviewed branch explicitly with:
  git push --force-with-lease origin linux-rga-multi
MSG
fi

#!/usr/bin/env bash
set -euo pipefail

# Prune unrelated refs from a fork of JeffyCN/mirrors while preserving all branches
# that are directly part of the RGA project.  No kept branch is rewritten, so the
# current linux-rga-multi ancestry remains suitable for upstream rebases.

keep_branches=(
    linux-rga-multi
    linux-rga-im2d
    linux-rga
)
execute=0

case "${1:-}" in
    "") ;;
    --execute) execute=1 ;;
    *)
        echo "Usage: $0 [--execute]" >&2
        exit 2
        ;;
esac

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Run this from a Git checkout." >&2
    exit 1
fi

origin_url=$(git remote get-url origin 2>/dev/null || true)
if [[ -z "$origin_url" ]]; then
    echo "Remote 'origin' is missing." >&2
    exit 1
fi

declare -A keep_sha=()
for branch in "${keep_branches[@]}"; do
    line=$(git ls-remote --heads origin "refs/heads/${branch}" | head -n1 || true)
    if [[ -z "$line" ]]; then
        echo "Required RGA branch origin/${branch} does not exist." >&2
        exit 1
    fi
    keep_sha["$branch"]=${line%%[[:space:]]*}
done

is_kept_branch()
{
    local candidate=$1
    local keep
    for keep in "${keep_branches[@]}"; do
        [[ "$candidate" == "$keep" ]] && return 0
    done
    return 1
}

mapfile -t all_branches < <(
    git ls-remote --heads origin |
        awk '{sub("refs/heads/", "", $2); print $2}' |
        sort -u
)

branches=()
for branch in "${all_branches[@]}"; do
    if ! is_kept_branch "$branch"; then
        branches+=("$branch")
    fi
done

# Mirror-wide tags can point into non-RGA histories. Remove the tag refs; commits that
# are ancestors of any preserved RGA branch remain reachable through those branches.
mapfile -t tags < <(
    git ls-remote --tags --refs origin |
        awk '{sub("refs/tags/", "", $2); print $2}' |
        sort -u || true
)

printf 'origin: %s\n' "$origin_url"
printf 'preserved RGA branches:\n'
for branch in "${keep_branches[@]}"; do
    printf '  %s @ %s\n' "$branch" "${keep_sha[$branch]}"
done
printf 'unrelated branches to delete: %d\n' "${#branches[@]}"
printf 'tags to delete: %d\n' "${#tags[@]}"

if ((${#branches[@]})); then
    printf '\nBranches to delete:\n'
    printf '  %s\n' "${branches[@]}"
fi

if ((${#tags[@]})); then
    printf '\nTags to delete (first 40 shown):\n'
    printf '  %s\n' "${tags[@]:0:40}"
    if ((${#tags[@]} > 40)); then
        printf '  ... and %d more\n' "$(( ${#tags[@]} - 40 ))"
    fi
fi

if ((execute == 0)); then
    cat <<'MSG'

DRY RUN ONLY. No refs were modified.

The three RGA branches above and their complete histories will NOT be rewritten.
Run again with --execute to delete only the unrelated refs listed above:
  tools/compact-fork-history.sh --execute
MSG
    exit 0
fi

printf '\nDeleting unrelated remote branches without rewriting RGA history...\n'
if ((${#branches[@]})); then
    for ((i=0; i<${#branches[@]}; i+=50)); do
        git push origin --delete "${branches[@]:i:50}"
    done
fi

printf 'Deleting mirror-wide remote tags...\n'
if ((${#tags[@]})); then
    refs=()
    for tag in "${tags[@]}"; do
        refs+=(":refs/tags/${tag}")
    done
    for ((i=0; i<${#refs[@]}; i+=100)); do
        git push origin "${refs[@]:i:100}"
    done
fi

# Prove every preserved RGA branch stayed byte-for-byte at the same commit.
for branch in "${keep_branches[@]}"; do
    final_line=$(git ls-remote --heads origin "refs/heads/${branch}" | head -n1 || true)
    final_sha=${final_line%%[[:space:]]*}
    if [[ -z "$final_sha" || "$final_sha" != "${keep_sha[$branch]}" ]]; then
        echo "ERROR: origin/${branch} moved during pruning: ${keep_sha[$branch]} -> ${final_sha:-missing}" >&2
        exit 1
    fi
done

cat <<MSG

Ref pruning complete.
All three RGA branch tips were preserved unchanged.

Validate with an ordinary clone (no --depth/--filter/--single-branch):
  git clone ${origin_url} rga-compact-check

For future linux-rga-multi updates without merge commits:
  git remote add upstream https://github.com/JeffyCN/mirrors.git
  git fetch --no-tags upstream linux-rga-multi
  git rebase upstream/linux-rga-multi
  git push --force-with-lease origin linux-rga-multi
MSG

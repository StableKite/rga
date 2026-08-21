# Compact plain-clone repository while preserving RGA history

`StableKite/rga` is a GitHub fork of `JeffyCN/mirrors`, a multi-project mirror.  The
fork currently advertises many branch tips belonging to kernel, U-Boot, MPP, rkbin,
camera, Mali, Wi-Fi/Bluetooth and other projects.  Those refs are the source of the
multi-gigabyte ordinary clone.

The RGA histories themselves are retained.  The fork has three directly RGA-related
branches:

- `linux-rga-multi` — current branch and default branch;
- `linux-rga-im2d` — older im2d line that shares ancestry with the current line;
- `linux-rga` — independent legacy RGA line.

The compaction policy is **ref pruning, not history rewriting**:

- preserve all three RGA branches exactly, including their ancestors;
- delete every non-RGA branch from this fork;
- delete mirror-wide tags, which can advertise unrelated project histories;
- do not create replacement root commits or squash RGA history;
- do not force-rewrite the preserved RGA branches;
- do not detach/leave the GitHub fork network.

This preserves common Git ancestry for the current upstream branch.  New upstream
commits can therefore be consumed with rebase instead of merge commits.

Inspect the exact remote refs first:

```sh
tools/compact-fork-history.sh
```

Then execute the same audited set:

```sh
tools/compact-fork-history.sh --execute
```

The script records all three RGA branch SHAs before pruning and verifies that every
one remains unchanged afterward.

## Validate ordinary clone size

Use a completely ordinary clone; no shallow or partial-clone options are required:

```sh
git clone https://github.com/StableKite/rga.git rga-compact-check
cd rga-compact-check
git count-objects -vH
du -sh .git
```

GitHub repository-size metadata and unreachable-object garbage collection can lag
behind ref deletion.  New clones, however, no longer need objects reachable only
from deleted non-RGA refs.

## Update current RGA from upstream without merge commits

Configure upstream once:

```sh
git remote add upstream https://github.com/JeffyCN/mirrors.git
```

Then update only the current RGA branch and suppress unrelated upstream tags:

```sh
git fetch --no-tags upstream linux-rga-multi
git rebase upstream/linux-rga-multi
git push --force-with-lease origin linux-rga-multi
```

A rebase remains linear.  If upstream and local hardening modify the same lines, Git
will request a real conflict resolution, but it does not introduce a merge commit.

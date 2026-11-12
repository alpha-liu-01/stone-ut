#!/bin/sh
# Make the kernel fork (docs/roadmap-release.md item 4, step 1): crDroid's
# commit plus kernel/patches/ as commits, plus a commit adding
# kernel/config/halium-sunstone.fragment as
# arch/arm64/configs/halium-sunstone.fragment.
#
#   sh tools/make-kernel-fork.sh DIR [TAG]
#
# DIR: a new directory; it becomes a git worktree of
# third_party/android_kernel_xiaomi_sm6375 (sh tools/fetch-inputs.sh kernel)
# on the branch stone-ut. TAG: also tag the tip, for example boot-16bfa7b0
# for the kernel of boot image 16bfa7b0.
#
# The commits are reproducible: author, committer and dates come from the
# patch headers (the fragment commit takes the date of the fragment's last
# change in this repository), so the same inputs always give the same hashes.
# Nothing is pushed.
#
# The branch is regenerated: a new patch goes before the fragment commit, so
# the new branch does not fast-forward the published one. The tags are the
# permanent references (each published branch tip has one), so the branch is
# force-updated, with a lease on the previous release's tag:
#   git push --force-with-lease=stone-ut:refs/tags/<previous tag> <fork URL> stone-ut <tag>
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
KSRC="$ROOT/third_party/android_kernel_xiaomi_sm6375"
BASE=42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d
DIR=${1:?usage: sh tools/make-kernel-fork.sh DIR [TAG]}
TAG=${2:-}
FRAG=kernel/config/halium-sunstone.fragment

[ -d "$KSRC/.git" ] || { echo "no kernel checkout; run sh tools/fetch-inputs.sh kernel" >&2; exit 1; }
[ ! -e "$DIR" ] || { echo "$DIR exists" >&2; exit 1; }
git -C "$KSRC" cat-file -e "$BASE^{commit}"

# The patches' author is also the committer.
from=$(sed -n 's/^From: //p' "$ROOT"/kernel/patches/0001-*.patch | head -n 1)
GIT_COMMITTER_NAME=${from% <*}
GIT_COMMITTER_EMAIL=${from##*<}
GIT_COMMITTER_EMAIL=${GIT_COMMITTER_EMAIL%>}
export GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

git -C "$KSRC" worktree add -q -B stone-ut "$DIR" "$BASE"
git -C "$DIR" am -q --committer-date-is-author-date "$ROOT"/kernel/patches/*.patch

date=$(git -C "$ROOT" log -1 --format=%aD -- "$FRAG")
[ -n "$date" ] || { echo "$FRAG has no history in this repository" >&2; exit 1; }
cp "$ROOT/$FRAG" "$DIR/arch/arm64/configs/halium-sunstone.fragment"
git -C "$DIR" add arch/arm64/configs/halium-sunstone.fragment
GIT_AUTHOR_NAME=$GIT_COMMITTER_NAME GIT_AUTHOR_EMAIL=$GIT_COMMITTER_EMAIL \
GIT_AUTHOR_DATE=$date GIT_COMMITTER_DATE=$date \
    git -C "$DIR" commit -q -F - <<'EOF'
arm64: configs: add the Halium fragment for Ubuntu Touch on stone

Merged on top of moonstone_defconfig (the stone tree's defconfig) to run
Ubuntu Touch with Halium: SysV IPC and the IPC, PID and user namespaces
for the LXC Android container, VT, devtmpfs (mounted), fhandle, AppArmor
with the SELinux boot parameter, RNDIS and MTP USB functions, and
hci_vhci for bluebinder.

  make O=out ARCH=arm64 LLVM=1 moonstone_defconfig
  scripts/kconfig/merge_config.sh -O out out/.config \
      arch/arm64/configs/halium-sunstone.fragment
EOF

[ -z "$TAG" ] || git -C "$DIR" tag -f "$TAG" >/dev/null
git -C "$DIR" log --oneline "$BASE..HEAD"
echo "branch stone-ut at $(git -C "$DIR" rev-parse HEAD)${TAG:+, tag $TAG}"
echo "To publish: git -C $DIR push --force-with-lease=stone-ut:refs/tags/<previous tag> <fork URL> stone-ut${TAG:+ $TAG}"

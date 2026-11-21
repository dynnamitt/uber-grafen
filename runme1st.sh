#!/usr/bin/env bash
# Rename a repo created from the zig-rayflecs template, then delete this script.
# Usage: ./runme1st.sh [name]    name defaults to the GitHub repo name of `origin`.
# Leaves the changes unstaged: review `git diff`, then commit.
set -euo pipefail

TEMPLATE=zig-rayflecs TEMPLATE_OWNER=dynnamitt
TEMPLATE_PKG=${TEMPLATE//-/_}

cd "$(dirname "$0")"
slug=$(git remote get-url origin)
slug=${slug#*github.com[:/]} slug=${slug%.git} # owner/repo
owner=$(printf %s "${slug%%/*}" | tr '[:upper:]' '[:lower:]') repo=${slug#*/}
name=${1:-$repo}
pkg=${name//-/_}

[[ $pkg =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "name must be lowercase letters, digits, - or _: $name" >&2; exit 1; }
[[ $name != "$TEMPLATE" ]] || { echo "still named $TEMPLATE; pass a new name: ./runme1st.sh my-game" >&2; exit 1; }
grep -q "\.name = \.$TEMPLATE_PKG," build.zig.zon || { echo "build.zig.zon is already renamed; nothing to do" >&2; exit 1; }

# Computed before any edit, so a failure here leaves the repo untouched and re-runnable.
# zig rejects a fingerprint whose high 32 bits aren't crc32(name); the low 32 are a fresh random id (new package lineage, never 0 or 0xffffffff).
fp=$(perl -MCompress::Zlib -e 'printf "0x%08x%08x", crc32($ARGV[0]), 1 + int(rand(0xfffffffe))' "$pkg")

# Drop the template-only notes (blocks or inline) before renaming.
perl -0pi -e 's/<!-- template -->.*?<!-- \/template -->\n{0,2}//gs' README.md CLAUDE.md

# The URL goes last: by then the name pass has turned it into OLD_URL, and NEW_URL must not be renamed again.
export OLD_URL="$TEMPLATE_OWNER.github.io/$name" NEW_URL="$owner.github.io/$repo"
export TEMPLATE TEMPLATE_PKG name pkg
git grep -lzI -e "$TEMPLATE" -e "$TEMPLATE_PKG" -- . ':!runme1st.sh' ':!.github' |
  xargs -0 perl -pi -e 's/\Q$ENV{TEMPLATE}\E/$ENV{name}/g; s/\Q$ENV{TEMPLATE_PKG}\E/$ENV{pkg}/g; s/\Q$ENV{OLD_URL}\E/$ENV{NEW_URL}/g'

perl -pi -e "s/\\.fingerprint = 0x[0-9a-f]+/.fingerprint = $fp/" build.zig.zon

rm -- runme1st.sh
git status --short
echo "Renamed to $name ($owner/$repo). Review 'git diff', commit, and set Settings → Pages → Source: GitHub Actions."

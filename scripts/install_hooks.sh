#!/usr/bin/env bash
# Point git at the version-controlled hooks in .githooks/.
#
# Hooks in .git/hooks are invisible to the repo and vanish on a fresh clone,
# which is no good for a rule that has to hold on every machine and in every
# unattended run. core.hooksPath moves them into the tree instead.
#
# Run once per clone:  ./scripts/install_hooks.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "error: not a git repository" >&2
  exit 1
}

chmod +x .githooks/*
git config core.hooksPath .githooks

echo "core.hooksPath = $(git config core.hooksPath)"
echo "installed:"
for hook in .githooks/*; do
  [ -f "${hook}" ] && echo "  $(basename "${hook}")"
done

# Prove the commit-msg hook actually rejects what it is supposed to, rather than
# trusting that it was installed correctly.
probe="$(mktemp)"
trap 'rm -f "${probe}"' EXIT
printf 'test\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' >"${probe}"

if .githooks/commit-msg "${probe}" >/dev/null 2>&1; then
  echo "error: the commit-msg hook did NOT reject an attributed message" >&2
  exit 1
fi
echo "verified: attributed commit messages are rejected"

# AGENTS.md

Working notes for any agent (human or AI) touching this repository.

## Build folders

Build output must never pollute the repository tree while developing.

- Build out of source, in an ignored folder: \`build/\` or \`dist/\`. Never build in the source folders and never commit what a build makes (objects, binaries, `.dSYM`, caches, `dist/`, `out/`, `node_modules/`).
- Experiments and one-off test builds go in a scratch folder outside the repo (`mktemp -d`, or the session scratchpad), not in a new `build-<name>/` here. If one has to live here, it must match an ignored pattern and be deleted when the test ends.
- Logs, snapshots, tarballs and other temporary files from a task stay outside the repo too (or under an ignored folder), and are removed when the task is done.
- Before finishing, run `git status --short --ignored`: nothing you generated should show as untracked. If a new kind of build output appears, add it to `.gitignore` in the same change.
- Remove git worktrees once their PR is merged (`git worktree remove <path>`, then `git worktree prune`).

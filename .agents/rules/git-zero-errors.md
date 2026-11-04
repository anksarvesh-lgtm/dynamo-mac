# Zero Git Errors Rule (Mandatory for All Time)

To guarantee that not a single Git error occurs during operations across any repository or branch, all Git operations must strictly follow these pre-flight checks, validation protocols, and execution safeguards:

## 1. Pre-Flight State Verification
- **Check Working Directory & Staging**: Always inspect `git status --porcelain` or `git status` before executing any commit, add, stash, or branch command.
- **Never Commit on Clean Tree**: Never execute `git commit` if there are no changes to commit (`git status --porcelain` is empty). Committing on a clean working tree fails with exit code 1.
- **Verify File Paths Before Staging**: Never guess or hardcode file paths in `git add <path>` or `git commit <path>`. Always verify the exact path exists on disk (`test -f <path>` or `git status`) before passing it to git.
- **Index Lock Prevention**: Check for stale `.git/index.lock` before starting file-modifying git commands. If another git process is running or aborted abnormally, wait for it or ensure the lock is safely resolved.

## 2. Safe Committing Protocol
- When staging specific files, ensure paths match `git status` output exactly.
- Prefer staging verified modified files with `git add <path1> <path2>` or using `git commit -am "<message>"` only when all tracked modifications are intentional.
- Verify staging with `git diff --cached --quiet` (if exit code 0, nothing is staged; do not run commit without `--allow-empty` or staging files first).

## 3. Safe Branching, Rebase & Merging
- Always check the current branch with `git branch --show-current` or `git status` before branching, merging, or pushing.
- Never perform operations in a detached HEAD state unless specifically intended for read-only inspection.
- Pull remote changes cleanly with `--rebase` or check remote tracking status (`git fetch origin`) before applying local changes to prevent diverged branch rejection.

## 4. Safe Tagging Protocol
- Check whether a tag already exists using `git rev-parse -q --verify "refs/tags/<tag_name>"` or `git tag -l <tag_name>`.
- When updating or moving an existing release tag (such as `app` or a re-release), always pass `-f` (force update): `git tag -f <tag_name> -m "<message>"`.
- When pushing tags, pass `-f` if existing tags on the remote are being overwritten: `git push origin --tags -f`.

## 5. Safe Remote Pushing Protocol
- Always verify remote origin exists with `git remote -v`.
- Check if local branch is ahead or diverged using `git status` or `git log origin/<branch>..<branch>`.
- If the remote has new commits, fetch and rebase first before pushing to prevent non-fast-forward rejection.
- If upstream branch is not set, use `git push -u origin <branch>` to prevent "fatal: The current branch has no upstream branch".

## 6. Error Trapping & Recovery
- Any script or compound command executing git (`git add ... && git commit ... && git push ...`) must test each step or verify preconditions so that failure cascades never leave an ambiguous state.
- Always inspect command exit codes and stderr immediately. Never ignore a git warning or error.

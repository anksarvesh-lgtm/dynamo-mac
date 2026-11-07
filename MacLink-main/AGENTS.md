# Workspace Rules

## Build Rule
- **Only build the app when explicitly told by the user. If not mentioned, do not build the app.**
- Verification may use fast checks (like `cargo check` or linting), but do not run full packaging, release builds, or build scripts (`build-all.sh`, `macdeployqt`, etc.) unless the user explicitly requests a build.

## Zero Git Errors Rule
- **Pre-flight Status Check:** Always inspect `git status --porcelain` before staging or committing. Never attempt `git commit` on a clean working tree or without staged changes.
- **Path Verification:** Verify exact path existence before invoking `git add` or `git checkout`.
- **Safe Remote Operations:** Always explicitly specify remote and refspec (e.g., `git push origin <branch>`), ensuring remote connectivity and tracking branch validity.
- **Moving Tags:** Use `-f` flag when deliberately updating moving tags (`git tag -f <tag>` and `git push -f origin <tag>`).
- **Submodule Cleanliness:** Ensure child submodules (`nectarlink`) are committed, pushed, and clean before updating parent submodule pointer commits.



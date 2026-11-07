# Contributing to ILoveNotch

Thanks for helping. ILoveNotch is a clean-room, MIT-licensed project, so a few
rules matter more than usual.

## Where to start

- **Question or idea?** Open a [Discussion](https://github.com/niyamvora/ILoveNotch/discussions).
- **Bug or feature request?** Open an [issue](https://github.com/niyamvora/ILoveNotch/issues/new/choose)
  with its template. For anything bigger than a small fix, agree on the approach in the
  issue before writing the PR.
- **Looking for something to do?** Try [good first issues](https://github.com/niyamvora/ILoveNotch/labels/good%20first%20issue).

## Clean-room rules

- Write original code. Never copy code, assets, icons, or strings from
  closed-source apps, and never paste code from GPL-licensed projects.
- Never commit third-party app bundles, extracted binaries, or disassembly.
  `.gitignore` blocks the common cases; don't work around it.
- Dependencies must be permissively licensed (MIT, BSD, Apache-2.0, ISC, zlib)
  and listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Describe features by behavior (see [docs/parity-checklist.md](docs/parity-checklist.md)),
  never by how another app implements them.

## Development

Build and test commands live in the [README](README.md#build--run). Run
`make check` before pushing; CI runs the same targets.

## Branches

`main` is what ships. `dev` is where work lands first, and it reaches `main`
by fast-forward, so both keep the same commits:

```text
feat/xyz ──merge──▶ dev ──pull request, CI──▶ main
```

1. **Branch off `dev`** for each change. Parallel work, such as another Claude
   session, gets its own branch:
   `git switch dev && git pull && git switch -c feat/xyz`
2. **Build and test it** on your Mac: `make install`.
3. **Merge it into `dev`** without a pull request: CI doesn't run on `dev`, so
   one would add a step and check nothing. Rebase first if `dev` moved:
   `git rebase dev feat/xyz && git switch dev && git merge --ff-only feat/xyz && git push`,
   then delete the branch.
4. **Open one pull request from `dev` into `main`** when `dev` is ready to ship.
   CI runs there, in about three and a half minutes. A draft waits until it's
   marked ready for review, and a change to docs alone passes without building.
   To run CI without a pull request, use the Actions tab.
5. **Once it's green, `make ship`.** It fast-forwards `main` to `dev`, only if
   `dev` is what the pull request tested and every required check passed, and
   GitHub marks the pull request merged. The commits keep their hashes, so
   `dev`, `main`, and every open branch stay in step. GitHub still deletes the
   merged `dev` branch, and the Sync dev workflow puts it back within a minute.

Don't merge that pull request with its **Rebase and merge** button: the button
copies the commits onto `main` with new hashes. The Sync dev workflow then puts
`dev` back on `main`, but a branch still open off the old `dev` carries stale
copies and needs `git rebase --onto origin/dev <old dev> <branch>`, and a local
`dev` needs `git fetch && git reset --hard origin/dev`.

A pull request from outside goes straight into `main` and is merged with that
button; then bring `dev` up with
`git switch dev && git rebase origin/main && git push --force-with-lease`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): imperative summary under 72 characters

Optional body explaining why the change is needed, wrapped at 72.
```

Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`,
`style`, `chore`. Scopes are module names such as `core` or `surface`. Keep each
commit to one logical change that builds and passes tests on its own.

## Pull requests

- Keep PRs small and focused; fill in the template.
- A change people will notice adds a line under **Unreleased** in
  [CHANGELOG.md](CHANGELOG.md), in the same commit.
- CI must pass before merge.
- Feature PRs report idle CPU and memory measured with Instruments. The budgets
  are in the [implementation plan](docs/plan/implementation-plan.md#8-performance-gates).
- Prefer rebase over squash when the history tells a story; `main` takes no
  merge commits.

## Versioning and releases

ILoveNotch follows [Semantic Versioning](https://semver.org/), with a `vX.Y.Z`
tag on the exact commit each release was built from: a patch version for fixes,
a minor one for new features, and a major one for a change that breaks
something people rely on, such as dropping a macOS version. A pre-release
carries a suffix, as in `v1.3.0-beta.1`. `MARKETING_VERSION` in `project.yml`
names the latest release, so a build from source says where it stands.

[CHANGELOG.md](CHANGELOG.md) records every notable change the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) way: **Added**,
**Changed**, **Fixed**, and **Removed**, in words for the people who use the
app, not the code. Changes collect under **Unreleased**; a release renames that
section to its version and date. Each version's section is its release notes,
at the top of the GitHub release and in the app's update prompt, and CI fails a
pull request whose version has none.

Releases ship as signed, notarized DMGs on
[GitHub Releases](https://github.com/niyamvora/ILoveNotch/releases), through
Sparkle to installed copies, and through the Homebrew cask. The steps are in
[docs/releasing.md](docs/releasing.md).

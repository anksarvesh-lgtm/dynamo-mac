# GitHub Releases & Update Distribution Rules

These rules govern version releases, CI/CD packaging, in-app updates, and asset uploads for LiquidDynamo.

---

## 1. Git Tag vs. GitHub Release (Critical)

1. **A Git Tag is NOT a GitHub Release**:
   - Running `git push origin v{version}` only creates a git tag in Git history. It does **NOT** create a GitHub Release and does **NOT** update GitHub's `releases/latest` API.
   - The in-app update checker (`GitHubUpdateChecker.swift`) queries:
     `https://api.github.com/repos/anksarvesh-lgtm/dynamo-mac/releases/latest`
   - If a Git Tag is pushed without publishing an official GitHub Release, the GitHub API will continue returning the previous release tag, and **installed older versions will fail to detect the new update**.

2. **Mandatory Version Bump & Build on Every Push**:
   - Every single time any code, fix, or feature update is made to the app before pushing:
     1. Bump `MARKETING_VERSION` (semver) and `CURRENT_PROJECT_VERSION` (integer build number) in `LiquidDynamo.xcodeproj/project.pbxproj`.
     2. Update `CHANGELOG.md`, `README.md`, and version fallbacks.
     3. Build the application and package the DMG and update zip (`INSTALL_APP=false bash build_dmg.sh`).
     4. Tag the commit: `git tag -a v{version} -m "Release v{version}"`.
     5. Push commits and tag: `git push origin main && git push origin v{version}` to both remotes.
     6. **Publish the GitHub Release**: Run `swift scripts/publish_release_assets.swift` to upload `LiquidDynamo-{version}.dmg`, `LiquidDynamo.dmg`, and `liquiddynamo.zip` to both repositories.

---

## 2. Dual-Repository Synchronization

LiquidDynamo maintains active remote mirrors. Release operations must publish to both:
- `anksarvesh-lgtm/dynamo-mac`
- `anksarvesh-lgtm/dynamomac`

Both repositories must have:
1. The versioned tag release (`v{version}`) with notes from `CHANGELOG.md`.
2. The rolling `app` tag release updated with the latest `LiquidDynamo.dmg` and `liquiddynamo.zip` assets for permanent download URLs.

---

## 3. GitHub Actions CI/CD Secrets Resilience

In `.github/workflows/release.yml`:
1. **Never Hard-Fail on Missing Secrets**:
   - Do not exit with code 1 if `DEVELOPER_ID_CERTIFICATE_BASE64` or notary credentials are unset.
   - If secrets exist: Execute full Developer ID inside-out signing, two-stage Apple Notarization, stapling, and verification.
   - If secrets are missing: Log a warning (`::warning::`), fall back to standard DMG and zip packaging, and upload assets to the GitHub Release.
2. **Always Upload Both Artifacts**:
   - Every CI release build must upload both `LiquidDynamo-{version}.dmg` and `liquiddynamo.zip` so the in-place auto-updater and direct installers function seamlessly.

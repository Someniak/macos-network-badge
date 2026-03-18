# Releasing Network Badge

## Overview

Releases are fully automated via GitHub Actions. There are two ways to release:

1. **Branch push** — push a `release/v*` branch to trigger a full release with automatic merge-back
2. **Manual dispatch** — trigger from the Actions UI with version, draft, and pre-release options

The pipeline validates the version, stamps `Info.plist`, runs tests, builds a signed `.app` bundle, creates a DMG with SHA256 checksum, publishes a GitHub Release, and opens a merge-back PR.

## Option A: Branch-Based Release

### 1. Create the release branch

```bash
git checkout main
git pull origin main
git checkout -b release/v1.2.0    # use your version number
```

### 2. Push the release branch

```bash
git push -u origin release/v1.2.0
```

That's it. The pipeline handles everything automatically:

1. Validates the version is valid semver
2. Checks the tag doesn't already exist
3. Stamps `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`
4. Runs the full test suite
5. Builds the `.app` bundle
6. Creates the DMG
7. Generates SHA256 checksum
8. Uploads build artifacts (retained 90 days)
9. Tags the commit as `v1.2.0`
10. Creates a GitHub Release with DMG and checksum attached
11. Opens a PR to merge the release branch back to `main`

### 3. Verify and merge back

Check the [Actions tab](../../actions) to confirm the pipeline succeeded, then visit the [Releases page](../../releases) to verify the DMG is attached.

A merge-back PR is created automatically. Review and merge it, then delete the release branch.

> **Note:** You no longer need to manually bump `Info.plist` — the pipeline stamps the version automatically from the branch name.

## Option B: Manual Dispatch

1. Go to **Actions** > **Release** > **Run workflow**
2. Enter the version (e.g., `1.2.0`)
3. Optionally check **Create as draft release** or **Mark as pre-release**
4. Click **Run workflow**

This is useful for:
- Creating draft releases for review before publishing
- Releasing pre-release versions (e.g., `1.2.0-beta.1`)
- Triggering a release from any branch without the `release/v*` naming convention

## Versioning

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR** — breaking changes or major redesigns
- **MINOR** — new features, backward-compatible
- **PATCH** — bug fixes

Pre-release suffixes are supported (e.g., `1.2.0-beta.1`, `2.0.0-rc.1`).

The version is validated as semver by the pipeline — invalid formats will fail fast.

## What Gets Published

Each GitHub Release includes:

- **NetworkBadge.dmg** — ready-to-install disk image
- **NetworkBadge.dmg.sha256** — SHA256 checksum for download verification
- **Auto-generated release notes** — commit history since the previous tag
- **Installation instructions** and checksum verification command in the release body

Build artifacts (DMG, checksum, `.app` bundle) are also uploaded as workflow artifacts with 90-day retention.

## Pipeline Features

| Feature | Detail |
|---------|--------|
| Version validation | Semver regex check, fails fast with clear error |
| Auto version stamp | `Info.plist` updated automatically — no manual bump needed |
| Build caching | Swift build artifacts cached between runs |
| SHA256 checksum | Generated and attached to release + embedded in release notes |
| Artifact retention | DMG, checksum, and `.app` uploaded for 90 days |
| Concurrency control | Only one release runs at a time (queued, never cancelled) |
| Draft/pre-release | Supported via manual dispatch inputs |
| Merge-back PR | Automatically created for branch-triggered releases |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Pipeline fails at version validation | Ensure the branch name or input follows semver (e.g., `1.2.0`, not `v1.2.0` or `1.2`) |
| Pipeline fails at tests | Fix the failing tests on the release branch, commit, and push again |
| Tag already exists | A previous release used this version. Bump to a new version (e.g., `v1.2.1`) |
| DMG not attached | Check the build logs — `scripts/create-dmg.sh` may have failed. Build artifacts are still available in the workflow run |
| Merge-back PR not created | Check that the `GITHUB_TOKEN` has `pull-requests: write` permission. You can manually merge the release branch |
| Concurrent release queued | The pipeline uses `cancel-in-progress: false` — the second release will wait for the first to finish |

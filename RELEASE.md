# Releasing Network Badge

## Overview

Releases are automated via GitHub Actions. Pushing a `release/v*` branch triggers the pipeline which runs tests, builds a DMG, and publishes a GitHub Release.

## How to Release

### 1. Prepare the release branch

```bash
git checkout main
git pull origin main
git checkout -b release/v1.2.0    # use your version number
```

### 2. Bump the version (if needed)

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>1.2.0</string>
<key>CFBundleVersion</key>
<string>3</string>
```

Commit the change:

```bash
git add Resources/Info.plist
git commit -m "Bump version to 1.2.0"
```

### 3. Push the release branch

```bash
git push -u origin release/v1.2.0
```

This triggers the release pipeline which will:

1. Run the full test suite
2. Build the `.app` bundle (`scripts/build-app.sh`)
3. Create the DMG (`scripts/create-dmg.sh`)
4. Tag the commit as `v1.2.0`
5. Create a GitHub Release with the DMG attached

### 4. Verify the release

Check the [Actions tab](../../actions) to confirm the pipeline succeeded, then visit the [Releases page](../../releases) to verify the DMG is attached.

### 5. Merge back to main

```bash
git checkout main
git merge release/v1.2.0
git push origin main
git push origin --delete release/v1.2.0
```

## Versioning

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR** — breaking changes or major redesigns
- **MINOR** — new features, backward-compatible
- **PATCH** — bug fixes

## What Gets Published

Each GitHub Release includes:

- **NetworkBadge.dmg** — ready-to-install disk image
- **Auto-generated release notes** — commit history since the previous tag

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Pipeline fails at tests | Fix the failing tests on the release branch, commit, and push again |
| Tag already exists | A previous release used this version. Bump to a new version (e.g., `v1.2.1`) |
| DMG not attached | Check the build logs — `scripts/create-dmg.sh` may have failed. Ensure `hdiutil` commands work on the CI runner |

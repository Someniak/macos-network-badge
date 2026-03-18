---
name: release
description: Create a new release of Network Badge
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(swift *), Bash(gh *)
argument-hint: [version]
---

Create a new release of Network Badge with version `$ARGUMENTS`.

## Current state

- Working tree: !`git status --short`
- Current branch: !`git branch --show-current`
- Recent tags: !`git tag --list 'v*' --sort=-v:refname | head -5`

## Steps

Follow these steps in order. Stop and report if any step fails.

### 1. Validate version

Confirm `$ARGUMENTS` is valid semver (e.g., `1.2.0`, `2.0.0-beta.1`). It must match the pattern `X.Y.Z` with an optional pre-release suffix. Do NOT include a leading `v`. If invalid, stop and tell the user the correct format.

### 2. Check preconditions

- The working tree must be clean (no uncommitted changes). If dirty, stop and ask the user to commit or stash.
- Confirm tag `v$ARGUMENTS` does not already exist. If it does, stop and tell the user.

### 3. Switch to main and pull latest

```bash
git checkout main
git pull origin main
```

### 4. Create release branch

```bash
git checkout -b release/v$ARGUMENTS
```

### 5. Run tests

```bash
swift test
```

If tests fail, stop and report the failures. Do not push a broken release.

### 6. Push the release branch

```bash
git push -u origin release/v$ARGUMENTS
```

This triggers the GitHub Actions release pipeline which will automatically:
1. Validate the version and stamp `Info.plist`
2. Build the `.app` bundle and create the DMG
3. Generate SHA256 checksum
4. Tag the commit as `v$ARGUMENTS`
5. Create a GitHub Release with the DMG attached
6. Open a merge-back PR to `main`

### 7. Report success

Tell the user:
- The release branch has been pushed
- The GitHub Actions pipeline is now running
- They can monitor progress in the **Actions** tab
- A merge-back PR will be created automatically once the pipeline completes
- After the PR is merged, the release branch can be deleted

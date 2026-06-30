---
name: release
description: Merge develop into main and cut a versioned release tag. Use when ready to ship a stable release.
---

# Release

## 1. Determine the version

If a version tag was passed as an argument (e.g. `/release v0.2.0`), use it. Otherwise, show the user the last few tags and ask what the next version should be:

```bash
git tag --sort=-version:refname | head -10
```

Follow semantic versioning:
- **Patch** (`v0.x.y+1`): bug fixes only
- **Minor** (`v0.x+1.0`): new features, backwards-compatible
- **Major** (`v1.0.0`): breaking changes or major milestone

## 2. Verify the working tree and show what will ship

```bash
git status                        # must be clean
git log --oneline main..develop   # commits being released
```

Summarize the commits for the user before proceeding. If the working tree is dirty, stop and ask them to commit or stash first.

## 3. Merge develop → main

```bash
git checkout main
git pull origin main
git merge --no-ff develop -m "Release <version>"
```

## 4. Tag the release

```bash
git tag -a <version> -m "Release <version>"
```

## 5. Push main and the tag

```bash
git push origin main
git push origin <version>
```

## 6. Return to develop

```bash
git checkout develop
```

## 7. iOS app version reminder

If any files under `App/` changed since the last release, remind the user to update `CFBundleShortVersionString` (marketing version, e.g. `0.2.0`) and increment `CFBundleVersion` (build number) in Xcode before the next TestFlight or App Store submission. Docs-only releases don't require a version bump.

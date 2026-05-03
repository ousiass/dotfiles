---
name: release-en
description: Generate changelog, version tag, GitHub release notes, and registry publish.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# release-en

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **Version** (e.g., `/release-en v1.2.0`): Release with specified version
- **Version type** (e.g., `/release-en patch`): Auto-determine from current version
- **No arguments**: Suggest version type based on changes and confirm with user

## Phase 0: Release Options

### 0-1. Manifest Detection

Detect the following at project root to identify publish candidates:

| Manifest | Registry | Publish command |
|---|---|---|
| `package.json` | npm | `npm publish` |
| `pyproject.toml` / `setup.py` | PyPI | `python -m build && twine upload dist/*` |
| `Cargo.toml` | crates.io | `cargo publish` |
| `*.gemspec` | RubyGems | `gem build && gem push` |
| `*.csproj` / `*.nuspec` | NuGet | `dotnet pack && dotnet nuget push` |
| `mix.exs` | Hex | `mix hex.publish` |

For monorepo (`workspaces`, `pnpm-workspace.yaml`, `lerna.json`), confirm target packages with user.

**Skip publish (do not ask user) if any of the following apply:**

- `package.json` has `"private": true`
- CI workflows (`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`, etc.) already contain a publish step
- Manifest has no `version` field
- Project is clearly an application (not a library)

### 0-1b. CI Release Detection

Scan CI workflows (`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`, etc.) to determine **whether CI creates the GitHub Release**.

**Set `ci_creates_release = true` if any of the following are detected:**

- `goreleaser` / `goreleaser-action` (GoReleaser)
- `softprops/action-gh-release`
- `ncipollo/release-action`
- `gh release create` executed within a workflow
- Any other Action or script that creates a GitHub Release

When `ci_creates_release = true`, skip `gh release create` in Phase 6 (delegate to CI via tag push).

### 0-2. User Confirmation

Confirm with `AskUserQuestion`:

1. **Branch merge**: Merge a branch before release? (confirm source and target)
2. **Binary build**: Attach build artifacts? (confirm build command and artifact path)
3. **Registry publish**: Shown only when manifest is detected and none of the "skip" conditions above apply. Ask "Publish to <registry>?" (also confirm OTP requirement, `--access public` for scoped packages, etc. as needed)

## Phase 1: Merge (if applicable)

1. Check if source branch is up to date (`git fetch && git log`)
2. Checkout target -> `git merge --no-ff <source>`
3. If conflicts exist, report to user and abort

## Phase 2: Collect Changes

1. Get latest release tag (`gh release list` / `git tag`)
2. Collect commits and merged PRs since last release
3. Classify by change category (see `templates/changelog.md`)

## Phase 3: Version Decision

1. If version specified in arguments -> use as-is
2. If not specified -> suggest based on changes:
   - Breaking changes -> **major**
   - New features -> **minor**
   - Bug fixes/improvements only -> **patch**
3. Confirm with user for agreement

## Phase 4: Changelog Generation

1. Check if `CHANGELOG.md` exists (create new if not, prepend if exists)
2. Add entries in the format from `templates/changelog.md`
3. Each entry in `English / Japanese` bilingual format. Generate from commit messages

## Phase 5: Version Update (registry publish only)

Update version in manifest files:

| Registry | Target | Method |
|---|---|---|
| npm | `package.json` `version` | `npm version <ver> --no-git-tag-version` |
| PyPI | `pyproject.toml` `version` / `setup.py` | Direct edit |
| crates.io | `Cargo.toml` `version` | Direct edit |
| RubyGems | gemspec `version` | Direct edit |
| NuGet | csproj `Version` | Direct edit |
| Hex | `mix.exs` `version` | Direct edit |

Also update lock files (`package-lock.json`, `Cargo.lock`, etc.) if needed.

## Phase 5b: Build (if applicable)

1. Run build command
2. Verify artifacts exist
3. If failed, report to user and abort

## Phase 6: Release Creation

1. Commit changelog (`docs: add changelog for v<version>`)
2. Create tag (`git tag v<version>`)
3. Push (`git push && git push --tags`)
4. **If `ci_creates_release = false`:** Create release with `gh release create v<version>` (attach artifacts if any)
   **If `ci_creates_release = true`:** Skip `gh release create` as CI will create the release from the tag push. Report "CI will create the release" to user
5. Report release URL to user (when delegated to CI, provide the CI workflow URL instead)

## Phase 7: Registry Publish (if applicable)

Execute only when publish was approved in Phase 0.

1. Run dry-run for pre-check (`npm publish --dry-run`, `twine check dist/*`, etc.)
2. Show dry-run results to user and get final confirmation
3. Execute publish
4. Report package URL on registry to user

**Commands by registry:**

| Registry | Dry-run | Publish |
|---|---|---|
| npm | `npm publish --dry-run` | `npm publish` (scoped: `--access public`) |
| PyPI | `twine check dist/*` | `twine upload dist/*` |
| crates.io | `cargo publish --dry-run` | `cargo publish` |
| RubyGems | `gem build *.gemspec` | `gem push *.gem` |
| NuGet | `dotnet pack` | `dotnet nuget push` |
| Hex | `mix hex.publish --dry-run` | `mix hex.publish` |

If OTP is required, prompt user for input.

## Rules

- Always get user agreement before finalizing version
- Changelog must be fact-based. Use commit messages and PR titles as source
- Always mark breaking changes in the warning section
- Confirm with user before pushing to remote and creating release
- Track progress with TaskCreate/TaskUpdate

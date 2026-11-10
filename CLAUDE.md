# Prepped

WoW Forever addon (interface 16001).

## Every change ships as a release

Every PR that changes the addon must bump `## Version:` in `prepped.toc` in the same PR:

- patch (`2.5.0` -> `2.5.1`): fixes and small tweaks
- minor (`2.5.0` -> `2.6.0`): new reminders, options or features
- major: breaking changes to settings or behaviour

`.github/workflows/release.yml` publishes a GitHub release (tag `v<version>-release`) when a push to `main` changes `prepped.toc`. So bumping the version and merging is what makes the release. Without the bump, no release happens.

Before merging, check that no `v<version>-release` tag exists for the new version.

## Tests

```bash
lua5.1 tests/run.lua
```

Add scenarios to `tests/run.lua` (and mock data to `tests/mock_client.lua`) for new reminders. Document user-visible changes in `README.md`.

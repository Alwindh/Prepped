# Prepped

WoW Forever addon (interface 16001).

## Every change ships as a release

Every PR that changes the addon must bump `## Version:` in `prepped.toc` in the same PR:

- patch (`2.5.0` -> `2.5.1`): fixes and small tweaks
- minor (`2.5.0` -> `2.6.0`): new reminders, options or features
- major: breaking changes to settings or behaviour

`.github/workflows/release.yml` publishes a GitHub release (tag `v<version>-release`) when a push to `main` changes `prepped.toc`. So bumping the version and merging is what makes the release. The `version` job in `tests.yml` fails a PR whose addon files changed without a bump, or whose new version already has a release tag.

## Tests

```bash
lua5.1 tests/run.lua
```

Add scenarios to `tests/run.lua` (and mock data to `tests/mock_client.lua`) for new reminders. Document user-visible changes in `README.md`.

## Conventions

- A reminder is one rule in its module's `Prepped:RegisterModule` list; the "Rules" comment in `core.lua` documents the fields. A rule's `id` is a key in players' saved settings: keep existing ids stable.
- Every text a player sees is `L["English text"]` with a literal string, translated in `locale_deDE.lua`, `locale_frFR.lua` and `locale_esES.lua` with the same placeholders; the tests list missing, stale or mismatched translations. Spell and item names come from the client (`C_Spell.GetSpellName`, `API.GetItemName`). `/prepped debug` output stays English.
- Secure click buttons (`display.lua`) change only out of combat and anchor to `UIParent`, never to the bars.
- A new global from the game API goes in `read_globals` in `.luacheckrc`; CI runs luacheck.

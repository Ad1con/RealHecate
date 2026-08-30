# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

Documentation and source tidying. No change to how the mod behaves.

- README: added a note that the mod may be useful for accessibility, with an
  invitation to raise an issue if effects like these would help elsewhere in the
  game.
- README: credited `LuaENVY-ENVY`, which is a declared dependency the credits had
  never named, and said what each dependency contributes.
- Trimmed the comments in `main.lua` from 55% of the file to 39%, moving the
  development rationale to a `DESIGN.md` that stays in the repository and is not
  packaged. Removed comments describing settings and a function that no longer
  exist.

## [1.0.0] - 2026-08-29

First public release.

Marks the real Hecate during her Triple Divide with a red glow on the ground and
a red outline, so she can be told from her two clones.

- Works in the ordinary fight, in the Rivals fight, and in Dream Dives.
- Adds only. The clones keep their own effects and so does Hecate; every removal
  is opt-in.
- Dream Dive fix: vanilla gives the base fight's clones the *same red outline* as
  the real Hecate, so the outline identifies nothing there. The clones' outline
  is removed so she is the only outlined one. No effect outside Dream runs.
- Eleven settings, all also on a panel in the modding overlay.
- Modifies no game files. Edits `EnemyData` in memory, attaches art that ships
  with the game, and wraps one function (`UnitSplit`).

[unreleased]: https://github.com/Ad1con/RealHecate/compare/1.0.0...HEAD
[1.0.0]: https://github.com/Ad1con/RealHecate/compare/cbb81f786e424f85f4498ccae59dd0d8cab83bc6...1.0.0
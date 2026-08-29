# Changelog

## Unreleased

## 5.3.0

First public release.

Marks the real Hecate during her Triple Divide with a red ground glow and a red
outline, so she can be told from her two clones.

- Works in the ordinary fight, in Extreme Measures / Rivals, and in Dream Dive.
- Adds only. The clones keep their own effects and so does Hecate; every removal
  is opt-in.
- Dream Dive fix: vanilla gives the base fight's clones the *same red outline* as
  the real Hecate, so the outline identifies nothing there. The clones' outline
  is removed so she is the only outlined one. No effect outside Dream runs.
- Eleven settings, all also on a panel in the modding overlay.
- Modifies no game files. Edits `EnemyData` in memory, attaches art that ships
  with the game, and wraps one function (`UnitSplit`).

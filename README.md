# Dumpster Delights

Dumpster Delights is a turn-based hybrid puzzle game built in Godot. It mixes deliberate Tetris-style piece placement with 2048-style number merging, but without a falling timer.

## Game pitch

- Place snack-shaped pieces carefully on a crowded board.
- Connect matching numbers into merge groups for bigger values.
- Think several turns ahead instead of reacting to gravity.
- Built for Godot web export so it can live on GitHub Pages.

## Current direction

The project now follows a modular, editor-configurable structure:

- `GameConfig` resource for board, scoring, colors, and piece lists.
- `PieceDefinition` resources for content-driven piece shapes and values.
- `BoardState` for authoritative board logic.
- `PieceGenerator` for isolated weighted randomness.
- `main.gd` for turn flow, input, HUD, and presentation.

## Run locally

1. Open the project in Godot 4.7.1 using `tools/local-godot/Godot_v4.7.1-stable_win64.exe` when available.
2. Press `F5` to run the game.
3. Use arrow keys to move the current piece.
4. Use `Q` / `E` to rotate when the piece allows it.
5. Press `Enter` to place the current piece.
6. Best score is saved locally between sessions.

## Preferred Godot build

Use the standard non-mono `4.7.1` Windows 64-bit build for this project.

Why this is the preferred choice:

- The project is GDScript-only and does not require C# or Mono support.
- `project.godot` already targets the `4.7` feature set.
- The standard build is smaller and simpler to maintain than the Mono distribution.
- The companion console executable is useful for headless validation without changing the runtime version.

## Repeatable rules checks

The deterministic board rules now have a small GDScript test harness:

- Test definitions: `res://tests/board_state_test.gd`
- Headless runner: `res://tests/run_rules_tests.gd`

From Godot, Ziva can validate the current core rules by running:

```text
tools/local-godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_rules_tests.gd
```

The current tests cover:

- Basic placement acceptance and rejection
- Merge resolution for connected equal-value groups
- Score changes matching merge outcomes
- Full-board move detection for simple pieces

## Export for GitHub Pages

1. In Godot, open `Project -> Export`.
2. Add the `Web` preset if Godot asks to install web export templates.
3. Export the project to `docs/index.html`.
4. Push the repository to GitHub on the `main` branch.
5. In GitHub repo settings, set Pages to `GitHub Actions`.

The workflow at `.github/workflows/deploy-pages.yml` deploys whatever is inside `docs/`, so after each fresh web export and push, the site updates automatically.

Until that first real export exists, `docs/index.html` is a temporary static landing page so GitHub Pages still has something decent to serve.

## Editor-facing content

- Change board size, spacing, score rules, and palette in `res://resources/config/default_game_config.tres`.
- Add new piece content by duplicating a file in `res://resources/pieces/`.
- Reassign a different config resource to the root `Main` scene if you want another rule set.

## Repository structure

- `assets/`
- `docs/`
- `resources/config/`
- `resources/pieces/`
- `resources/themes/`
- `scenes/`
- `scripts/board/`
- `scripts/core/`
- `scripts/managers/`
- `scripts/pieces/`
- `scripts/ui/`
- `scripts/utilities/`
- `tests/`
- `tools/local-godot/`

## Repository notes

- Local Godot executables belong in `tools/local-godot/` and are ignored by Git.
- The previous proprietary `addons/ziva_agent` dependency was removed during cleanup because it was not required for gameplay and was not appropriate to keep as a production project dependency.

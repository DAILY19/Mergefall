# Mergefall

Mergefall is a turn-based Godot puzzle game about positioning fixed-orientation tetromino pieces, dropping them into a 7x9 board, and building deterministic 2048-style merge waves. Spawn values progress from mostly low-value tiles toward 8 and 16 as completed turns accumulate, using the tunable phases in `resources/config/default_spawn_progression.tres`.

## Controls

- `<`: move the active piece left with the board-side control
- `DROP`: commit the active piece
- `>`: move the active piece right with the board-side control

Keyboard controls also work with Left Arrow, Right Arrow, Enter, and Down Arrow.

## Spawn Progression

Spawn values advance by completed turns only:

- Turns 0-15: 2 at 60%, 4 at 40%
- Turns 16-35: 2 at 40%, 4 at 50%, 8 at 10%
- Turns 36-65: 2 at 20%, 4 at 55%, 8 at 25%
- Turns 66-105: 4 at 45%, 8 at 45%, 16 at 10%
- Turns 106+: 4 at 20%, 8 at 55%, 16 at 25%

## Godot Version

Built and tested with Godot `4.7.1.stable` non-mono.

## Run Locally

Open `project.godot` in Godot 4.7.1 and run the main scene.

For headless startup validation:

```powershell
.\tools\local-godot\Godot_v4.7.1-stable_win64_console.exe --headless --quit
```

## Tests

```powershell
.\tools\local-godot\Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/run_rules_tests.gd
.\tools\local-godot\Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/falling_feel_test_runner.gd
```

## Web Export

The Web preset exports to `build/web/index.html`. GitHub Actions builds that export and deploys it through GitHub Pages.

GitHub Pages URL:

https://daily19.github.io/Mergefall/

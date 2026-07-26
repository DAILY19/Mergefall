# Mergefall

Mergefall is a turn-based Godot puzzle game about positioning fixed-orientation pieces, dropping them into a 6x7 board, and building deterministic 2048-style merge waves.

## Controls

- `LEFT`: move the active piece left
- `DROP`: commit the active piece
- `RIGHT`: move the active piece right

Keyboard controls also work with Left Arrow, Right Arrow, Enter, and Down Arrow.

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

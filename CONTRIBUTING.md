# Contributing

## Required Tools

- Godot `4.7.1.stable` non-mono.
- PowerShell for the repository validation script.

Set `MERGEFALL_GODOT` to the Godot console executable, install `godot` on `PATH`, or place a local download under `tools/local-godot/`. Local engine downloads are ignored by Git.

## Validation

Run the full local check:

```powershell
.\tools\validate.ps1
```

Run tests without exporting:

```powershell
.\tools\validate.ps1 -SkipExport
```

## Repository Layout

- `project.godot`, `scenes/`, `scripts/`, `resources/`, and `tests/` are source.
- Curated runtime assets live under `assets/`.
- `docs/` is for hand-written project notes, not the deployed Web build.
- `build/` contains local exports and is ignored.
- `.godot/`, `.import/`, editor settings, local AI metadata, downloaded tools, and uncurated asset packs are ignored.

## Deployment

GitHub Pages deploys from `.github/workflows/deploy-pages.yml`. The workflow imports the project, runs the rules and gameplay integration tests, exports the Web build into `build/web`, uploads that folder as a Pages artifact, and deploys it.

Do not commit generated Web output unless the deployment model intentionally changes.

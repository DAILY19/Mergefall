# Board Presentation Layer Update

Date: 2026-07-24

## Architecture introduced

- `Main` remains the gameplay controller and keeps turn flow, piece queueing, placement, merges, save/load, and undo state.
- `BoardView` is a reusable presentation component that renders the authoritative `BoardState`, the active-piece preview, empty and occupied cells, and merge/invalid placement feedback.
- `GameHUD` owns player-facing text, action buttons, toast messages, and preview-strip presentation.
- `PiecePreviewStrip` remains reusable and now supports inspector-assigned fonts and optional slot textures.

## Asset subset used

- Fonts:
  - `assets/fonts/Neatpixels Standard/neatpixels-standard.ttf`
  - `assets/fonts/Neatpixels Minimal/NeatpixelsMinimal.ttf`
- UI:
  - `assets/ui/Free Inventory/Inventory_background.png`
  - `assets/ui/Free Inventory/Inventory_Slot.png`

These were selected from the 2026-07-24 audit because they provide a coherent HUD/preview direction without forcing a full board-art commitment yet.

## Placeholder visuals retained

- Board background fallback: code-drawn rounded panel
- Empty cells: code-drawn rounded cells
- Occupied cells: code-drawn colored cells driven by `GameConfig.tile_palette`
- Active-piece preview: code-drawn valid/invalid overlays
- Merge flash: code-drawn overlay

This keeps the feature usable even when optional textures are unassigned.

## Signals and update flow

- `BoardView.anchor_targeted(anchor: Vector2i)` sends pointer intent upward to `Main`.
- `Main` remains authoritative and resolves the requested anchor before updating state.
- `Main` pushes presentation updates through:
  - `BoardView.set_board_state(...)`
  - `BoardView.set_active_piece(...)`
  - `BoardView.set_feedback(...)`
  - `GameHUD.update_status(...)`
  - `GameHUD.set_preview_pieces(...)`

No presentation component modifies `BoardState` directly.

## Inspector settings added

- `BoardView`
  - `config`
  - `top_padding`
  - `bottom_padding`
  - `board_corner_radius`
  - `cell_corner_radius`
  - `board_texture`
  - `empty_cell_texture`
  - `occupied_cell_texture`
  - `value_font`
  - `value_font_size`
- `GameHUD`
  - `title_font`
  - `body_font`
  - `header_panel_texture`
  - `footer_panel_texture`
  - `stat_chip_texture`
  - `header_separation`
  - `footer_separation`
  - `stats_separation`
  - `panel_tint`
  - `text_color`
  - `title_text`
- `PiecePreviewStrip`
  - `title_font`
  - `label_font`
  - `card_texture`

## Validation

- Godot 4.7.1 headless load:
  - `tools/local-godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --quit`
  - Result: passed
- Deterministic rules tests:
  - `tools/local-godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/run_rules_tests.gd`
  - Result: `BoardState tests passed.`
- Optional texture fallback:
  - Supported by component logic; board and HUD still render with code-drawn fallback styling where optional textures are missing
- Missing scene/resource references for this feature:
  - No missing references surfaced in the headless project load

## SpriteCook follow-up list

- Final board-cell sprite family matching the HUD palette and rounded-cell proportions
- Piece-cell sprite variations that map cleanly onto existing numeric piece values
- Merge-effect concept frames that fit the current readable, low-noise board presentation
- A consistent HUD panel variant sized for the header/footer containers
- A preview-strip frame treatment that matches the chosen board-cell family
- Small icons for score, best, and turns if the HUD should become more pictographic

SpriteCook should not modify GDScript, scenes, tests, or gameplay logic.

## Remaining limitations

- Board cells and active-piece previews are still mostly placeholder/vector-style visuals
- HUD stat chips use curated textures only indirectly through the preview/panel treatment, not bespoke per-stat art
- No production audio cues were integrated in this pass
- No large animation system was introduced beyond the existing toast and lightweight merge/invalid-placement feedback

## Recommended next feature

- Curate or generate a coherent production board-cell and piece-cell sprite family, then add a small presentation-only animation pass for placement confirmation and merge emphasis.

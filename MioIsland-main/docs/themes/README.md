# Theme Manifest

CodeIsland now supports loading custom notch themes from two locations:

- `~/.config/codeisland/themes/*.json`
- Plugin bundles at `Contents/Resources/Themes/*.json`

Each file must contain one theme manifest. A complete example lives in
[theme-manifest-example.json](/Users/ying/Documents/AI/CodeIsland/docs/themes/theme-manifest-example.json).

## Required Fields

- `id`: unique stable identifier used for persistence
- `displayName`: label shown in the settings picker
- `tokens`: semantic theme token payload

## Optional Fields

- `previewIdleLabelEN`
- `previewIdleLabelZH`
- `prefersUppercasePreviewLabel`

## Notes

- Built-in themes load first. External themes are appended if their `id` does not collide with an existing theme.
- If a saved theme ID no longer exists, CodeIsland falls back to the built-in `classic` theme at render time.
- The current schema is code-defined by `ThemePluginManifest` in [ThemeRegistry.swift](/Users/ying/Documents/AI/CodeIsland/ClaudeIsland/Models/ThemeRegistry.swift).

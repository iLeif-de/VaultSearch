# Documentation images

The screenshots of the documentation, one folder per interface language. All images show the sample vault [`docs/demo-vault`](../demo-vault), never personal notes.

| File | Shows | Used in |
|---|---|---|
| `main-window.png` | Search `battery`, top hit selected, find bar on “2 of 7” | README, user guide: *The window* |
| `tag-search.png` | Search `tag:idea` with ranked results | user guide: *Tags* |
| `settings-export.png` | Settings ▸ Export, top part | user guide: *Settings* |
| `settings-templates.png` | Settings ▸ Export, templates | user guide: *Templates* |
| `about.png` | About window | developer guide: *About window* (English only) |

`en/` is used by the README, the [User Guide](../user-guide.md) and the [Developer Guide](../development.md); `de/` by the [Benutzerhandbuch](../benutzerhandbuch.md).

## Replacing an image

Save a new PNG under the same name in `en/` and/or `de/`. The documents reference images with relative Markdown links such as `![…](images/en/main-window.png)`; GitHub does not understand Obsidian's `![[…]]` embeds. Recommended: capture the window only (⇧⌘4, then Space, click the window) and keep the width below about 1800 px.

## Taking all screenshots again

```sh
docs/images/capture-screenshots.sh [path/to/VaultSearch.app]
```

Without an argument the script uses the Debug build from Xcode's DerivedData. It starts VaultSearch with the demo vault and fixed settings, passed as launch arguments only; your own settings stay unchanged. It types the searches, opens Settings and the About window, and saves everything in `en/` and `de/`. The Terminal needs Accessibility and Screen Recording permission (System Settings ▸ Privacy & Security). Your clipboard is restored afterwards.

# GTD AppleScript Applications

Native macOS applications for GTD capture that properly receive focus when triggered via global hotkeys.

## Applications

| App | Hotkey | Description |
|-----|--------|-------------|
| `GTDMenu.app` | `Alt+Shift+Space` | Full GTD menu with capture, metrics, lists |
| `GTDCapture.app` | `Alt+Shift+C` | Quick capture with state picker |
| `GTDClipboard.app` | `Alt+Shift+V` | Capture from clipboard |

## Building

Compile with `osacompile`:

```bash
# Build all apps
osacompile -o ~/bin/GTDMenu.app GTDMenu.applescript
osacompile -o ~/bin/GTDCapture.app GTDCapture.applescript  
osacompile -o ~/bin/GTDClipboard.app GTDClipboard.applescript
```

## Why AppleScript Apps?

Regular shell scripts calling `osascript` don't receive window focus when triggered from background processes (like Aerospace hotkeys). By compiling as proper `.app` bundles, macOS treats them as applications that can be activated and receive focus.

The `tell me to activate` statement at the start of each script ensures the dialog appears in front of all other windows.

## Customization

Edit the `.applescript` source files and recompile. Key customizations:

- `INBOX_FILE` - Path to your inbox file
- `GTD_DIR` - Path to your GTD directory
- State options in the picker (TODO, NEXT, WAITING, SOMEDAY)
- Menu items in GTDMenu.app

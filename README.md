# btop Desktop

A menu bar app for macOS that keeps [btop](https://github.com/aristocratos/btop) on your desktop — above the wallpaper and below the desktop icons — so it looks like a system monitor built into your wallpaper.

- Borderless, transparent window at `kCGDesktopWindowLevel` (shown on every Space, hidden from Mission Control and ⌘Tab)
- Click-through by default, so it never gets in the way of the desktop
- Terminal rendering by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)'s `LocalProcessTerminalView`; rows and columns are computed from the window size and font and passed to btop
- btop is restarted automatically if it exits (with exponential backoff up to 30 s if it keeps crashing)

## Requirements

- macOS 14 or later, Apple Silicon
- Swift 6.2 or later (Xcode 26 or its Command Line Tools), required by SwiftTerm 1.99
- btop: `brew install btop` (if it is missing, the app shows a dialog explaining how to install it)

## Build

```sh
./build.sh            # creates build/BtopDesktop.app (release, ad-hoc signed)
./build.sh run        # builds and launches it
./build.sh install    # builds and copies it to /Applications
CONFIG=debug ./build.sh
SIGN_IDENTITY="Developer ID Application: ..." ./build.sh   # sign with a real identity
```

## Install

```sh
./build.sh install
open /Applications/BtopDesktop.app
```

Enable **Launch at Login** (SMAppService) after the app is in `/Applications`.
macOS may ask you to approve it in System Settings › General › Login Items; the app opens that pane for you when needed.
With the default ad-hoc signature every rebuild changes the code signature, so you may need to turn Launch at Login off and on again after reinstalling.

## Usage

Everything is in the CPU icon in the menu bar.

| Item | What it does |
| --- | --- |
| Show on Desktop | Show or hide. btop is stopped while hidden |
| Fill Screen | On by default: the window fills the display's visible area (excluding the menu bar and Dock) and follows its size. Moving or resizing in edit mode turns it off; turn it back on to return to full screen |
| Edit Mode (Move & Resize) | Turns off click-through: drag to move, drag an edge (12 pt) to resize, press Esc to finish. Turning it off saves the position and size and restores click-through. While editing, the window is temporarily raised to the front |
| Display | Choose which display to use. Dragging the window onto another display in edit mode also switches |
| Font Size / Background Opacity | Quick presets |
| Appearance… | Monospaced font, size and opacity (applied immediately) |
| Open btop Config File | Opens the app-private `btop.conf` in your default editor (TextEdit if none) |
| Restart btop | Applies changes made to the config file |
| Launch at Login | Registers or unregisters the app with SMAppService |

## Multiple displays

The monitor is shown on **one** display at a time — the one selected under **Display** (the primary display by default).

- By default the window fills the selected display. A custom position and size (after moving or resizing in edit mode) is saved per display (by display UUID).
- If the selected display is unplugged, the window moves to the primary display. The selection is kept, so it moves back when the display is reconnected.
- When the display configuration or resolution changes (including after waking from sleep), the window is re-fitted to the screen, and once things settle the terminal is re-measured and btop is told to re-lay itself out for the new size.

## Where settings live

- App settings: UserDefaults (`io.github.masaki39.BtopDesktop`). Window frames are stored per display.
- btop settings: `~/Library/Application Support/BtopDesktop/btop/btop.conf`
  (btop is started with `XDG_CONFIG_HOME=~/Library/Application Support/BtopDesktop`, so your `~/.config/btop` is never touched).
- Defaults: `color_theme` = tokyo-night (dracula if missing), `theme_background = False`, `update_ms = 1000`.
- To reset, delete `btop.conf` and restart the app.

## Known limitations

- **Minimum size**: btop shows "Terminal size too small" below 80 columns × 24 rows. Lower the font size if you want a small window.
- **Display only**: you cannot type into or click btop. Change what it shows through `btop.conf`.
- **Background transparency**: cells that btop paints with an explicit background color (such as the selected row) stay opaque.
- **Raised while editing**: at desktop level, Finder's desktop layer would take the clicks, so the window is raised to floating level only while in edit mode.
- **Full-screen Spaces**: the desktop is not visible there, so neither is the monitor.
- **Single display**: the monitor is not mirrored to every display.
- **Signing**: `build.sh` uses an ad-hoc signature. Distributing to other Macs requires Developer ID signing and notarization.
- **CPU usage**: btop and rendering use a little CPU all the time. Raise `update_ms` if that matters to you.

## License

MIT

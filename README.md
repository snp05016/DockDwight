# DockDwight

A tiny persistent pixel character who patrols the bottom-right of the macOS desktop, pauses to deliver Dwight-style declarations, and stays out of the Dock and menu bar.

His opaque foot pixels are anchored to the physical bottom edge of the display containing the pointer. He follows between monitors automatically and scales to the current macOS Dock tile size.

## Controls

- Left-click Dwight: make him stop and say another line.
- Right-click Dwight: hide him.
- `Control + Option + D`: hide or restore him globally.
- Drag Dwight: move him anywhere across your monitor layout; he then patrols near that spot.
- Scroll over Dwight, or Shift-drag vertically: resize from 45% to 300% of the current Dock size.
- Double-click Dwight: reset to automatic monitor-following, bottom-anchored, Dock-sized placement.

## Install

```bash
./scripts/install.sh
```

The app installs to `/Applications/DockDwight.app` and starts automatically at login.

## Sprite provenance

The standing and two walking sprites in `Sources/DockDwightLib/Resources` were produced with the built-in image generation tool from the two user-supplied pixel-art references. The extraction prompts requested one centered full-body pose, preserved clothing and facial details, hard pixel edges, and a transparent background.

# DockDwight

A tiny persistent pixel character who patrols the bottom-right of the macOS desktop, pauses to deliver Dwight-style declarations, and stays out of the Dock and menu bar.

## Controls

- Left-click Dwight: make him stop and say another line.
- Right-click Dwight: hide him.
- `Control + Option + D`: hide or restore him globally.

## Install

```bash
./scripts/install.sh
```

The app installs to `/Applications/DockDwight.app` and starts automatically at login.

## Sprite provenance

The standing and two walking sprites in `Sources/DockDwightLib/Resources` were produced with the built-in image generation tool from the two user-supplied pixel-art references. The extraction prompts requested one centered full-body pose, preserved clothing and facial details, hard pixel edges, and a transparent background.


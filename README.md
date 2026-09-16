# DockDwight

A persistent, menu-bar-free pixel desktop companion with a real behavior state machine. Dwight patrols, sleeps, inspects apps and devices, supervises focus sessions, reacts to weather and battery state, accepts drag-and-drop placement, stages visitor cameos, and records a local Schrute Log.

His opaque foot pixels are anchored to the physical bottom edge of the display containing the pointer. He follows between monitors automatically and scales to the current macOS Dock tile size.

## Controls

- Left-click Dwight: make him stop and say another line.
- Right-click Dwight: open the action menu (settings, focus, visitors, beet drill, hide, reset, or quit).
- Option-click Dwight: open the **Schrute Command Center**.
- `Control + Option + D`: hide or restore him globally.
- `Control + Option + ,`: open the Schrute Command Center globally.
- Drag Dwight: move him anywhere across your monitor layout; he then patrols near that spot.
- Scroll over Dwight, or Shift-drag vertically: resize from 45% to 300% of the current Dock size.
- Double-click Dwight: reset to automatic monitor-following, bottom-anchored, Dock-sized placement.
- Triple-click Dwight: begin a 12-second beet-harvesting drill; click him to score.

## Companion systems

- Dedicated walking, sleeping, clipboard-inspection, celebration, pickup and landing states.
- Foreground-app reactions for Xcode, Terminal, Slack, music, Calendar and Mail.
- Configurable focus supervision with a private, local distracting-app list.
- AirPods, XM4 and ProtoArc K100-A reactions through DeviceArrivalHUD's distributed event bridge.
- External-drive, monitor-transfer, low-battery, idle/sleep and wake reactions.
- Weather-aware accessories using configurable coordinates and Open-Meteo.
- Optional sound effects, trackpad haptics, visitor cameos and personality intensity.
- Local-only routine counters and an in-memory incident history. No URLs, documents, keystrokes or screen contents are collected.

## Install

```bash
./scripts/install.sh
```

The app installs to `/Applications/DockDwight.app` and starts automatically at login.

## Sprite provenance

The standing sprite and walk-cycle frames in `Sources/DockDwightLib/Resources` preserve the user-supplied pixel-art references. The stride frame was cleanly extracted from the supplied walk reference; the matching passing-position, sleeping, clipboard-inspection and celebration frames were produced with the built-in image generation tool, normalized to the same 437 px source height and pixel density, and converted to genuine transparency.

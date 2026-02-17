# HyprGBorder

**Make your Hyprland windows drip with style.**

A buttery-smooth border animation tool written in [Zig](https://ziglang.org) for [Hyprland](https://hyprland.org/) enthusiasts who refuse to settle for boring window edges. Direct IPC communication means zero bloat, zero CPU-hogging loops — just pure, unadulterated border bliss.

---

## What's This?

Your windows deserve better than static, lifeless borders. HyprGBorder lets you:

- **Rainbow borders** — cycle through the full spectrum like a majestic unicorn
- **Pulse animations** — breathe life into your workspace with rhythmic color pulses  
- **Gradient borders** — smooth transitions between your favorite colors
- **Solid colors** — for when you want to make a statement
- **Live preview** — see changes in real-time before committing
- **Preset management** — save, load, and organize your favorite looks

All configurable through a slick TUI (Terminal User Interface) or command-line flags.

---

## Installation

### Build from Source

You'll need **Zig 0.16+** (nightly):

```bash
git clone https://github.com/scooter-lacroix/hyprgborder.git
cd hyprgborder
zig build -Doptimize=ReleaseFast
```

The binary lands at:

```
zig-out/bin/hyprgborder
```

### System Installation

After building, install to `/usr/local/bin`:

```bash
sudo zig build install -Doptimize=ReleaseFast --prefix /usr/local
```

Or for a user-local installation:

```bash
zig build install -Doptimize=ReleaseFast --prefix ~/.local
```

Make sure `~/.local/bin` is in your PATH.

### Verify Installation

```bash
hyprgborder --help
```

### Quick Start

```bash
# Run with saved configuration (or defaults)
hyprgborder

# Open the TUI for interactive configuration
hyprgborder --tui

# Show help
hyprgborder --help
```

### Autostart with Hyprland

Enable autostart from the System Settings panel in the TUI, or manually add to your Hyprland config (`~/.config/hypr/hyprland.conf`):

```ini
exec-once = hyprgborder
```

**Important**: After enabling autostart, verify the desktop entry was created:

```bash
ls ~/.config/autostart/hyprgborder.desktop
```

---

## Features

### Terminal User Interface (--tui)

The TUI provides a full-featured configuration experience:

- **Animation Settings** — Choose animation type, speed, FPS, and colors
- **Live Preview** — See your changes applied instantly
- **Preset Management** — Save/load/delete named configurations
- **System Status** — Check Hyprland connection and environment
- **Autostart Toggle** — Enable/disable automatic startup

Navigation:
- `Tab` — Switch between panels
- `Enter` — Select/activate
- `F1` — Help
- `F2` — Toggle live preview
- `Esc` — Exit

### Animation Types

| Type | Description |
|------|-------------|
| **Rainbow** | HSV color cycling through the full spectrum |
| **Pulse** | Breathing animation with your chosen color |
| **Gradient** | Smooth blend between two or more colors |
| **Solid** | Static color for clean, minimal borders |
| **None** | Disable animations (why would you?) |

---

## Configuration

Configuration is stored in:

```
~/.config/hyprgborder/config.json
```

Presets are saved to:

```
~/.config/hyprgborder/presets/
```

---

## Requirements

- **Hyprland** running with proper environment variables set
- `$XDG_RUNTIME_DIR` — standard XDG runtime directory
- `$HYPRLAND_INSTANCE_SIGNATURE` — set by Hyprland automatically

---

## Acknowledgments

This project was inspired by [HyprIngMyBorder](https://github.com/blue-codes-yep/HyprIngMyBorder) by **@blue-codes-yep** — thanks for lighting the spark that made these borders possible! 

---

## License

MIT — use it, modify it, share it. Just don't blame me if your borders become too beautiful.

---

*Built with ❤️ and an unhealthy obsession with animated window decorations.*

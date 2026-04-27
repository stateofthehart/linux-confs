# Sway Dual-Bar Configuration

Your sway setup now features a developer-focused dual-bar configuration inspired by KDE's usability.

## Architecture

### Top Bar (`config-top`)
**Purpose**: System monitoring & workspace navigation
**Modules**:
- **Left**: Sway workspaces with window count indicators, Mode indicator
- **Center**: Active window title
- **Right**: CPU usage+temp, RAM, GPU usage+temp, Disk usage

**Key Features**:
- Window indicators show as colored squares on workspace buttons:
  - Blue (default), Orange (Firefox), Green (terminals), Blue-VS (VS Code), Purple (chat apps)
- Color-coded system stats with left-border accents
- Dark hacker aesthetic with GitHub-dark background

### Bottom Bar (`config-bottom`)
**Purpose**: KDE-inspired control center
**Modules**:
- **Left**: CachyOS launcher icon (click to open rofi app launcher)
- **Center**: Large clock (date + time, click to toggle format)
- **Right**: Brightness, Volume, WiFi (custom module), Bluetooth (custom module), Battery, System tray (Slack, 1Password, etc.)

**Key Features**:
- Custom WiFi and Bluetooth modules (NOT nm-applet/blueman-applet in tray)
- System tray reserved for other apps (Slack, 1Password, etc.)
- Scroll on brightness/volume to adjust
- Click WiFi → nm-connection-editor, Bluetooth → blueman-manager, Volume → pavucontrol
- Color-coded: Yellow (brightness), Blue (volume), Green (network), Cyan (bluetooth), Pink (battery)
- Battery charging states with visual feedback
- WiFi shows IP addresses on hover tooltip

## Style Highlights

### Top Bar
- Background: `rgba(13, 17, 23, 0.95)` (GitHub dark)
- Accent borders on modules (amber CPU, purple RAM, cyan GPU, etc.)
- Rounded 8px pill-style modules
- Focused workspaces: Blue border + glow

### Bottom Bar
- Background: `rgba(30, 30, 46, 0.98)` (Catppuccin-inspired)
- Breeze-like hover states with blue border highlight
- Prominent center clock with pink accent
- Modules: 8px border-radius, subtle borders

## Keyboard Shortcuts (Unchanged)

Your existing keybindings remain intact:
- `$mod+d`: Window switcher (rofi)
- `$wndw+d`: App launcher (rofi drun)
- `$mod+[1-0]`: Switch workspaces
- `$mod+Return`: Terminal (foot)
- All your custom bindings preserved

## Files Modified

1. `~/.config/sway/config` - Changed bar section to dual exec_always
2. `~/.config/waybar/config-top` - New top bar config
3. `~/.config/waybar/config-bottom` - New bottom bar config  
4. `~/.config/waybar/style.css` - Complete theme rewrite

## Customization Tips

### Change Colors
Edit `~/.config/waybar/style.css`:
- Top bar accents: Lines 94-100
- Bottom bar module colors: Lines 157-161

### Add/Remove Modules
Edit the respective config file:
- Top: `~/.config/waybar/config-top`
- Bottom: `~/.config/waybar/config-bottom`

### Window Indicator Colors
Edit `config-top` sway/workspaces section:
- `window-format`: Default window color
- `window-rewrite`: Per-app colors

## Troubleshooting

**Bars not showing?**
```bash
pkill waybar
waybar --config ~/.config/waybar/config-top &
waybar --config ~/.config/waybar/config-bottom &
```

**Check for errors:**
```bash
waybar --config ~/.config/waybar/config-top -l debug
```

**After sway config changes:**
Press `$mod+Shift+c` to reload sway config

## Dependencies Used

- `waybar` - Bar program
- `JetBrainsMono Nerd Font` - Icons and text
- `brightnessctl` - Brightness control
- `pactl/pavucontrol` - Volume control
- `nm-connection-editor` - Network GUI
- `blueman-manager` - Bluetooth GUI

## Design Philosophy

This setup embraces:
- **Developer/hacker aesthetic**: Dark themes, monospace fonts, accent colors
- **KDE usability inspiration**: Logical control grouping, visual feedback, hover states
- **Sway tiling philosophy**: Minimal chrome, keyboard-first, scriptable
- **Information hierarchy**: System status visible at glance, controls easily accessible

Enjoy your optimized sway environment!

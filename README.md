# Bezel

Bezel is a Linux daemon that provides customizable trackpad edge gestures.
It intercepts raw trackpad inputs via evdev and dispatches shell
commands based on directional swipes or taps along the edges (zones) of your trackpad.

<p align="center">
  <img width="700" src="preview.gif" alt="Bezel Demo">
</p>

<br clear="right">

## Installation

Bezel is Linux-only (Wayland required).

### Prebuilt binary
```sh
curl -sSfL https://raw.githubusercontent.com/indra55/bezel/main/install.sh | bash
```
*(To update to a newer version, simply run this exact same command again. It will safely back up your old binary and seamlessly restart the service.)*

### From source
```sh
cargo install --git https://github.com/indra55/bezel
```

### Arch Linux

Normally we'd just tell you to `yay -S bezel`, but the AUR is currently experiencing a massive malware apocalypse. Someone adopted 1,500 orphaned packages and turned them into malware, so Arch had to disable new account registrations. We have our `PKGBUILD` ready to go, but until they put out the fire, you'll have to use the prebuilt binary or build from source like a normal person. Stay safe out there!

### NixOS
You can try out Bezel using this command:
```sh
nix run github:indra55/bezel
```

For a permanent installation, first add Bezel to your flake inputs:
```nix
{
  inputs = {
    # ... other inputs
    bezel = {
      url = "github:Indra55/bezel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ... rest of your flake
}
```

Also make sure that you have `extraSpecialArgs = { inherit inputs; };` in your flake outputs.

Bezel provides a NixOS module. To enable it:
```nix
{ inputs, ... }: {
  imports = [
    inputs.bezel.nixosModules.default
  ];
}
```

You can now enable the Bezel service. This snippet will:
1. install the Bezel package on your system;
2. create and enable the Bezel service for all users;
3. configure udev rules.
**NOTE:** you'll still have to add yourself to the `input` and `uinput` groups
```nix
{ ... }: {
  services.bezel.enable = true;
}
```

If you prefer to enable Bezel per-user instead, you can do so using Home Manager.
```nix
{ inputs, ... }: {
  imports = [
    inputs.bezel.homeModules.default
  ];

  services.bezel.enable = true;
}
```

`homeManagerModules.default` remains available for existing configurations.

**NOTE:** If you use the Home Manager module, you'll have to enable uinput separately in your NixOS config, as Home Manager doesn't have access to them:
```nix
{ ... }: {
  hardware.uinput.enable = true;
}
```

## Setup

Add yourself to the `input` group (required on all distros):
```sh
sudo usermod -aG input $USER
# reboot your computer after this
```

**NixOS Users:** Add `"input"` and `"uinput"` to your `users.users.<name>.extraGroups` instead of using `usermod`.

If you still get `Permission denied (os error 13)` after rebooting, you may need custom udev rules for your physical and virtual trackpads. Create `/etc/udev/rules.d/99-bezel.rules`:
```udev
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", GROUP="input", MODE="0640"
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
```
Then reload udev rules with `sudo udevadm control --reload-rules && sudo udevadm trigger`.

**NixOS Users:** set either `services.bezel.enable = true` or `hardware.uinput.enable = true`

### Configuration
Bezel looks for its configuration at `~/.config/bezel/config.toml`.

On first install, `install.sh` launches a terminal onboarding wizard. It detects your Wayland desktop, offers numbered choices for Hyprland, Niri, Sway, Plasma, GNOME, other Wayland desktops, or NixOS, and shows each trackpad edge as you configure it. In the panel, customizing an edge lets you choose 1–4 fingers, then a gesture and action, with up to 30 action presets plus custom shell commands. Window controls adapt to Hyprland, Niri, and Sway; utility presets appear when their required tools are installed. Press Enter to keep suggested bindings, or customize each edge, including multi-finger bindings. Hyprland, Niri, and Sway get their own workspace commands; Plasma, GNOME, and unknown desktops omit workspace actions. On upgrades, the installer asks whether to run onboarding again when a config exists. Choosing no keeps the config. Choosing yes opens the wizard, where **Apply now** backs up and replaces it, while **Save preview only** leaves it unchanged.

The active trackpad edge uses a static warm-orange halo in color terminals. If your shell sets `NO_COLOR`, run `bash onboard.sh --color` to preview the accent anyway; `--no-color` forces the monochrome version.

On NixOS, the installer prints a Home Manager snippet instead of creating an unmanaged TOML file or systemd service. Import the Bezel Home Manager module, add the snippet, and configure `hardware.uinput` plus the `input` and `uinput` groups in your NixOS configuration. The snippet includes the gesture command tools (`wpctl`, `brightnessctl`, `playerctl`).

For Arch, Debian/Ubuntu, Fedora, and openSUSE, the same installer uses systemd user services and udev; you need Rust only when building from source or when a prebuilt binary is unavailable. The command tools above must be installed separately.

To define a gesture, specify the zone and direction, and the command to run:
This example uses Hyprland 0.55+ syntax; older Hyprland releases use different dispatch commands.

```toml
[gestures.top.left]
action = "command"
cmd = "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'"
```
*(See `config.toml.example` in this repo for a basic template.)*

To configure OSD labels, add the following:
```toml
[osd]
enabled = true
backend = "notify-send" # Valid options: "notify-send", "swayosd", "pipe"
canonical_hints = false # Set to true only if using mako or notify-osd
```

**NixOS Users:** After importing the Home Manager module you can also customize Bezel using the `services.bezel.config` option. See `config.nix.example` for a complete template.

### Multi-finger gestures

Legacy `[gestures.edge.direction]` entries bind one finger. Use `[[bindings]]` for **1–4 fingers**, with `zone`, `fingers`, `gesture`, `action = "command"`, and `cmd`:

```toml
[[bindings]]
zone = "left"
fingers = 2
gesture = "slide_up"
action = "command"
cmd = "wpctl set-volume @DEFAULT_SINK@ 2%+"
step_distance = 0.03
```

Start one finger at an edge, then add the others within **80 ms** (`join_ms`); they may start inside the pad. Existing center touches stay independent. One edge gesture runs at a time, and contacts arriving after the joining window pass through normally. The selected edge and finger count remain fixed until release. Unconfigured counts do not fall back to one-finger commands; gesture contacts remain reserved until lifted. More than four joining contacts cancel the gesture. Your trackpad must report each contact independently using multitouch slots.

Available gestures:

- `tap`, `double_tap`, `hold`.
- `swipe_up`, `swipe_down`, `swipe_left`, `swipe_right`, and `swipe_up_left`, `swipe_up_right`, `swipe_down_left`, `swipe_down_right`.
- `slide_up`, `slide_down`, `slide_left`, `slide_right`: repeat the command for each movement step, with direction reversal supported.

Swipes fire once when all participating fingers lift. Holds fire once while fingers remain down. Slides and holds suppress release gestures. Diagonal bindings apply within 22.5° of their diagonal; otherwise Bezel uses the dominant cardinal direction. Single taps are delayed only when a double tap is bound for the same edge/count; both taps must finish within the double-tap interval and start close together.

Set shared defaults in `[recognition]`. Distances are fractions of the trackpad axes, not physical millimeters:

| Setting | Default | Per-binding override |
| --- | --- | --- |
| `join_ms` | 80 | Shared only |
| `swipe_distance` | 0.05 | Swipes |
| `tap_distance` | 0.02 | Taps and holds |
| `tap_ms` | 200 | Taps and double taps |
| `double_tap_ms` | 300 | Double taps |
| `hold_ms` | 500 | Holds |
| `step_distance` | 0.03 | Slides |

Distances accept 0.001–1; times accept 1–10000 ms (`join_ms`: 1–1000), with joining time no greater than tap/hold time. Explicit bindings override equivalent legacy entries; duplicate explicit bindings and incompatible overrides are rejected. Valid config reloads affect the next gesture; invalid reloads retain the previous configuration.

Run `bash onboard.sh` and choose **Customize this edge → finger count → gesture → action**. You can assign one-finger volume and two-finger brightness on the same edge. The plain fallback also provides a separate advanced binding editor. It supports 30 action presets, custom shell commands (option 31), shared sensitivity, and TOML or Nix output. New presets include close/fullscreen/floating, directional window focus, launcher, terminal, lock, screenshots, clipboard history, and Do Not Disturb. Utility choices detect installed tools: fuzzel/wofi/rofi, common terminals, hyprlock/swaylock/loginctl, grim + slurp + wl-copy (or Niri screenshots), cliphist + a picker + wl-copy, and swaync/dunst. Clipboard history requires an existing cliphist capture service; screenshots from grim are copied to the clipboard. Nix users should add the tools they select to their packages. Preview, backup, and cancel work as before. See [config.toml.example](config.toml.example) and [config.nix.example](config.nix.example).

### Autostart

> [!WARNING]  
> If you used the NixOS/HM module or `install.sh` script, Bezel is already running as a `systemd` service! **Do not** add these autostart commands, or you will run two instances simultaneously and they will crash.

Start Bezel when your Wayland compositor starts. **Void Linux / non-systemd** users should use this method instead of a background service. If `bezel` is not in your system `$PATH`, use the absolute path `~/.local/bin/bezel` (or `~/.cargo/bin/bezel` if built with cargo).

For **Hyprland 0.55+** (`~/.config/hypr/hyprland.lua`):
```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.local/bin/bezel")
end)
```

For **older Hyprland** (`~/.config/hypr/hyprland.conf`):
```conf
exec-once = ~/.local/bin/bezel
```

For **Sway** (`~/.config/sway/config`):
```conf
exec ~/.local/bin/bezel
```

For **Niri** (`~/.config/niri/config.kdl`):
```conf
spawn-at-startup "~/.local/bin/bezel"
```

### Web Visualizer (Demo)

Bezel includes a web-based visualizer that shows a graphical representation of your trackpad and animates when you perform gestures. It's useful for testing, debugging, or recording demos.

To use the visualizer:
1. Update your `~/.config/bezel/config.toml` to use the `pipe` OSD backend:
   ```toml
   [osd]
   enabled = true
   backend = "pipe"
   ```
2. Restart Bezel (`systemctl --user restart bezel.service` or restart manually).
3. Start the visualization server from the root of this repository:
   ```sh
   python3 viz/server.py
   ```
4. Open `http://localhost:8080` in your web browser. When you perform gestures, the server will read them from the pipe (`/tmp/bezel-osd`) and broadcast them to the webpage in real-time.

## Troubleshooting

## Compatibility with libinput-gestures

If you are running both Bezel and `libinput-gestures`, you may find that `libinput-gestures` stops working when Bezel is active. This happens because Bezel grabs the physical trackpad exclusively, and `libinput-gestures`' auto-detection heuristic prefers devices with "touchpad" in the name over "trackpad". It will bind to the silenced hardware device instead of the virtual one created by Bezel.

To fix this, you must explicitly tell `libinput-gestures` to use Bezel's virtual device by adding the following line to your `/etc/libinput-gestures.conf` (or `~/.config/libinput-gestures.conf` if you're using a per-user config):
```conf
device Bezel Virtual Trackpad
```
Then restart `libinput-gestures` (`libinput-gestures-setup restart`).
### OSD Notifications Not Showing

If OSD notifications (`notify-send`) fail or don't show up when Bezel is run as a `systemd` service, your compositor might not be exporting the D-Bus environment properly. You can check the logs to see if `notify-send` is exiting with an error. 

To fix this, add the following to your compositor's startup config to import the session variables:

**Hyprland 0.55+** (`hyprland.lua`):
```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS")
end)
```

**Older Hyprland** (`hyprland.conf`):
```conf
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS
```

**Sway:**
```conf
exec systemctl --user import-environment WAYLAND_DISPLAY SWAYSOCK DBUS_SESSION_BUS_ADDRESS
```
*(Niri does this automatically).*

### Debugging Logs

To enable more detailed logging, you can set the `BEZEL_LOG` environment variable. Valid log levels are `error`, `warn`, `info`, `debug`, and `trace`. For example:
```sh
BEZEL_LOG=debug bezel
```
If you are running Bezel as a systemd service, you can run `systemctl --user edit bezel.service` and add the following to the override file:
```ini
[Service]
Environment="BEZEL_LOG=debug"
```
Then restart the service.

If your trackpad stops responding, restart the service:
```sh
systemctl --user restart bezel.service
```

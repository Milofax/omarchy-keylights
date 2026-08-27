# Key Lights for Omarchy

An Omarchy bar plugin that automatically discovers and controls Elgato Key Lights on the local network.

## Features

- Automatic discovery through the Elgato `_elg._tcp` mDNS service
- Individual on/off switches for every discovered light
- Shared brightness and color-temperature controls with explicit mixed-value states
- Fast retries for occasionally unresponsive light APIs
- A standalone bar icon while a light is on, with an automatic system-tray fallback otherwise
- Setup flow for factory-reset lights through Elgato's local pairing page
- No Elgato Control Center installation required

## Requirements

- Omarchy with Quickshell plugin support
- `avahi`, `curl`, and `jq` for discovery and control
- Python 3 with `python-dbus` and `python-gobject` for the system-tray item
- The `omarchy.tray` widget present in the bar layout for the automatic tray fallback
- NetworkManager, Zenity, a Wi-Fi adapter, and a browser for first-time setup
- Key Lights and the Omarchy computer on the same local network

The control panel works without Elgato Control Center. First-time setup additionally requires `nmcli`, `zenity`, `xdg-open`, and a Wi-Fi adapter.

## Installation

```bash
omarchy plugin add https://github.com/Milofax/omarchy-keylights.git --enable
```

The manifest places the widget in the right section of the bar by default.

## Removal

```bash
omarchy plugin remove io.github.milofax.keylights --yes
```

The plugin does not create configuration files, services, caches, or credential stores. Removing the plugin checkout removes all of its persistent files.

## Usage

- Left-click: open or close the control panel
- Middle-click: toggle every discovered light
- Right-click: turn every discovered light off
- Scroll: adjust shared brightness in 5% steps
- `R` in the panel: refresh discovery and state
- `S` in the panel: start setup

While at least one reachable light is on, the normal filled Key Lights icon occupies its standalone bar slot. When all discovered lights are off or no light is reachable, that slot collapses and Key Lights remains available in Omarchy's system-tray drawer behind the chevron. Keep `omarchy.tray` in the bar layout so this fallback remains reachable. If the tray's Python dependencies are missing, the plugin retains its bar button and marks it with an `×` instead of disappearing. The same `×` also calls attention to setup availability, discovery errors, or unreachable lights. The tray item uses the same controls: left-click opens the panel, middle-click toggles all reachable lights, right-click turns them off, and scrolling adjusts shared brightness.

The brightness and color-temperature sliders control all reachable lights. If their current values differ, the panel displays **Mixed** until a shared value is selected. Color temperature is the light's configured setpoint, not a measured room temperature.

## Setup

Factory-reset a Key Light until it flashes three times, then choose **Set up** in the panel. The plugin connects the computer to the light's temporary Wi-Fi network, verifies the Elgato accessory API, and asks for confirmation before opening Elgato's local setup page. Network credentials are entered directly into that page and are never stored by this plugin. The previous network connection is restored on success, cancellation, error, or interruption.

Elgato exposes the setup page over unencrypted local HTTP. Only continue when the physical light you reset is flashing and its temporary Wi-Fi name matches the selected entry. The plugin cannot cryptographically authenticate a factory-reset light.

## CLI

The plugin includes its local driver at `bin/keylights`:

```bash
./bin/keylights json
./bin/keylights all status
./bin/keylights all toggle
./bin/keylights DEVICE_ID brightness 40
./bin/keylights DEVICE_ID temperature 4700
./bin/keylights setup
./bin/keylights control ACTION VALUE TARGETS_JSON
```

`control` is the panel's snapshot-based internal interface. `VALUE` is `-` for actions without a value, and `TARGETS_JSON` is the validated endpoint array returned from panel state. Invalid actions, values, or targets exit with status 2 before device I/O; missing dependencies or discovery failures use status 3.

## Privacy and security

The plugin communicates only with Avahi, NetworkManager, and discovered Elgato lights on the local network. Discovery marks an endpoint reachable only after verifying the Elgato accessory API; unreachable advertisements may still appear as disabled panel rows. A changed address is verified again, including its stable serial when available, before retrying a command. The plugin does not contact a cloud service or store Wi-Fi credentials.

The tray helper owns one fixed name on the local session D-Bus, so multiple monitor instances cannot publish duplicate icons. Other monitor instances wait without respawning and take ownership if the active monitor disappears. The helper is started only while the standalone bar icon is hidden, unregisters on termination, and talks back to the existing panel through Omarchy's same-user IPC. Like every Omarchy IPC target, its setup and control methods are available to other processes running as the same user; this does not cross the operating system's user boundary. Background discovery polling runs only while the panel is open or at least one previously discovered light remains known.

Omarchy plugins run unsandboxed as the current user. Review plugin code before installation, as you would for any third-party Omarchy plugin.

## Development

Validate the repository with:

```bash
./tests/run
```

Development checks require `shellcheck`, `node`, `ripgrep`, `qmllint`, `gdbus` (from GLib), and an Omarchy installation with its plugin validator. The suite replaces Avahi, curl, NetworkManager, Zenity, browser, and notification commands with temporary fixtures; it never contacts a real light or changes the host network. Set `KEYLIGHTS_TEST_REQUIRE_DBUS=1` to require the tray ownership/SIGTERM lifecycle test when a writable session D-Bus is available.

Agent skills are vendored on the development branch under `.agents/skills` and
locked by `skills-lock.json`. Run `bin/update-skills` to update them or
`bin/update-skills --check` to verify them. The updater creates local
`.claude/skills` aliases; those symlinks are ignored because Omarchy plugins
may not contain symlinks. Release tags and plugin payloads intentionally omit
all agent-skill tooling.

## License

MIT

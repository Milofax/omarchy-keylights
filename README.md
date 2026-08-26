# Key Lights for Omarchy

An Omarchy bar plugin that automatically discovers and controls Elgato Key Lights on the local network.

## Features

- Automatic discovery through the Elgato `_elg._tcp` mDNS service
- Individual on/off switches for every discovered light
- Shared brightness and color-temperature controls with explicit mixed-value states
- Fast retries for occasionally unresponsive light APIs
- A bar icon that shows on, off, partial, and setup states
- Setup flow for factory-reset lights through Elgato's local pairing page
- No Elgato Control Center installation required

## Requirements

- Omarchy with Quickshell plugin support
- `avahi`, `curl`, and `jq` for discovery and control
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

The icon is filled while at least one light is on. It is crossed while all lights are off, carries an `×` when setup or attention is required, and disappears when no configured or reset Key Light is discoverable.

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
```

## Privacy and security

The plugin communicates only with Avahi, NetworkManager, and discovered Elgato lights on the local network. Discovery verifies the Elgato accessory API before exposing an endpoint to the panel; a changed address is verified again before retrying a command. The plugin does not contact a cloud service or store Wi-Fi credentials.

Omarchy plugins run unsandboxed as the current user. Review plugin code before installation, as you would for any third-party Omarchy plugin.

## Development

Validate the repository with:

```bash
omarchy plugin validate .
./tests/run
```

## License

MIT

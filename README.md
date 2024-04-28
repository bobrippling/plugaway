# PlugAway

Inspired by [`autokbisw`], this simple app detects when you plug in, or remove a USB keyboard and switches between your first and second keyboard layout automatically.

[`autokbisw`]: https://github.com/ohueter/autokbisw

## Building

`make` or `swiftc plugaway.swift`

## Installation

- Save the binary (`plugaway`) to a known location
- Alter `com.bobrippling.plugaway.plist` to point at said file
- Copy the modified plist to `~/Library/LaunchAgents/`
- Run `launchctl load ~/Library/LaunchAgents/com.bobrippling.plugaway.plist`

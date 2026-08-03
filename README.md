# Sleepy

**Your Mac's sleep timer, one click away.**

Sleepy is a tiny native macOS menu bar app for changing how long your Mac waits
before turning off the display and going to sleep. It has no Dock icon, no main
window, and no settings maze.

## Features

- See the active sleep timer directly in the menu bar
- Choose from 1, 5, 10, 15, 30, 60, and 120 minutes, or Never
- Apply changes to battery, power adapter, or both
- Approve administrator access once, then change presets without more prompts
- Launch automatically when you log in
- Stay in sync with settings changed elsewhere in macOS

Sleepy keeps the display-off and system-sleep timers in sync. It does not modify
disk sleep, wake behavior, standby, or hibernation settings.

## Requirements

- macOS 13 or newer
- Swift 6.2 toolchain to build from source

## Install from source

Clone and build the app:

```sh
git clone https://github.com/stackoverprof/sleepy.git
cd sleepy
./build-app.sh release
open dist/Sleepy.app
```

For regular use, move `Sleepy.app` from `dist` into `/Applications`. Move it
before enabling Launch at Login so macOS remembers the final location.

## Use

1. Click the coffee bean and timer in the menu bar.
2. Choose whether changes apply to battery, power adapter, or both.
3. Select a sleep preset.
4. Approve the macOS administrator prompt the first time.

After the initial approval, preset changes do not require another password.

## Why the first change needs permission

macOS requires administrator access to modify power-management settings.
Sleepy handles this with a small privileged helper installed during the first
change:

```text
/Library/PrivilegedHelperTools/com.erbin.sleepy.helper
/Library/LaunchDaemons/com.erbin.sleepy.helper.plist
```

The helper exposes no general shell or command interface. It accepts only:

- Sleepy's fixed minute presets
- Battery, power adapter, or all-power-source scope
- The `displaysleep` and `sleep` settings managed by `/usr/bin/pmset`

All values are validated again inside the privileged process before `pmset`
runs.

## Development

Run the test suite:

```sh
swift test
```

Build a debug app bundle:

```sh
./build-app.sh debug
open dist/Sleepy.app
```

The project is split into three Swift targets:

| Target | Responsibility |
| --- | --- |
| `Sleepy` | Menu bar interface, current-setting display, and helper client |
| `SleepyCore` | Power-setting model, parser, request validation, and XPC protocol |
| `SleepyHelper` | Narrow privileged service that applies validated settings |

The build script creates an ad hoc signed local app at `dist/Sleepy.app`.

## Remove Sleepy

1. Turn off Launch at Login from the Sleepy menu.
2. Quit Sleepy and delete the app.
3. If you also want to remove the privileged helper, run:

```sh
sudo launchctl bootout system/com.erbin.sleepy.helper
sudo rm -f /Library/PrivilegedHelperTools/com.erbin.sleepy.helper
sudo rm -f /Library/LaunchDaemons/com.erbin.sleepy.helper.plist
```

The first command can report that the service was not found if it is already
stopped. The two helper files can still be removed.

## Notes

- Sleepy synchronizes idle display sleep and system sleep.
- Active power assertions from apps, media playback, sharing services, or macOS
  can temporarily prevent sleep even when a timer is configured.
- The current build is intended for personal installation from source. It is
  locally signed and is not distributed as a notarized release.

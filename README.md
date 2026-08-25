# Sleepy

**Your Mac's sleep timer, one click away.**

Sleepy is a tiny native macOS menu bar app for changing how long your Mac waits
before turning off the display and going to sleep. It has no Dock icon, no main
window, and no settings maze.

## Features

- See the active sleep timer directly in the menu bar
- Glance at a live grey and black day and night world map, with hour stamps
  marking what time it is at each longitude
- Read today's five prayer times, with each prayer's meridian drawn across the
  map as it sweeps toward you
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

## Install

Download `Sleepy-<version>.dmg` from the
[latest release](https://github.com/stackoverprof/sleepy/releases/latest), open
it, and drag Sleepy into Applications.

The app is signed locally rather than notarized, so macOS holds it the first
time. Right-click Sleepy in Applications, choose Open, then confirm. If macOS
refuses outright, clear the quarantine flag and open it again:

```sh
xattr -dr com.apple.quarantine /Applications/Sleepy.app
```

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

1. Click the moon and timer in the menu bar. The map at the top shows where it
   is daylight right now: the dot marks the point the sun is directly overhead,
   and the scale underneath stamps the hour along each meridian, so 12 always
   sits under the sun and 00 on the far side of the world.
2. Choose whether changes apply to battery, power adapter, or both.
3. Select a sleep preset.
4. Approve the macOS administrator prompt the first time.

After the initial approval, preset changes do not require another password.

## Prayer times

The row under the map lists today's five prayers, with the next one lit. Times
follow Kementerian Agama Republik Indonesia: 20 degrees below the horizon for
Fajr, 18 for Isha, the Shafi'i shadow for Asr, and two minutes of ihtiyati on
every entry. They match the published Kemenag timetable to the minute, which the
test suite pins as fixtures.

Each prayer also draws a curve on the map, tracing everywhere it is being called
at this moment. The curves sweep west, so one east of your marker is a prayer
still to come and one west of you has already passed, and the next one is lit
with a head riding it at your own latitude.

Only Dhuhr is a straight meridian, the one the sun stands on. The rest bend,
because the sun has to climb further to reach the same angle away from the
tropics: Maghrib traces the terminator exactly, and a curve simply stops at the
latitude where the sun stops reaching its angle at all, which is the honest
picture of why prayer times run out in the polar summer.

Sleepy asks Location Services for a fix on first launch. Until one arrives, and
whenever permission is refused, it falls back to the coordinate macOS keeps for
your time zone in `/usr/share/zoneinfo/zone.tab`, which lands within a couple of
minutes of the right times. Either way the coordinate stays on the Mac: nothing
is sent anywhere.

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

The build script creates an ad hoc signed local app at `dist/Sleepy.app`. To
package a release, `./Tools/make-dmg.sh` builds that app and wraps it in
`dist/Sleepy-<version>.dmg` with a drag-to-Applications shortcut.

### World map data

The day and night map is drawn from an embedded half-degree land and ocean
bitmask, so the app needs no map service, network access, or image asset. The
mask is generated from Natural Earth 110m land outlines, which are in the public
domain:

```sh
python3 Tools/generate-land-mask.py
```

That rewrites `Sources/SleepyCore/WorldLandMaskData.swift`, which is otherwise
never edited by hand. Daylight comes from the NOAA solar position equations in
`Sources/SleepyCore/SolarPosition.swift`.

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

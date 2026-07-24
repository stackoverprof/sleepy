# Sleepy

Sleepy is a small native macOS menu bar app for changing the computer's idle
sleep timer.

## Build

```sh
./build-app.sh release
open dist/Sleepy.app
```

For regular use, move `Sleepy.app` into `/Applications` before enabling
Launch at Login.

The first sleep change installs a narrowly scoped privileged helper using the
standard macOS administrator prompt. Later changes do not prompt again. The
helper accepts only Sleepy's fixed sleep presets and power-source scopes.

Sleepy changes only the `sleep` value managed by `pmset`. It does not change
display sleep, disk sleep, wake, standby, or hibernation settings.

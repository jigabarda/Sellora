# Sellora Mobile

Sellora Mobile is the Flutter, offline-first clone of the Sellora web app in `../SalesManagementSystem`.

Start with [SELLORA_MOBILE_PROJECT_GUIDE.md](SELLORA_MOBILE_PROJECT_GUIDE.md) before changing code. It explains the product goal, source-of-truth web app, offline database direction, feature roadmap, and operating instructions for developers and AI agents.

For common local development commands, run:

```bash
make help
```

Most common commands:

```bash
make run
make fresh-run
make run-build-apk
make fresh-install-debug
make fresh-install-launch
```

Use `make fresh-run` when the emulator/device still shows an old UI after code changes. It runs the clean rebuild flow before launching the app.

Use `make fresh-install-launch` when you want a finite Android flow instead of an attached Flutter debug session. It cleans, builds the debug APK, installs it, then launches the app with `adb`.

On Windows, install GNU Make or run from a terminal where `make` is on PATH. If `make` is not installed yet, the commands inside `Makefile` can still be run manually with `flutter`/`dart`.

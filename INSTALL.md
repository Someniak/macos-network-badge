# Installation & Setup

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Installation Methods

### Option 1: Install Script (recommended)

```bash
./scripts/install.sh
```

This builds a release binary, creates the `.app` bundle, and copies it to `/Applications/`.

### Option 2: DMG (drag & drop)

```bash
./scripts/create-dmg.sh
```

Open the generated DMG from the `build/` directory and drag **NetworkBadge** into your Applications folder.

### Option 3: Manual

```bash
swift build -c release
./scripts/build-app.sh
cp -R build/NetworkBadge.app /Applications/
```

## Launch

```bash
open /Applications/NetworkBadge.app
```

The app runs in the menu bar — look for the network icon and latency reading at the top of your screen. There is no Dock icon or main window.

## Auto-Launch at Login

### Via the app (easiest)

1. Click the Network Badge icon in the menu bar
2. Toggle **Launch at Login** on

This registers the app as a login item using macOS's built-in system. You can verify it in **System Settings → General → Login Items**.

### Via System Settings (manual)

1. Open **System Settings → General → Login Items**
2. Click **+** under "Open at Login"
3. Select **NetworkBadge** from `/Applications/`

## Uninstall

```bash
rm -rf /Applications/NetworkBadge.app
```

If you enabled Launch at Login, the login item is automatically cleaned up when the app is removed.

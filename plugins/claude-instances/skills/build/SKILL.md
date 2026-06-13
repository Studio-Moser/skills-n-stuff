---
name: build
description: >-
  Build or refresh a renamed duplicate of /Applications/Claude.app so the user can run
  multiple Claude Desktop apps side by side, each signed into a different account. Same
  skill creates a new instance (e.g. "Claude Work", "Claude Client X") or rebuilds an
  existing one to pick up Claude's latest auto-update. Trigger whenever the user wants
  to add another logged-in Claude account, refresh a duplicate Claude app, or mentions
  things like "Claude Work is out of date", "I need a second Claude for my work
  account", "make another Claude instance", "duplicate Claude for client X". Invoke
  with /claude-instances:build.
---

# Build Claude Instance

This skill builds a renamed, ad-hoc-signed duplicate of `/Applications/Claude.app` that:

- Has its own bundle identifier (so macOS treats it as a separate app and lets it run alongside the original)
- Uses its own `~/Library/Application Support/<Name>` directory (so it can be signed into a different account)
- Optionally has a custom icon (so the user can tell instances apart in Finder/Dock)
- Inherits whatever version Claude.app is currently at — re-run the skill any time the original auto-updates to bring the duplicate forward

The same procedure handles both the first build of an instance and every subsequent refresh; the only difference is whether the target `.app` already exists.

## Inputs to gather

1. **Instance name** — the display name of the duplicate, e.g. `Claude Work`, `Claude Client X`, `Claude Personal 2`. This becomes the `.app` filename (`/Applications/<Name>.app`), the user-data folder name (`~/Library/Application Support/<Name>`), and a slug feeds the bundle id. Ask the user if they didn't already say one in their message.

2. **Custom icon** (optional, first time only) — path to a `.icns` file. If the user doesn't provide one, the instance shares Claude's default icon (telling them apart visually becomes hard, but the app still works). If the user previously provided an icon for this instance name, reuse it without asking — it lives at `~/Library/Application Support/claude-instances/icons/<Name>.icns`.

Do not invent a name. If you don't have one, ask — keep the question brief and don't survey the user with options.

## Preconditions

1. `/Applications/Claude.app` exists.
2. If the instance already exists, it's quit (Cmd-Q, not force-killed). Replacing a running bundle corrupts in-flight state and may log the user out.

```bash
NAME="<the instance name>"          # e.g. "Claude Work"
APP="/Applications/$NAME.app"
ls -d "/Applications/Claude.app" 2>&1
pgrep -fl "$NAME" || echo "$NAME not running"
```

If it's running, stop and ask the user to Cmd-Q it. Don't `pkill` yourself — that risks corrupting auth.

## Why this is delicate (read before touching)

Claude is an Electron app. Getting a renamed duplicate to launch *and* keep its own separate login state requires threading five needles, each independently easy to get wrong.

### 1. Do NOT change `CFBundleName`

Electron resolves its helper `.app`s by name derived from `CFBundleName`, looking for `Contents/Frameworks/<CFBundleName> Helper.app`, `<CFBundleName> Helper (GPU).app`, etc. Setting `CFBundleName` to anything other than `Claude` makes Electron search for non-existent helpers; the app crashes during startup with `FATAL:electron/shell/app/electron_main_delegate_mac.mm:65 Unable to find helper app`.

Change only `CFBundleIdentifier` and `CFBundleDisplayName`. Leave `CFBundleName` as `Claude`. The duplicate will show as "Claude" in the Dock/app switcher but as the chosen name in Finder/Spotlight/window titles. Don't "fix" the Dock label by reverting this — it breaks the app.

### 2. Ad-hoc sign inside-out, and DROP `requirements` metadata

A naive `codesign --force --deep --sign -` strips helper entitlements and breaks V8. The correct order is helpers → frameworks → main bundle.

Use `--preserve-metadata=entitlements,flags,runtime` where appropriate. **Do not** include `requirements` — the original Designated Requirement pins Anthropic's Team ID, and an ad-hoc signature can't satisfy a Team-ID-pinned requirement, so verification fails with "nested code is modified or invalid".

### 3. Main-app entitlements need three extras beyond what Anthropic ships

Original `Claude.app` has only `com.apple.security.cs.allow-jit` on the main bundle. That works under Anthropic's signature because library validation passes on matching Team IDs. Ad-hoc signatures have no Team ID, so library validation fails and V8 crashes with SIGTRAP during `v8::Isolate::Dispose`.

The main binary needs all three:
- `com.apple.security.cs.allow-jit` (already present; keep)
- `com.apple.security.cs.disable-library-validation` (add — lets main binary load ad-hoc-signed frameworks/helpers)
- `com.apple.security.cs.allow-unsigned-executable-memory` (add — V8 needs this once library validation is off)

Also add `disable-library-validation` to three of the four helpers: `Claude Helper.app`, `Claude Helper (GPU).app`, `Claude Helper (Renderer).app`. The Plugin helper already ships with it.

### 4. Delete `CFBundleIconName` so a custom icon takes effect on macOS 26+

On macOS 26 (Tahoe) and later, the system prefers `CFBundleIconName` (an asset name inside `Contents/Resources/Assets.car`) over the loose `CFBundleIconFile` → `electron.icns` path. Claude.app ships with both set. If we leave `CFBundleIconName` in place, Finder/Dock read the icon out of `Assets.car` and ignore our swapped `electron.icns` entirely.

Deleting `CFBundleIconName` forces Launch Services to fall back to `CFBundleIconFile`, which is `electron.icns` and now holds the custom icon. On older macOS this key is absent anyway, so deleting it is safe across versions.

### 5. Wrap the main executable to pass `--user-data-dir` on every launch (CRITICAL)

Because `CFBundleName` stays "Claude", Electron's `app.getPath('userData')` returns `~/Library/Application Support/Claude` — the *same* path as the original. Without intervention, all instances share the original's login state.

The fix: replace `Contents/MacOS/Claude` with a shell wrapper that execs the real binary with `--user-data-dir`. The real binary is renamed to `Claude-bin` and lives alongside the wrapper:

```
Contents/MacOS/Claude       # shell wrapper (new)
Contents/MacOS/Claude-bin   # real Mach-O binary (renamed from Claude)
```

The wrapper:

```bash
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/Claude-bin" --user-data-dir="$HOME/Library/Application Support/<Name>" "$@"
```

`Claude-bin` must be signed directly (with entitlements + hardened runtime) because codesign can't apply entitlements to a shell script. The bundle-level sign then seals both files as resources.

## The build procedure

Substitute the user's chosen instance name for `<Name>` and a slug (lowercase, spaces → hyphens) for `<slug>`. Example: `Claude Work` → name `Claude Work`, slug `claude-work`, bundle id `com.anthropic.claudefordesktop.claude-work`.

Run in order. Stop on any failure.

```bash
set -e
NAME="<Name>"                                                   # e.g. "Claude Work"
SLUG="$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-')"           # e.g. "claude-work"
BUNDLE_ID="com.anthropic.claudefordesktop.$SLUG"
APP="/Applications/$NAME.app"
SRC="/Applications/Claude.app"
FW="$APP/Contents/Frameworks"
DATA_DIR="$HOME/Library/Application Support/$NAME"
ICON_CACHE="$HOME/Library/Application Support/claude-instances/icons"
ICON_FILE="$ICON_CACHE/$NAME.icns"

# 1. Replace any old duplicate with a fresh copy of Claude.app
rm -rf "$APP"
cp -R "$SRC" "$APP"

# 2. Change ONLY identifier and display name. CFBundleName stays "Claude".
# Also delete CFBundleIconName (see needle #4 above).
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2>/dev/null || true

# 3. Build augmented main-app entitlements
MAIN_ENT="/tmp/$SLUG-main-ents.plist"
codesign --display --entitlements :- "$SRC" 2>/dev/null | tail -1 > "$MAIN_ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$MAIN_ENT" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.allow-unsigned-executable-memory bool true" "$MAIN_ENT" 2>/dev/null || true

# 4. Sign helpers first, inside-out. Add disable-library-validation to the three lacking it.
for h in "Claude Helper.app" "Claude Helper (GPU).app" "Claude Helper (Renderer).app"; do
  ENT="/tmp/$SLUG-$(echo "$h" | tr ' ()' '___')-ents.plist"
  codesign --display --entitlements :- "$FW/$h" 2>/dev/null | tail -1 > "$ENT"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENT" 2>/dev/null || true
  codesign --force --sign - --entitlements "$ENT" --options runtime "$FW/$h"
done
# Plugin helper already has disable-library-validation; just preserve its entitlements
codesign --force --sign - --preserve-metadata=entitlements,flags,runtime "$FW/Claude Helper (Plugin).app"

# 5. Frameworks — no entitlements, just valid signatures
for f in "Electron Framework.framework" "Mantle.framework" "ReactiveObjC.framework" "Squirrel.framework"; do
  codesign --force --sign - "$FW/$f"
done

# 6. Apply the custom icon, if we have one for this instance.
# If the user provided a fresh icon path this run, copy it into the cache first.
# (The "user-provided-icon path" step happens here, before this block:
#   mkdir -p "$ICON_CACHE"
#   cp "<user-provided path>" "$ICON_FILE"
# )
if [ -f "$ICON_FILE" ]; then
  cp "$ICON_FILE" "$APP/Contents/Resources/electron.icns"
fi

# 7. Install the wrapper: move real binary aside, write shell script in its place
mv "$APP/Contents/MacOS/Claude" "$APP/Contents/MacOS/Claude-bin"
cat > "$APP/Contents/MacOS/Claude" <<WRAPPER
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$DIR/Claude-bin" --user-data-dir="$DATA_DIR" "\$@"
WRAPPER
chmod +x "$APP/Contents/MacOS/Claude"

# 8. Sign the real binary directly with entitlements (entitlements can't apply to a shell script)
codesign --force --sign - --entitlements "$MAIN_ENT" --options runtime "$APP/Contents/MacOS/Claude-bin"

# 9. Sign the whole bundle (seals the wrapper, icon, and modified Info.plist as resources)
codesign --force --sign - --entitlements "$MAIN_ENT" --options runtime "$APP"

# 10. Re-register with Launch Services + clear icon caches
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP"
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null
touch "$APP"
killall iconservicesagent Dock Finder 2>/dev/null
```

Note the heredoc uses `<<WRAPPER` (unquoted) so `$DATA_DIR` interpolates from the parent shell; the `\$DIR`, `\$0`, and `\$@` references inside are escaped so they get baked into the script literally rather than expanding at heredoc-write time.

## Verify before declaring success

Signature verification passing does NOT prove the app launches. The SIGTRAP-in-V8 crash is only caught by actually running it. Always do all four checks.

```bash
# Signature
codesign --verify --strict --verbose "$APP"
# Expect: "valid on disk" + "satisfies its Designated Requirement"

# All three entitlements present on Claude-bin
codesign --display --entitlements :- "$APP/Contents/MacOS/Claude-bin" 2>&1 \
  | grep -oE "allow-jit|disable-library-validation|allow-unsigned-executable-memory" | sort -u
# Expect three lines

# CFBundleIconName gone (so custom icon will take effect)
/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP/Contents/Info.plist" 2>&1
# Expect: 'Print: Entry, ":CFBundleIconName", Does Not Exist'

# Version (should match Claude.app)
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"

# Live launch — confirm it stays alive AND uses the per-instance data dir
"$APP/Contents/MacOS/Claude" > /tmp/$SLUG-smoke.log 2>&1 &
BGPID=$!
sleep 5
if kill -0 $BGPID 2>/dev/null; then
  pgrep -fl "Claude-bin" | grep -q "user-data-dir=$DATA_DIR" \
    && echo "SUCCESS: $NAME launched with its own data dir" \
    || echo "WARNING: launched but --user-data-dir flag not visible"
  pkill -f "$NAME" 2>/dev/null
else
  echo "FAILED — exited early"; cat /tmp/$SLUG-smoke.log
fi
```

Report the new version to the user.

## Saving the user's icon (when they provide one)

If the user supplies an icon path this run, save it to the cache before step 6 so future refreshes can find it:

```bash
mkdir -p "$ICON_CACHE"
cp "<path the user gave you>" "$ICON_FILE"
```

Use the original path as-is (allow `~` and shell-style paths — the user might paste a Downloads path or drag-drop into the terminal). If the source file doesn't exist or isn't a `.icns`, surface the error rather than silently skipping; don't try to convert PNG/JPG inline.

## Failure signatures and what they mean

- **App appears with the default Claude icon despite providing a custom one** — `CFBundleIconName` wasn't deleted, so macOS 26+ is reading the icon out of `Assets.car` instead of our `electron.icns`. Re-check step 2 and confirm `PlistBuddy Print :CFBundleIconName ...` errors with "Does Not Exist". Then clear icon caches (`rm -rf ~/Library/Caches/com.apple.iconservices.store`; if that's not enough, the system-level cache at `/Library/Caches/com.apple.iconservices.store` via sudo) and `killall iconservicesagent Dock Finder`.
- **Two apps share the same logged-in account** — the wrapper isn't in place or isn't being called. Confirm `Contents/MacOS/Claude` is a shell script and `Claude-bin` exists beside it. Check `pgrep -fl "Claude-bin"` shows the `--user-data-dir` flag for *this* instance's path.
- **`Unable to find helper app`, immediate exit** — `CFBundleName` got changed. Set it back to "Claude".
- **SIGTRAP in `v8::Isolate::Dispose` / `ares_dns_rr_get_ttl`** — missing entitlements on `Claude-bin`. Confirm all three (`allow-jit`, `disable-library-validation`, `allow-unsigned-executable-memory`) are on the Mach-O binary, not just the bundle.
- **`different Team IDs` dyld error** — main app or helpers lack `disable-library-validation`. Re-sign inside-out.
- **`nested code is modified or invalid` from `codesign --verify`** — `requirements` was preserved; drop it from `--preserve-metadata`.
- **App shows as "Claude" not the chosen name in Dock** — not a failure. `CFBundleName` must stay "Claude" for Electron to find its helpers. `CFBundleDisplayName` handles Finder/Spotlight.

## Edge cases

- **First-run Gatekeeper dialog**: macOS may prompt "<Name>.app was downloaded from the internet" after re-signing. Normal; user clicks Open.
- **Permission error on `/Applications`**: surface it; don't silently escalate to `sudo`.
- **Electron major version upgrade**: helper names (`Claude Helper.app`, etc.) could theoretically change. If `ls "$FW"` shows different sub-`.app`s, stop and report the actual contents to the user.
- **Instance data lost after refresh**: check that `~/Library/Application Support/<Name>/` still exists. The build only rebuilds the `.app` bundle, never touches user data.
- **Multiple instances**: there's no list-of-instances state; each is identified purely by its `.app` name. To enumerate, scan `/Applications` for `.app` bundles whose `Contents/MacOS/Claude-bin` exists.

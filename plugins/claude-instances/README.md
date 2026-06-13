# Claude Instances

Run multiple Claude Desktop apps on the same Mac, each signed into a different account. Useful when you have a personal subscription and a work subscription (or any two), and you want both logged in at the same time without juggling sign-outs.

## Why

The Claude Desktop app is single-account: signing into account B logs out of account A. Apple's standard "duplicate an app to get a second instance" trick is non-trivial for Electron apps — there are five things that have to be right (helper-app lookup, code signing, V8 entitlements, icon-cache behavior on macOS Tahoe, and Electron's user-data path) and getting any one of them wrong leaves you with an app that either won't launch or shares state with the original.

This plugin bakes that knowledge into a single skill that handles all five. It works on macOS 13+ and is verified on macOS 26 (Tahoe).

## Installation

```bash
/plugin install claude-instances@studio-moser
```

Requires:
- `/Applications/Claude.app` already installed
- An `.icns` icon file if you want the duplicate to be visually distinct (recommended — otherwise it looks identical to the original in the Dock)

## Skills

### `/claude-instances:build`

Build a new Claude Desktop instance, or refresh an existing one.

```
/claude-instances:build
```

The skill asks for the instance name (e.g. "Claude Work", "Claude Client X") and an optional `.icns` icon. It creates `/Applications/<Name>.app` with:

- A unique bundle identifier (`com.anthropic.claudefordesktop.<slug>`) so macOS treats it as a separate app
- A wrapper that launches with `--user-data-dir=~/Library/Application Support/<Name>` so it has its own login state
- All the entitlements V8 needs under ad-hoc signing
- The custom icon, applied so it survives macOS 26's `Assets.car` icon-resolution behavior

The icon is cached at `~/Library/Application Support/claude-instances/icons/<Name>.icns`, so future refreshes don't need it re-supplied.

Run the same skill again any time the original Claude auto-updates — it rebuilds the duplicate from the current `Claude.app` while preserving your login state and icon.

## How it works (short version)

Each instance is a renamed copy of `Claude.app` with:

1. `CFBundleIdentifier` changed (so it's a distinct app to macOS).
2. `CFBundleDisplayName` changed (so it looks distinct in Finder/Spotlight).
3. `CFBundleName` **un**changed — Electron uses it to locate `Claude Helper.app` and friends.
4. `CFBundleIconName` deleted (so the loose `electron.icns` icon takes effect on macOS 26+).
5. The main executable replaced by a shell wrapper that exec's the original binary with `--user-data-dir`.
6. Ad-hoc re-signed inside-out (helpers → frameworks → main) with extra entitlements added so V8 still works without Apple's Team-ID signature.

See `skills/build/SKILL.md` for the full rationale, the exact procedure, and failure-mode triage.

## Caveats

- **Not officially supported by Anthropic.** Modifying a signed `.app` is fair game on your own Mac, but check Anthropic's ToS before relying on it for production work.
- **Auto-updates only touch the original.** Each new Claude release requires re-running `/claude-instances:build` for every instance you want to keep current.
- **All instances appear as "Claude" in the Dock.** They show their custom name in Finder, Spotlight, and window titles, but the Dock label and app-switcher entry read `CFBundleName`, which has to stay "Claude" for Electron's helper-app lookup to work. Use a custom icon to tell them apart visually.

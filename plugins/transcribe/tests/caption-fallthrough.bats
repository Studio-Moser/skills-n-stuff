#!/usr/bin/env bats
# Tier 0 caption selection and tier 2 dependency guarding.
#
# Both behaviours here are regressions with a known failure in the wild
# (2026-09-08): a video whose auto "en" track returned HTTP 429 produced no
# transcript at all even though its "en-orig" track downloaded fine, and a
# plugin copy with no node_modules passed verify-deps.sh and then died inside
# tier 2 with a raw ERR_MODULE_NOT_FOUND stack trace.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  export TRANSCRIBE_STUB_STATE="$BATS_TEST_TMPDIR/attempts.log"
  : > "$TRANSCRIBE_STUB_STATE"
}

# A yt-dlp stub that serves captions for exactly one language and, for every
# other language, exits 0 having written nothing. Exiting 0 on failure is the
# behaviour that made the original bug invisible: yt-dlp reports success at the
# process level while abandoning the subtitle download.
make_ytdlp_stub() {
  local serves_lang="$1"
  cat > "$STUB_DIR/yt-dlp" <<STUB
#!/usr/bin/env bash
lang=""; out=""; want_print=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --version) echo "0.0.0-stub"; exit 0 ;;
    --print)   want_print=1; shift ;;
    --sub-lang) lang="\$2"; shift 2 ;;
    -o)         out="\$2";  shift 2 ;;
    *) shift ;;
  esac
done
if [ "\$want_print" = 1 ]; then
  echo "Stub Video|||42"
  exit 0
fi
echo "\$lang" >> "\$TRANSCRIBE_STUB_STATE"
if [ "\$lang" = "$serves_lang" ]; then
  dir="\$(dirname "\$out")"
  mkdir -p "\$dir"
  cat > "\$dir/caps.\$lang.vtt" <<'VTT'
WEBVTT

00:00:00.000 --> 00:00:02.000
the fallthrough reached the original track

VTT
fi
exit 0
STUB
  chmod +x "$STUB_DIR/yt-dlp"
}

@test "tier 0 falls through to en-orig when an earlier track yields nothing" {
  make_ytdlp_stub "en-orig"

  PATH="$STUB_DIR:$PATH" run "$PLUGIN_ROOT/bin/transcribe" "https://youtu.be/stub"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the fallthrough reached the original track"* ]] || return 1
  [[ "$output" == *"youtube-auto-captions"* ]] || return 1
  # The point of the fix: earlier candidates were attempted and did not abort
  # the tier. A single batched --sub-lang call would show one attempt and quit.
  grep -qx "en" "$TRANSCRIBE_STUB_STATE" || return 1
  grep -qx "en-orig" "$TRANSCRIBE_STUB_STATE" || return 1
}

@test "tier 0 prefers a manual track over the auto-generated one" {
  make_ytdlp_stub "en"

  PATH="$STUB_DIR:$PATH" run "$PLUGIN_ROOT/bin/transcribe" "https://youtu.be/stub"

  [ "$status" -eq 0 ]
  [[ "$output" == *"youtube-manual-captions"* ]] || return 1
  # Manual "en" satisfies the request, so no auto track is ever fetched.
  ! grep -qx "en-orig" "$TRANSCRIBE_STUB_STATE" || return 1
}

@test "verify-deps reports a missing playwright package without failing" {
  # Tiers 0 and 1 never touch Playwright, so its absence must not block them.
  copy="$BATS_TEST_TMPDIR/plugin"
  mkdir -p "$copy"
  cp -R "$PLUGIN_ROOT/scripts" "$copy/"
  [ ! -d "$copy/node_modules/playwright" ]

  run bash "$copy/scripts/verify-deps.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"playwright"* ]] || return 1
  [[ "$output" == *"MISSING (tier 2 only)"* ]] || return 1
}

@test "tier 2 names the missing package instead of dying on the import" {
  make_ytdlp_stub "none"   # no captions anywhere, so tier 0 fails

  copy="$BATS_TEST_TMPDIR/plugin2"
  mkdir -p "$copy"
  cp -R "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/scripts" "$copy/"
  [ ! -d "$copy/node_modules/playwright" ]

  # Threads skips tier 1 and goes straight to the Playwright extractor.
  PATH="$STUB_DIR:$PATH" run "$copy/bin/transcribe" "https://www.threads.net/@stub/post/1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"'playwright' package is not installed"* ]] || return 1
  [[ "$output" != *"ERR_MODULE_NOT_FOUND"* ]] || return 1
}

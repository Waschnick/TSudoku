#!/usr/bin/env bash
# TSudoku toolchain contract. Source this; never trust the login shell.
#
# Why this file exists: on the development machine `java` was once broken by a stale jenv
# shim, `adb` is not on the login PATH, and jenv's global JDK is 21 while the Java oracle
# needs 17. Any script that inherits the interactive environment works by luck.
#
# Usage:  source tool/env.sh        # set up the environment
#         bash tool/env.sh --check  # assert everything resolves (gate G0)
#         bash tool/env.sh --boot   # bring up both reference devices
#
# A fresh clone of this repository is enough for the Flutter side. The Java oracle and the
# Android reference app additionally need the upstream workspace (FreeSodukuSrc/,
# difftest-harness/) that sits OUTSIDE this repository; those checks degrade to "skipped"
# rather than failing when it is absent.

# --- paths -------------------------------------------------------------------

TS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export TS_ROOT
export ENGINE="$TS_ROOT/packages/sudoku_engine"
export APP="$TS_ROOT/packages/sudoku_app"
export ASSETS="$APP/assets/puzzles"

# The upstream workspace, if this clone happens to sit inside it. Optional.
export WORKSPACE="$(cd "$TS_ROOT/.." && pwd)"
export UPSTREAM="$WORKSPACE/FreeSodukuSrc"
export HARNESS="$WORKSPACE/difftest-harness"
export ANDROID_REF="$WORKSPACE/android-ref"

# The oracle reads the UPSTREAM corpus, not the vendored copy. They are byte-identical
# (verified), but keeping them distinct means a divergence between them shows up as a
# diff rather than hiding because both sides read the same file.
export UPSTREAM_ASSETS="$UPSTREAM/app/src/main/assets/puzzles"

# --- pinned versions ---------------------------------------------------------
# Measured, not copied from documentation. Regenerate with:
#   fvm flutter --version --machine   (NOTE: emits MULTI-LINE pretty JSON)
export EXPECT_FLUTTER="3.47.6"
export EXPECT_DART="3.13.5"
export EXPECT_FLUTTER_REV="5fc346839b5d0eef006ed8404392afb4dfae428d"
export EXPECT_JAVA="17.0.16"
export EXPECT_GRADLE="8.14.5"
export REF_AVD="Pixel_6_API_34"
export REF_IOS_DEVICE="iPhone 17"
export EXPECT_ADK_FILES="96"
export EXPECT_ADK_RECORDS="45166"

# --- java (oracle only) ------------------------------------------------------
# Pinned explicitly. jenv's global is 21; the Android project and the oracle want 17.
export JAVA_HOME="/Library/Java/JavaVirtualMachines/liberica-jdk-17-full.jdk/Contents/Home"

# --- android -----------------------------------------------------------------
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"   # some tools still read the legacy name
export SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
export EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"

# --- gradle (Android reference app only) -------------------------------------
# AGP 8.7.3 refuses Gradle < 8.9, and does not support Gradle 9.x -- which is what
# Homebrew's default `gradle` now is. Hence the keg-only gradle@8.
export GRADLE_HOME="/opt/homebrew/opt/gradle@8"
export GRADLE="$GRADLE_HOME/bin/gradle"

# --- PATH --------------------------------------------------------------------
# /opt/homebrew/bin FIRST and unconditionally: without it a pristine shell
# (`env -i`) cannot find fvm or magick, and the G0 assertions that depend on fvm
# were silently SKIPPED rather than failing. Measured.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export PATH="$JAVA_HOME/bin:$GRADLE_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

# Prefer the fvm-pinned SDK for bare `flutter`/`dart` inside the project.
if [ -x "$TS_ROOT/.fvm/flutter_sdk/bin/flutter" ]; then
  export PATH="$TS_ROOT/.fvm/flutter_sdk/bin:$PATH"
fi

# Absolute paths to the pinned SDK binaries. Harness scripts use these rather than a bare
# `dart`, so that a script which forgets to source this file fails loudly on an unset
# variable instead of quietly running whichever Dart the login shell happens to expose.
export FLUTTER="$(command -v flutter || true)"
export DART="$(command -v dart || true)"

# --- helpers -----------------------------------------------------------------

# `sleep` is unavailable in some sandboxed runners; poll with a portable spin.
_wait_for() {            # _wait_for <seconds> <command...>
  local limit="$1"; shift
  local i=0
  while [ "$i" -lt "$limit" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    i=$((i + 1))
    /bin/sleep 1 2>/dev/null || :
  done
  return 1
}

android_booted() {
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

# Boot the reference AVD, idempotently.
#
# The emulator MUST be fully detached. Launched as a plain background child it dies with
# the parent shell -- which is what happens when an agent's background task is killed,
# silently removing the reference device mid-protocol. `setsid` does NOT exist on macOS,
# so nohup + stdin redirected away from the terminal + disown is what actually reparents
# it to init. Verify with `ps -o ppid= -p <qemu pid>`, which must print 1. Note the
# process is named qemu-system-aarch64, not `emulator`.
boot_android_ref() {
  android_booted && { echo "android: already booted"; return 0; }
  nohup "$EMULATOR" -avd "$REF_AVD" -no-snapshot-load -no-audio -no-boot-anim \
    >/dev/null 2>&1 < /dev/null &
  disown 2>/dev/null || :
  adb start-server >/dev/null 2>&1
  _wait_for 300 android_booted || { echo "android: BOOT TIMEOUT" >&2; return 1; }
  # Freeze animations so captures are reproducible. Does NOT freeze the in-game timer.
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
  echo "android: booted"
}

boot_ios_ref() {
  xcrun simctl boot "$REF_IOS_DEVICE" 2>/dev/null || true
  _wait_for 120 bash -c 'xcrun simctl list devices | grep -q "Booted"' \
    || { echo "ios: BOOT TIMEOUT" >&2; return 1; }
  echo "ios: booted"
}

# --- gate G0 -----------------------------------------------------------------

_check() {
  local fails=0
  _ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; }
  _skip() { printf '  \033[33m--\033[0m   %s\n' "$1"; }
  _fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }

  echo "toolchain check (gate G0)"

  # --- layout. Assert the directories the other gates dereference actually exist,
  # --- or a renamed/moved tree makes later gates match nothing and pass vacuously.
  local d
  for d in ENGINE APP; do
    [ -d "${!d}" ] && _ok "\$$d -> ${!d#$TS_ROOT/}" || _fail "\$$d does not exist: ${!d}"
  done

  # --- flutter + dart, via the project pin
  if command -v fvm >/dev/null 2>&1; then
    local fj fv dv rev
    fj="$(cd "$TS_ROOT" && fvm flutter --version --machine 2>/dev/null)"
    fv="$(printf '%s' "$fj" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("frameworkVersion",""))' 2>/dev/null)"
    dv="$(printf '%s' "$fj" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("dartSdkVersion",""))' 2>/dev/null)"
    rev="$(printf '%s' "$fj" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("frameworkRevision",""))' 2>/dev/null)"
    [ "$fv" = "$EXPECT_FLUTTER" ] && _ok "flutter $fv" || _fail "flutter: got '$fv', want $EXPECT_FLUTTER"
    [ "$dv" = "$EXPECT_DART" ]    && _ok "dart $dv"    || _fail "dart: got '$dv', want $EXPECT_DART"
    [ "$rev" = "$EXPECT_FLUTTER_REV" ] && _ok "revision ${rev:0:10}" \
      || _fail "flutter revision: got '${rev:0:10}', want ${EXPECT_FLUTTER_REV:0:10}"
  else
    _fail "fvm not on PATH"
  fi
  # fvm in a directory with no .fvmrc is a SILENT no-op: zero output, exit 0.
  [ -f "$TS_ROOT/.fvmrc" ] && _ok ".fvmrc pin present" || _fail ".fvmrc missing -- every fvm call here would silently do nothing"

  # --- ios. simctl is authoritative; the Runtimes directory does NOT exist on
  # --- current Xcode, so never test for that path.
  local nrt
  nrt="$(xcrun simctl list runtimes 2>/dev/null | grep -c 'iOS')"
  [ "$nrt" -ge 1 ] && _ok "iOS runtimes: $nrt" || _fail "no iOS simulator runtime (xcodebuild -downloadPlatform iOS)"
  xcrun simctl list devices available 2>/dev/null | grep -q "$REF_IOS_DEVICE" \
    && _ok "iOS device $REF_IOS_DEVICE" || _fail "iOS device $REF_IOS_DEVICE unavailable"

  # --- android sdk
  command -v adb >/dev/null 2>&1 && _ok "adb $(adb version | head -1 | awk '{print $5}')" \
    || _fail "adb not on PATH"
  [ -d "$ANDROID_SDK_ROOT/platforms/android-35" ] && _ok "platforms;android-35" \
    || _fail "platforms;android-35 missing (compileSdk 35 needs it)"
  [ -d "$HOME/.android/avd/${REF_AVD}.avd" ] && _ok "AVD $REF_AVD" \
    || _fail "AVD $REF_AVD missing"

  # --- imagemagick, for the golden pixel gate
  command -v magick >/dev/null 2>&1 \
    && _ok "magick $(magick -version | awk '/^Version/{print $3}')" \
    || _fail "magick absent (brew install imagemagick)"

  # --- the vendored puzzle corpus. This is repository content, so it must be exact.
  local nf nr
  nf="$(ls "$ASSETS"/*.adk 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$nf" = "$EXPECT_ADK_FILES" ]; then
    _ok "assets: $nf .adk files"
    nr=0
    for f in "$ASSETS"/*.adk; do nr=$((nr + $(grep -vc '^#' "$f"))); done
    [ "$nr" = "$EXPECT_ADK_RECORDS" ] && _ok "assets: $nr records" \
      || _fail "assets: got $nr records, want $EXPECT_ADK_RECORDS"
    # CRLF is load-bearing: field 3 is followed by CR and the parser must split on \r?\n.
    # If git ever normalises these, this is the assertion that catches it.
    local ncr
    ncr="$(tr -cd '\r' < "$ASSETS/squiggly_x_1.adk" 2>/dev/null | wc -c | tr -d ' ')"
    [ "${ncr:-0}" -gt 0 ] && _ok "assets: CRLF preserved ($ncr CR in squiggly_x_1)" \
      || _fail "assets: CRLF STRIPPED -- check .gitattributes (core.autocrlf rewrote them)"
  else
    _fail "assets: got $nf .adk files, want $EXPECT_ADK_FILES"
  fi

  # --- optional: the Java oracle and Android reference live outside this repo.
  if [ -d "$UPSTREAM" ]; then
    local jv
    jv="$("$JAVA_HOME/bin/javac" -version 2>&1 | awk '{print $2}')"
    [ "$jv" = "$EXPECT_JAVA" ] && _ok "javac $jv" || _fail "javac: got '$jv', want $EXPECT_JAVA"
    if [ -x "$GRADLE" ]; then
      local gv
      gv="$("$GRADLE" --version 2>/dev/null | awk '/^Gradle /{print $2}')"
      [ "$gv" = "$EXPECT_GRADLE" ] && _ok "gradle $gv" || _fail "gradle: got '$gv', want $EXPECT_GRADLE"
    else
      _fail "gradle absent at $GRADLE (brew install gradle@8)"
    fi
    [ -d "$HARNESS" ] && _ok "oracle harness present" || _skip "difftest-harness absent"
  else
    _skip "upstream workspace absent -- oracle and android-ref checks skipped"
    _skip "(that is expected in a standalone clone)"
  fi

  echo
  [ "$fails" -eq 0 ] && echo "G0 PASS" || echo "G0 FAIL ($fails)"
  return "$fails"
}

case "${1:-}" in
  --check) _check ;;
  --boot)  boot_android_ref; boot_ios_ref ;;
esac

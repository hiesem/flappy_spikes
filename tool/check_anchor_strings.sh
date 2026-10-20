#!/usr/bin/env bash
# PRD-2.5 §3.5 WP-STRINGS: fails (exit 1) when any line of
# tool/anchor_strings.txt is a whole string in the Dart AOT snapshot of a
# release build: every lib/*/libapp.so of an AAB (base/lib/...) or APK, or
# Payload/*.app/Frameworks/App.framework/App of an IPA.
# Usage: tool/check_anchor_strings.sh <app.aab|app.apk|app.ipa>
# Exact whole-string match (`strings -n 4` + `grep -xFf`): substrings such as
# `coins_spent` are fine. Not listed on purpose: `coins`, `noAds` (enum
# names, never obfuscated), `players` (audio-focus channel key, also native),
# `seal` / `integrity` (common words).
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <app.aab|app.apk|app.ipa>" >&2
  exit 2
fi
archive="$1"
list="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/anchor_strings.txt"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$archive" in
  *.ipa) unzip -q -o "$archive" 'Payload/*.app/Frameworks/App.framework/App' -d "$work" ;;
  *.aab | *.apk) unzip -q -o "$archive" '*lib/*/libapp.so' -d "$work" ;;
  *) echo "unknown archive type: $archive" >&2; exit 2 ;;
esac

mapfile -t bins < <(find "$work" -type f \( -name libapp.so -o -path '*App.framework/App' \) | sort)
if [[ ${#bins[@]} -eq 0 ]]; then
  echo "no libapp.so / App.framework/App in $archive" >&2
  exit 2
fi

status=0
for bin in "${bins[@]}"; do
  rel="${bin#"$work"/}"
  hits="$(strings -n 4 "$bin" | grep -xFf "$list" | sort -u || true)"
  if [[ -n "$hits" ]]; then
    status=1
    echo "FAIL $rel:"
    sed 's/^/  /' <<<"$hits"
  else
    echo "ok   $rel ($(grep -c . "$list") anchors absent)"
  fi
done
exit $status

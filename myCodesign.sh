#!/usr/bin/env bash

# -e (errexit)
#   Skript bricht sofort ab, wenn ein Befehl einen Fehler (Exit-Code ≠ 0) liefert.
#   → Verhindert, dass das Skript nach Fehlern „einfach weitermacht“.
# -u (nounset)
#   Verwendung einer nicht gesetzten Variable führt zu einem Fehler und beendet das Skript.
#   → Hilft Tippfehler oder vergessene Variablen früh zu erkennen.
# -o pipefail
#   In einer Pipe (cmd1 | cmd2 | cmd3) zählt als Exit-Code der Pipe der erste fehlgeschlagene Befehl, nicht nur der letzte.
#   → Fehler in früheren Pipe-Kommandos werden nicht versteckt.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-binary-or-app>"
  exit 1
fi

target="$1"

xattr -cr "$target" || true
# Run codesign verification and capture output (do not exit on non-zero)
output="$(codesign --verify --deep --verbose "$target" 2>&1 || true)"

echo "$output"

if grep -q "code object is not signed at all" <<< "$output"; then
  echo "Target is not signed. Signing with ad-hoc identity..."
  codesign --force --deep -s - "$target" || true
else
  echo "Target is already signed or another error occurred."
fi



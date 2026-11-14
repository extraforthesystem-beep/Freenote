#!/usr/bin/env bash
# Reports layout literals in NoteApp that are off the design-token scales.
# A report, not a gate: it always exits 0.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 0

SPACING=" 0 2 4 8 12 16 20 24 32 "
RADIUS=" 4 8 10 12 16 20 "
SHOW_VALUES=0
[[ ${1:-} == --values ]] && SHOW_VALUES=1

TMP=$(mktemp) || exit 0
trap 'rm -f "$TMP"' EXIT

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(rg --files NoteApp -g '*.swift' | grep -v '^NoteApp/Design/')

area_of() {
  local path=$1 area
  area=${path#NoteApp/}
  case $area in
    */*) printf '%s' "${area%%/*}" ;;
    *) printf '(root)' ;;
  esac
}

collect() { # kind pattern allowed-scale extractor
  local kind=$1 pattern=$2 allowed=$3
  rg -o --no-heading --with-filename "$pattern" "${files[@]}" 2>/dev/null |
    while IFS= read -r hit; do
      local path=${hit%%:*} match=${hit#*:} value
      value=$(printf '%s' "$match" | grep -oE -- '-?[0-9]+' | tail -1)
      [[ $allowed == *" $value "* ]] && continue
      printf '%s\t%s\t%s\n' "$kind" "$(area_of "$path")" "$value" >> "$TMP"
    done
}

collect padding '\.padding\((?:\[[^]]*\], *)?(?:\.(?:horizontal|vertical|top|bottom|leading|trailing), *)?(-?[0-9]+)\)' "$SPACING"
collect spacing 'spacing: [0-9]+' "$SPACING"
collect radius 'cornerRadius: [0-9]+' "$RADIUS"

rg -n --no-heading -e 'withAnimation\(' -e '\.animation\(' "${files[@]}" 2>/dev/null |
  grep -v 'AppMotion' |
  while IFS= read -r hit; do
    printf 'anim\t%s\t\n' "$(area_of "${hit%%:*}")" >> "$TMP"
  done

printf '%-10s %7s %8s %7s %5s\n' area padding spacing radius anim
awk -F'\t' '
  BEGIN {
    n = split("(root) AI Audio Backup Boards Export Import Library Notebook Search Settings Study TextDocs", seed, " ")
    for (i = 1; i <= n; i++) areas[seed[i]] = 1
  }
  { count[$2, $1]++; areas[$2] = 1 }
  END {
    for (a in areas)
      printf "%-10s %7d %8d %7d %5d\n", a, count[a, "padding"], count[a, "spacing"], count[a, "radius"], count[a, "anim"]
  }' "$TMP" | sort
awk -F'\t' '
  { total[$1]++ }
  END { printf "%-10s %7d %8d %7d %5d\n", "TOTAL", total["padding"], total["spacing"], total["radius"], total["anim"] }' "$TMP"

((SHOW_VALUES)) || exit 0

printf '\noff-scale values across the app\n'
for kind in padding spacing radius; do
  line=""
  while read -r value count; do
    line+="$value ($count)  "
  done < <(awk -F'\t' -v kind="$kind" '$1 == kind { values[$3]++ } END { for (v in values) print v, values[v] }' "$TMP" |
    sort -n)
  printf '%-8s%s\n' "$kind" "${line:-none}"
done
printf '%-8s%s\n' anim "$(awk -F'\t' '$1 == "anim" { n++ } END { print n + 0 " lines without AppMotion" }' "$TMP")"
exit 0

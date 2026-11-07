#!/bin/bash
# Export every named state through the production container, at both scales.
#
# Not a picture of a card: a picture of the panel the app actually draws —
# shape, corner radii, cutout, padding, clipping and page dots included — with
# an explicit geometry fixture and a fixed clock, so two runs of the same
# commit produce the same bytes and a diff between runs means something.
#
# Four machines, because the only per-Mac variables in a panel's size are the
# cutout it hangs from and the scale the app takes from the panel's physical
# width: the 13-inch reference, the 14-inch, the 16-inch (the largest that
# ships, and the one `LEDGE_SIM_DISPLAY=16` reproduces so an export can be held
# against a real overlay), and a display with no cutout at all.
#
# Fails if a state produced no file; if anything is drawn on the panel's left,
# right or bottom edge — the panel reserves room for the tallest card plus a
# margin, so content reaching an edge is content that was cut off; or if two
# states exported identical bytes, which means one of them is not showing what
# its name says. The first sweep caught exactly that: a satellite state written
# as a HUD, where the satellite has no seat.
#
# `--sections` renders the older bare-card sweep instead, which is still the
# quickest way to compare many states of one card side by side.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$ROOT/.build/debug/LedgePreview"
OUT="${LEDGE_GALLERY_DIR:-$HOME/Library/Developer/Ledge/gallery}/$(date +%Y%m%d-%H%M%S)"
MACS=(13 14 16 none)

SECTIONS=(
    split empty weather timerears ears compact levels
    eyes bottoms timerheights timer media calendar
)

if [[ ! -x "$BINARY" ]]; then
    echo "no preview binary — run: swift build -c debug" >&2
    exit 1
fi

mkdir -p "$OUT"
STATUS=0
COUNT=0

# Sections are bare cards at reference units — the only layout production
# actually performs. The scales live in the state sweep, which renders through
# the container that applies them.
render_sections() {
    for scale in 1.0; do
        for section in "${SECTIONS[@]}"; do
            local shot="$OUT/section-${section}.png"
            LEDGE_GALLERY_ONLY="$section" \
            LEDGE_GALLERY_SHOT="$shot" "$BINARY" >/dev/null 2>&1
            if [[ -f "$shot" ]]; then
                COUNT=$((COUNT + 1))
            else
                echo "missing: $section at $scale" >&2
                STATUS=1
            fi
        done
    done
}

render_states() {
    local manifest="$OUT/manifest.json"
    # The catalogue comes from the binary, so the list lives in one place.
    local states
    states="$(LEDGE_GALLERY_STATE=list "$BINARY" 2>/dev/null)"
    if [[ -z "$states" ]]; then
        echo "the preview listed no states" >&2
        exit 1
    fi

    {
        echo "{"
        echo "  \"commit\": \"$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\","
        echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"exports\": ["
    } > "$manifest"

    local first=1
    for mac in "${MACS[@]}"; do
        while IFS= read -r state; do
            [[ -z "$state" ]] && continue
            local shot="$OUT/${state}@${mac}.png"
            local line
            line="$(LEDGE_GALLERY_STATE="$state" LEDGE_GALLERY_MAC="$mac" \
                    LEDGE_GALLERY_SHOT="$shot" "$BINARY" 2>/dev/null | tail -1)"

            if [[ ! -f "$shot" || -z "$line" ]]; then
                echo "missing: $state on $mac" >&2
                STATUS=1
                continue
            fi
            if [[ "$line" != *'"clipped":[]'* ]]; then
                echo "clipped: $state on $mac — $line" >&2
                STATUS=1
            fi

            local digest
            digest="$(shasum -a 256 "$shot" | cut -d' ' -f1)"
            [[ $first -eq 0 ]] && echo "," >> "$manifest"
            first=0
            # The report the binary printed, plus what the file turned out to
            # be: the digest is what makes two runs comparable without opening
            # a single image.
            printf '    %s' "${line%\}}, \"file\": \"$(basename "$shot")\", \"sha256\": \"$digest\"}" \
                >> "$manifest"
            COUNT=$((COUNT + 1))
        done <<< "$states"
    done

    printf '\n  ]\n}\n' >> "$manifest"

    # Two states, one picture: whichever one is wrong, the pair is not telling
    # the truth about what the app draws.
    local twins
    twins="$(grep -o '"sha256": "[a-f0-9]*"' "$manifest" | sort | uniq -d)"
    if [[ -n "$twins" ]]; then
        while IFS= read -r digest; do
            [[ -z "$digest" ]] && continue
            local names
            names="$(grep "$digest" "$manifest" | grep -o '"file": "[^"]*"' | tr '\n' ' ')"
            echo "identical exports: $names" >&2
        done <<< "$twins"
        STATUS=1
    fi

    echo "manifest: $manifest"
}

if [[ "${1:-}" == "--sections" ]]; then
    render_sections
else
    render_states
fi

echo "$COUNT exports in $OUT"
exit $STATUS

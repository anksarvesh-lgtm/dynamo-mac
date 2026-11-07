#!/bin/bash
# Record how many times each release asset has been downloaded.
#
# GitHub keeps a running total per asset and no history at all: the moment a
# number changes, what it used to be is gone. So this appends a dated row for
# every asset and never rewrites one — the series is the only way to answer
# "how many this week", and it can only be built forward from today.
#
# The file lives in the *website* repository, which is private, under data/
# rather than public/ — Cloudflare serves only public/, so nothing here is
# reachable from ledgeapp.dev. Verified rather than assumed: /README.md and
# /.gitignore both answer 404 on the live site.
#
# It is not committed automatically. Writing a file on a timer is one thing;
# putting commits in your history while you sleep is another. `--commit` does
# it when you want it, and never pushes.
#
#   downloads.sh            append today's counts (skips a day already written)
#   downloads.sh --report    print what has been collected
#   downloads.sh --force     append even if today is already recorded
#   downloads.sh --commit    append, then commit the file locally (no push)
set -uo pipefail

REPO="${LEDGE_REPO:-egemertbalcik/Ledge}"
CSV="${LEDGE_DOWNLOADS_CSV:-$HOME/Developer/ledge-website/data/downloads.csv}"
TODAY="$(date +%F)"

report() {
    [[ -f "$CSV" ]] || { echo "nothing recorded yet: $CSV" >&2; exit 1; }
    echo "$CSV"
    echo
    # Totals per day, split into the two numbers worth knowing: disk images
    # people downloaded, and appcast fetches — one per running copy per check,
    # which is closer to "how many installs are out there".
    awk -F, 'NR > 1 {
        if ($3 ~ /\.dmg$/) dmg[$1] += $4
        else if ($3 == "appcast.xml") feed[$1] += $4
        else if ($3 ~ /\.delta$/) delta[$1] += $4
    }
    END {
        printf "%-12s %8s %8s %8s\n", "date", "dmg", "deltas", "checks"
        for (d in dmg) printf "%-12s %8d %8d %8d\n", d, dmg[d], delta[d], feed[d]
    }' "$CSV" | (read -r header; echo "$header"; sort)
}

case "${1:-}" in
    --report) report; exit 0 ;;
esac

mkdir -p "$(dirname "$CSV")"
if [[ ! -f "$CSV" ]]; then
    echo "date,tag,asset,count" > "$CSV"
fi

if [[ "${1:-}" != "--force" ]] && grep -q "^$TODAY," "$CSV"; then
    echo "already recorded for $TODAY — nothing to do"
    exit 0
fi

rows="$(gh api "repos/$REPO/releases" --paginate \
    --jq ".[] | . as \$r | .assets[] | \"$TODAY,\(\$r.tag_name),\(.name),\(.download_count)\"" 2>/dev/null)"

if [[ -z "$rows" ]]; then
    echo "error: no rows from the API — is gh authenticated?" >&2
    exit 1
fi

printf '%s\n' "$rows" >> "$CSV"
echo "recorded $(printf '%s\n' "$rows" | wc -l | tr -d ' ') assets for $TODAY in $CSV"

if [[ "${1:-}" == "--commit" ]]; then
    repo="$(cd "$(dirname "$CSV")/.." && pwd)"
    git -C "$repo" add "$CSV"
    git -C "$repo" -c user.name="Ege Mert Balçık" -c user.email="ege.mert.balcik@gmail.com" \
        commit -q -m "Record downloads for $TODAY" && echo "committed in $repo (not pushed)"
fi

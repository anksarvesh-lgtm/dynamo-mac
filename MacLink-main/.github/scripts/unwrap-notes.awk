# SPDX-License-Identifier: GPL-3.0-or-later
# Joins hard-wrapped Markdown lines: GitHub shows every line break in
# release notes. Headings, tables, list items, blank lines and code blocks
# keep their own lines.
/^```/ { fence = !fence; out[++n] = $0; next }
fence { out[++n] = $0; next }
{
  line = $0
  start = line ~ /^$/ || line ~ /^#/ || line ~ /^\|/ || line ~ /^ *([-*]|[0-9]+\.) /
  prev = out[n]
  if (!start && n > 0 && prev != "" && prev !~ /^#/ && prev !~ /^\|/ && prev !~ /^```/) {
    sub(/^ +/, "", line); out[n] = prev " " line
  } else {
    out[++n] = line
  }
}
END { for (i = 1; i <= n; i++) print out[i] }

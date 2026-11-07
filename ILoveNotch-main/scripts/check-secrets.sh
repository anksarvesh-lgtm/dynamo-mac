#!/usr/bin/env bash
# Secret gate, run by `make check` and CI: fails if a signing key, certificate, provisioning
# profile, private key, or App Store Connect key reference is in a file git tracks or would add.
# Release credentials live outside the repository (release.env points at them; see
# docs/releasing.md).
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
marker='-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
# Base64 key material: what follows a real key's BEGIN line. Code that only names the format, or
# builds a key at run time, has none.
material='[A-Za-z0-9+/=]{40,}'

# Files that must never be committed.
while IFS= read -r file; do
    echo "error: $file looks like a key, certificate, profile, or credentials file; it must not be committed"
    status=1
done < <(git ls-files --cached --others --exclude-standard |
    grep -E '\.(p8|p12|pfx|cer|pem|key|mobileprovision|provisionprofile|keychain-db)$|(^|/)(release\.env|\.env(\..*)?)$' |
    grep -vE '\.example$' || true)

# Private keys: key material on the line after the BEGIN line, or after an escaped newline on the
# same line (a key inside JSON).
while IFS= read -r file; do
    # Not grep -q: its early exit can kill the first grep with SIGPIPE, which pipefail reads as "no
    # key", so a file holding many keys would pass.
    if grep -A1 -E -- "$marker" "$file" |
        grep -E -- "^[[:space:]]*${material}[[:space:]]*\$|$marker\\\\n$material" >/dev/null; then
        echo "error: $file contains a private key"
        status=1
    fi
done < <(git grep --untracked -lIE -e "$marker" -- ':!scripts/check-secrets.sh' || true)

# App Store Connect key file names with a real key ID (not the X placeholder).
while IFS= read -r match; do
    echo "error: ${match%%:*} contains an App Store Connect key reference"
    status=1
done < <(git grep --untracked -nIE -e '(AuthKey|ApiKey)_[A-Z0-9]{10,}\.p8' -- ':!scripts/check-secrets.sh' |
    grep -vE '(AuthKey|ApiKey)_X+\.p8' || true)

[[ $status -eq 0 ]] && echo "secrets OK"
exit $status

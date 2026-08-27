#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target="$test_dir/../scripts/check-prerequisites.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat >"$fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "git version test" ;;
  rev-parse) echo "/tmp/forgimus-checkout" ;;
  config)
    case "${3:-}" in
      user.name) echo "Test User" ;;
      user.email) echo "test@example.com" ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo "gh version test"
  exit 0
fi
if [ "${1:-} ${2:-}" = "auth status" ]; then
  if printf '%s\n' "$*" | grep -q -- '--json'; then
    printf '%s\n' "${GH_AUTH_RECORD:-}"
    exit "${GH_AUTH_JSON_EXIT:-0}"
  fi
  exit "${GH_AUTH_PLAIN_EXIT:-1}"
fi
if [ "${1:-} ${2:-}" = "repo view" ]; then
  [ "${GH_REPO_READABLE:-yes}" = yes ]
  exit
fi
exit 1
EOF
chmod +x "$fixture/bin/git" "$fixture/bin/gh"

run_check() {
  local record=$1
  set +e
  output=$(GH_AUTH_RECORD="$record" PATH="$fixture/bin:/usr/bin:/bin" \
    "$target" Milofax/example 2>&1)
  status=$?
  set -e
}

require_status() {
  [ "$status" -eq "$1" ] || {
    printf 'expected status %s, got %s\n%s\n' "$1" "$status" "$output" >&2
    exit 1
  }
}

require_output() {
  printf '%s\n' "$output" | grep -Fq -- "$1" || {
    printf 'missing output: %s\n%s\n' "$1" "$output" >&2
    exit 1
  }
}

reject_output() {
  if printf '%s\n' "$output" | grep -Fq -- "$1"; then
    printf 'unexpected output: %s\n%s\n' "$1" "$output" >&2
    exit 1
  fi
}

run_check $'Milofax\x1ferror\x1fdial udp: socket: operation not permitted'
require_status 1
require_output "account Milofax is configured"
require_output "GitHub network and credential-store access"
reject_output "gh auth login"

run_check "You are not logged into any GitHub hosts. To log in, run: gh auth login"
require_status 1
require_output "no active account is configured for github.com"
require_output "gh auth login --hostname github.com"

run_check $'\x1ferror\x1f401 Unauthorized: Bad credentials'
require_status 1
require_output "credentials for github.com are invalid"
require_output "gh auth login"

run_check $'Milofax\x1fsuccess\x1f'
require_status 0
require_output "OK    gh authenticated       Milofax"
require_output "OK    repository readable    Milofax/example"

echo "check-prerequisites regression: PASS"

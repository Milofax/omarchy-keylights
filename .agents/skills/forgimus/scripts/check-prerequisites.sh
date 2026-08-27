#!/usr/bin/env bash
# Check what every other script in this skill assumes.
#
# Usage: check-prerequisites.sh [owner/repo]
# Run from anywhere inside the checkout. With a repository, read access is checked too.
# Output: one "RESULT  check  detail" line per check, then the commands to fix what failed.
# Exit:  0 ready · 1 a prerequisite is missing or unusable
#
# This one never exits 2: it is what tells you why the others would.

set -uo pipefail

repository=${1:-}
failed=0
declare -a remedy=()

report() { printf '%-5s %-22s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && failed=1 || true; }

installer() {
  # Name the command for this machine rather than a list to pick from.
  case "$1" in
    git) arch=git; debian=git; fedora=git; suse=git; mac=git ;;
    gh)  arch=github-cli; debian=gh; fedora=gh; suse=gh; mac=gh ;;
  esac
  if command -v pacman >/dev/null 2>&1; then echo "sudo pacman -S $arch"
  elif command -v apt >/dev/null 2>&1; then echo "sudo apt install $debian"
  elif command -v dnf >/dev/null 2>&1; then echo "sudo dnf install $fedora"
  elif command -v zypper >/dev/null 2>&1; then echo "sudo zypper install $suse"
  elif command -v brew >/dev/null 2>&1; then echo "brew install $mac"
  else echo "install $1 with this system's package manager"
  fi
}

if command -v git >/dev/null 2>&1; then
  report OK "git installed" "$(git --version)"

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    report OK "inside a checkout" "$(git rev-parse --show-toplevel)"
  else
    report FAIL "inside a checkout" "not a git checkout; run this from inside one"
    remedy+=("cd into the checkout, or: git clone <url>")
  fi

  # Committing fails late and confusingly when identity is unset, so ask early.
  name=$(git config --get user.name || true)
  email=$(git config --get user.email || true)
  if [ -n "$name" ] && [ -n "$email" ]; then
    report OK "git identity" "$name <$email>"
  else
    report FAIL "git identity" "user.name or user.email is unset; commits would fail"
    remedy+=('git config --global user.name "Your Name"')
    remedy+=('git config --global user.email "you@example.com"')
  fi
else
  report FAIL "git installed" "not found"
  remedy+=("$(installer git)")
fi

if command -v gh >/dev/null 2>&1; then
  report OK "gh installed" "$(gh --version | head -1)"

  auth_host=${GH_HOST:-github.com}
  auth_record=$(gh auth status --active --hostname "$auth_host" --json hosts \
    --jq '.hosts[] | .[] | select(.active) | [.login, .state, (.error // "")] | join("\u001f")' 2>&1)
  auth_probe=$?

  if [ "$auth_probe" -ne 0 ]; then
    report FAIL "gh authenticated" "authentication could not be checked in this execution environment"
    remedy+=("rerun this same command with GitHub network and credential-store access")
  elif [ -z "$auth_record" ] || [[ "$auth_record" != *$'\x1f'*$'\x1f'* ]]; then
    report FAIL "gh authenticated" "no active account is configured for $auth_host"
    remedy+=("gh auth login --hostname $auth_host          # interactive — run this yourself")
  else
    IFS=$'\x1f' read -r account auth_state auth_error <<<"$auth_record"
    if [ "$auth_state" = success ]; then
      report OK "gh authenticated" "${account:-unknown account}"

      if [ -n "$repository" ]; then
        if gh repo view "$repository" --json nameWithOwner >/dev/null 2>&1; then
          report OK "repository readable" "$repository"
        else
          report FAIL "repository readable" "$repository is not readable with this account"
          remedy+=("check the repository name, GitHub network access, or this account's authorisation")
        fi
      fi
    else
      case "${auth_error,,}" in
        *401*|*"bad credentials"*|*"invalid token"*|*"token is invalid"*)
          report FAIL "gh authenticated" "credentials for ${account:-$auth_host} are invalid"
          remedy+=("gh auth login --hostname $auth_host          # interactive — run this yourself")
          ;;
        *)
          report FAIL "gh authenticated" "account ${account:-for $auth_host} is configured; verification is unavailable here"
          remedy+=("rerun this same command with GitHub network and credential-store access")
          ;;
      esac
    fi
  fi
else
  report FAIL "gh installed" "not found"
  remedy+=("$(installer gh)")
  remedy+=("gh auth login          # interactive — run this yourself")
fi

if [ "$failed" -ne 0 ]; then
  echo
  echo "fix before running any other script in this skill:"
  for line in "${remedy[@]}"; do echo "  $line"; done
fi
exit "$failed"

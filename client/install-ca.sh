#!/usr/bin/env bash
# Squid Local CA を macOS / Linux の信頼ストアに登録する (他端末用)。
#   sudo ./install-ca.sh          登録
#   sudo ./install-ca.sh --remove 解除
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEM="$DIR/squid-ca.pem"
NAME="squid-local-ca"
[[ -f "$PEM" ]] || { echo "squid-ca.pem not found next to this script" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

REMOVE=0
[[ "${1:-}" == "--remove" ]] && REMOVE=1

case "$(uname -s)" in
  Darwin)
    KEYCHAIN=/Library/Keychains/System.keychain
    if [[ $REMOVE -eq 1 ]]; then
      security delete-certificate -c "Squid Local CA" "$KEYCHAIN" && echo "removed from System keychain"
    else
      security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$PEM"
      echo "installed into System keychain (trustRoot)"
    fi
    ;;
  Linux)
    if command -v update-ca-certificates >/dev/null 2>&1; then          # Debian / Ubuntu
      DST="/usr/local/share/ca-certificates/$NAME.crt"
      if [[ $REMOVE -eq 1 ]]; then rm -f "$DST"; update-ca-certificates --fresh >/dev/null; echo "removed $DST"
      else cp "$PEM" "$DST"; update-ca-certificates >/dev/null; echo "installed $DST"; fi
    elif command -v update-ca-trust >/dev/null 2>&1; then               # RHEL / Fedora
      DST="/etc/pki/ca-trust/source/anchors/$NAME.pem"
      if [[ $REMOVE -eq 1 ]]; then rm -f "$DST"; update-ca-trust; echo "removed $DST"
      else cp "$PEM" "$DST"; update-ca-trust; echo "installed $DST"; fi
    elif command -v trust >/dev/null 2>&1; then                         # Arch (p11-kit)
      if [[ $REMOVE -eq 1 ]]; then echo "remove manually: trust list | grep -i squid; trust anchor --remove <pkcs11 uri>"
      else trust anchor --store "$PEM"; echo "installed via p11-kit"; fi
    else
      echo "unsupported distro: install $PEM into your CA store manually" >&2; exit 1
    fi
    echo "Firefox / Chromium (NSS) の場合は別途: certutil -d sql:\$HOME/.pki/nssdb -A -t 'C,,' -n '$NAME' -i '$PEM'"
    ;;
  *) echo "unsupported OS" >&2; exit 1 ;;
esac

echo "Next: set your proxy to the address in README.txt"

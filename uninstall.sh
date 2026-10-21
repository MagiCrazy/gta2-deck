#!/usr/bin/env bash
# gta2-deck — remove GTA 2: Steam shortcut, compat tool mapping and install root.
set -euo pipefail

usage() {
	cat <<EOF
Usage: uninstall.sh [options]

  --dir DIR             install root used at install time (default: ~/Games/gta2)
  --keep-files          only remove the Steam shortcut, keep the game and saves
  --account-id ID       Steam account the shortcut was added to (default: last login)
  -y, --yes             do not ask for confirmation
  -h, --help            show this help
EOF
}

die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOME/Games/gta2"
KEEP=0
YES=0
ACCOUNT_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
	--dir) ROOT="${2:?--dir needs a value}"; shift ;;
	--keep-files) KEEP=1 ;;
	--account-id) ACCOUNT_ARGS=(--account-id "${2:?--account-id needs a value}"); shift ;;
	-y | --yes) YES=1 ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown option: $1" ;;
	esac
	shift
done

ROOT="$(realpath -m "$ROOT")"
STEAMPY=(python3 -I "$SCRIPT_DIR/lib/steam.py" "${ACCOUNT_ARGS[@]}")

pgrep -x steam >/dev/null && die "close Steam first (it rewrites its library files on exit)"

if [ "$YES" = 0 ]; then
	what="the Steam shortcut"
	[ "$KEEP" = 0 ] && what="$what and $ROOT (game, Proton prefix and saves)"
	read -r -p "Remove $what? [y/N] " answer
	case "$answer" in y | Y | yes) ;; *) die "cancelled" ;; esac
fi

appid="$("${STEAMPY[@]}" remove-shortcut --exe "$ROOT/game/gta2.exe")"
if [ -n "$appid" ]; then
	"${STEAMPY[@]}" unset-compat --appid "$appid"
	"${STEAMPY[@]}" unset-artwork --appid "$appid"
	log "Removed the Steam shortcut"
else
	log "No Steam shortcut found for $ROOT/game/gta2.exe"
fi

if [ "$KEEP" = 0 ] && [ -d "$ROOT" ]; then
	# Guard against a wrong --dir: only delete something that looks like our layout.
	[ -f "$ROOT/game/gta2.exe" ] && [ -d "$ROOT/prefix" ] \
		|| die "$ROOT does not look like a gta2-deck install (no game/gta2.exe + prefix/), not deleting it"
	rm -rf -- "$ROOT"
	log "Removed $ROOT"
fi

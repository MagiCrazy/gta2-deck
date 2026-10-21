#!/usr/bin/env bash
# Install and smoke-test GTA 2 with every installed Proton build.
#
# Run on the Deck (Desktop or Game Mode, Steam may stay open: nothing touches
# the Steam library). Each case installs into its own throwaway root, then
# starts the game in a headless gamescope (same display stack as Game Mode)
# and checks that it keeps running with the expected plugins loaded.
#
#   tests/matrix.sh --installer ~/GTA2INSTALLER.exe
#   tests/matrix.sh --installer ~/GTA2INSTALLER.exe --tools "proton_10 proton_11" --variants frontend
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$HOME/gta2-deck-matrix"
INSTALLER=""
TOOLS=""
VARIANTS="frontend vanilla"
RUN_SECONDS=20
KEEP=0

usage() {
	cat <<EOF
Usage: tests/matrix.sh --installer FILE [options]

  --installer FILE   local GTA2INSTALLER.exe (avoids downloading it per case)
  --tools "A B"      internal tool names to test (default: every installed one)
  --variants "..."   frontend and/or vanilla (default: both)
  --work DIR         scratch directory (default: ~/gta2-deck-matrix)
  --seconds N        how long the game must survive (default: 20)
  --keep             keep each case's install root after the run
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--installer) INSTALLER="$(realpath "$2")"; shift ;;
	--tools) TOOLS="$2"; shift ;;
	--variants) VARIANTS="$2"; shift ;;
	--work) WORK="$2"; shift ;;
	--seconds) RUN_SECONDS="$2"; shift ;;
	--keep) KEEP=1 ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
	shift
done
[ -f "$INSTALLER" ] || { usage >&2; exit 2; }

STEAMPY=(python3 -I "$REPO_DIR/lib/steam.py")
STEAM_ROOT="$("${STEAMPY[@]}" info | sed -n 's/^root=//p')"
[ -n "$TOOLS" ] || TOOLS="$("${STEAMPY[@]}" list-tools | cut -f1 | tr '\n' ' ')"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

RUN="$WORK/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
RESULTS="$RUN/results.tsv"
printf 'tool\tvariant\tinstall\tfiles\tstarts\tplugins\tresult\n' >"$RESULTS"

# game_pid ROOT -> pid of the gta2.exe running from ROOT/game
game_pid() {
	local pid
	for pid in $(pgrep -x gta2.exe); do
		[ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" = "$1/game" ] && { echo "$pid"; return; }
	done
}

stop_case() { # ROOT PROTON_DIR LAUNCHER_PID
	local server
	for server in "$2/files/bin/wineserver" "$2/dist/bin/wineserver"; do
		[ -x "$server" ] && WINEPREFIX="$1/prefix/pfx" "$server" -k 2>/dev/null
	done
	kill "$3" 2>/dev/null
	wait "$3" 2>/dev/null
}

for tool in $TOOLS; do
	IFS=$'\t' read -r _ label proton_dir < <("${STEAMPY[@]}" find-tool "$tool") || {
		printf '%s\t-\t-\t-\t-\t-\tNOT INSTALLED\n' "$tool" >>"$RESULTS"
		continue
	}
	for variant in $VARIANTS; do
		case_id="${tool}-${variant}"
		root="$RUN/$case_id"
		log="$RUN/$case_id"
		install=FAIL files=- starts=- plugins=- result=FAIL
		printf '\n=== %s (%s), %s\n' "$label" "$tool" "$variant"

		args=(--dir "$root" --no-steam -y --lang fr --proton "$tool" --installer "$INSTALLER")
		[ "$variant" = vanilla ] && args+=(--vanilla)
		if bash "$REPO_DIR/install.sh" "${args[@]}" >"$log.install.log" 2>&1; then
			install=ok
			missing=""
			expected=(game/gta2.exe game/dinput.dll game/data/f.gxt game/data/g.gxt game/data/i.gxt game/scripts/GInputII.asi)
			[ "$variant" = frontend ] && expected+=(game/scripts/FrontendFixII.asi game/scripts/GTA2.WidescreenFix.asi game/ufiles/settings.xml)
			for f in "${expected[@]}"; do [ -f "$root/$f" ] || missing="$missing $f"; done
			grep -q '"UseXVidMode"="N"' "$root/prefix/pfx/user.reg" || missing="$missing UseXVidMode"
			if [ -z "$missing" ]; then files=ok; else files="missing:$missing"; fi

			(cd "$root/game" && exec gamescope --backend headless -W 1280 -H 800 -- \
				env STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" STEAM_COMPAT_DATA_PATH="$root/prefix" \
				"$proton_dir/proton" run gta2.exe) >"$log.launch.log" 2>&1 &
			launcher=$!
			pid=""
			for _ in $(seq 1 40); do pid="$(game_pid "$root")"; [ -n "$pid" ] && break; sleep 1; done
			if [ -n "$pid" ]; then
				sleep "$RUN_SECONDS"
				if kill -0 "$pid" 2>/dev/null; then
					starts=ok
					want=(dinput.dll GInputII.asi)
					[ "$variant" = frontend ] && want+=(FrontendFixII.asi GTA2.WidescreenFix.asi)
					absent=""
					for m in "${want[@]}"; do grep -qi "/$m\$" "/proc/$pid/maps" || absent="$absent $m"; done
					if [ -z "$absent" ]; then plugins=ok; else plugins="missing:$absent"; fi
				else
					starts="exited"
				fi
			else
				starts="never started"
			fi
			grep -q 'Assertion' "$log.launch.log" && starts="$starts (assertion)"
			stop_case "$root" "$proton_dir" "$launcher"
			[ "$files" = ok ] && [ "$starts" = ok ] && [ "$plugins" = ok ] && result=PASS
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$tool" "$variant" "$install" "$files" "$starts" "$plugins" "$result" >>"$RESULTS"
		echo "$result"
		# Install roots are ~400 MB each: drop them unless asked to keep them.
		[ "$KEEP" = 1 ] || rm -rf -- "${root:?}"
	done
done

printf '\nLogs: %s\n\n' "$RUN"
column -t -s $'\t' "$RESULTS"
! grep -q $'\tFAIL$' "$RESULTS"

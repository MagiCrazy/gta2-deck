#!/usr/bin/env bash
# gta2-deck — install GTA 2 (Rockstar freeware, 9.6) on a Steam Deck in one go.
#
#   curl -fsSL https://raw.githubusercontent.com/MagiCrazy/gta2-deck/main/install.sh | bash
#
# Run it from Desktop Mode. Without arguments and with a display, it asks its
# questions through zenity; otherwise it uses the options below.
set -euo pipefail

REPO="MagiCrazy/gta2-deck"
VERSION="v1.0"

# Proton builds covered by tests/matrix.sh, in order of preference (internal
# tool names). Others (Proton 9 and older, GE-Proton...) work only through --proton and
# are reported as untested.
PROTON_SUPPORTED="proton_10 proton_11 proton_experimental proton_hotfix"
SHORTCUT_NAME="Grand Theft Auto 2"

# Pinned downloads: name|sha256|url [url...]
INSTALLER="GTA2INSTALLER.exe|0cd380498dfbe62448d56aaddd3e36593cfda324aa8a3972b06a02d015b083a0|https://github.com/${REPO}/releases/download/${VERSION}/GTA2INSTALLER.exe https://archive.org/download/gta2_rockstar-classics/GTA2INSTALLER.exe"
ASI_LOADER="Ultimate-ASI-Loader-v4.68.zip|7517c7d5bd8c475f18e6545b7998df379eed6e2e0a19fcd2139669152f9bcddb|https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v4.68/Ultimate-ASI-Loader.zip"
FRONTEND_FIX="FrontendFixII-v0.100.zip|ac959e5171696ccf7f6adef25054e68a0cc0a0005648390423258b1d808b7a55|https://github.com/gennariarmando/gta2-frontend-fix/releases/download/v0.100/FrontendFixII.zip"
WIDESCREEN_FIX="GTA2.WidescreenFix-20240827.zip|c64f9ba71f091265ea6ca59e3bba112d45667d6b16b6246aa2919ec243481cc7|https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gta2/GTA2.WidescreenFix.zip https://github.com/${REPO}/releases/download/${VERSION}/GTA2.WidescreenFix.zip"

usage() {
	cat <<EOF
Usage: install.sh [options]

  --dir DIR             install root (default: ~/Games/gta2)
                        the game goes to DIR/game, the Proton prefix to DIR/prefix
  --lang LANG           en, fr, de, it or es (default: en)
  --proton NAME         Proton build to use, e.g. "Proton 11.0" or proton_11
                        (default: Proton 10.0 if installed)
  --vanilla             skip Frontend Fix + Widescreen Fix (original menus,
                        settings only through gta2 manager.exe)
  --installer FILE      use a local GTA2INSTALLER.exe instead of downloading it
  --interactive         show the InstallShield wizard instead of a silent install
  --no-steam            do not create the Steam shortcut
  --account-id ID       Steam account to add the shortcut to (default: last login)
  -y, --yes             do not ask questions (no zenity dialogs)
  -h, --help            show this help
EOF
}

# --- output -------------------------------------------------------------------

GUI=0
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
	if [ "$GUI" = 1 ]; then zenity --error --title="GTA 2 installer" --text="$*" 2>/dev/null || true; fi
	exit 1
}

# --- locate the repository files ----------------------------------------------
# When piped from curl there is no checkout: fetch the tagged sources and re-run.

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/lib/steam.py" ]; then
	tmp="$(mktemp -d)"
	log "Downloading gta2-deck ${VERSION}"
	curl -fsSL "https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz" | tar -xz -C "$tmp" --strip-components=1 \
		|| die "cannot download https://github.com/${REPO}"
	# stdin is the piped script: give the real terminal back when there is one.
	if [ -r /dev/tty ] && (: </dev/tty) 2>/dev/null; then
		exec bash "$tmp/install.sh" "$@" </dev/tty
	fi
	exec bash "$tmp/install.sh" "$@" </dev/null
fi

# --- options ------------------------------------------------------------------

ROOT="$HOME/Games/gta2"
LANG_CODE=""
PROTON_WANTED=""
VANILLA=0
LOCAL_INSTALLER=""
INTERACTIVE=0
STEAM=1
ACCOUNT_ARGS=()
ASK=1
[ $# -gt 0 ] && ASK=0

while [ $# -gt 0 ]; do
	case "$1" in
	--dir) ROOT="${2:?--dir needs a value}"; shift ;;
	--lang) LANG_CODE="${2:?--lang needs a value}"; shift ;;
	--proton) PROTON_WANTED="${2:?--proton needs a value}"; shift ;;
	--vanilla) VANILLA=1 ;;
	--installer) LOCAL_INSTALLER="${2:?--installer needs a value}"; shift ;;
	--interactive) INTERACTIVE=1 ;;
	--no-steam) STEAM=0 ;;
	--account-id) ACCOUNT_ARGS=(--account-id "${2:?--account-id needs a value}"); shift ;;
	-y | --yes) ASK=0 ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown option: $1" ;;
	esac
	shift
done

if [ "$ASK" = 1 ] && command -v zenity >/dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
	GUI=1
	LANG_CODE="$(zenity --list --radiolist --title="GTA 2 installer" --text="Game language" \
		--column="" --column="Code" --column="Language" --hide-column=2 --height=300 \
		TRUE en English FALSE fr Français FALSE de Deutsch FALSE it Italiano FALSE es Español)" \
		|| die "installation cancelled"
	zenity --question --title="GTA 2 installer" --width=420 \
		--text="Install Frontend Fix + Widescreen Fix?\n\nRecommended: in-game settings menu usable with the controller, PlayStation-style menus, fixes the black main menu after a game.\n\nChoose No for the untouched original menus." \
		|| VANILLA=1
fi

case "${LANG_CODE:-en}" in
en) GXT=e ;; fr) GXT=f ;; de) GXT=g ;; it) GXT=i ;; es) GXT=s ;;
*) die "unsupported language: $LANG_CODE (en, fr, de, it, es)" ;;
esac

ROOT="$(realpath -m "$ROOT")"
GAME="$ROOT/game"
PREFIX="$ROOT/prefix"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/gta2-deck"
STEAMPY=(python3 -I "$SCRIPT_DIR/lib/steam.py" "${ACCOUNT_ARGS[@]}")

for cmd in python3 curl unzip sha256sum; do
	command -v "$cmd" >/dev/null || die "missing command: $cmd"
done

# --- helpers ------------------------------------------------------------------

# fetch "name|sha256|url [url...]" -> prints the cached file path
fetch() {
	local name sha urls file url
	IFS='|' read -r name sha urls <<<"$1"
	file="$CACHE/$name"
	mkdir -p "$CACHE"
	if [ -f "$file" ] && echo "$sha  $file" | sha256sum -c --status; then
		echo "$file"
		return
	fi
	for url in $urls; do
		log "Downloading $url" >&2
		if curl -fL --retry 2 --connect-timeout 20 -o "$file.part" "$url" \
			&& echo "$sha  $file.part" | sha256sum -c --status; then
			mv "$file.part" "$file"
			echo "$file"
			return
		fi
		warn "download failed or checksum mismatch: $url"
	done
	rm -f "$file.part"
	die "could not get $name with the expected checksum"
}

# Linux path -> Wine path on the Z: drive
winpath() { printf 'Z:%s' "${1//\//\\}"; }

proton() {
	STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" STEAM_COMPAT_DATA_PATH="$PREFIX" \
		"$PROTON_DIR/proton" run "$@"
}

wineserver_bin() {
	local server
	for server in "$PROTON_DIR/files/bin/wineserver" "$PROTON_DIR/dist/bin/wineserver"; do
		[ -x "$server" ] && { echo "$server"; return; }
	done
}

# wait_wine [SECONDS]: wait for the prefix to go idle, kill it after the timeout.
wait_wine() {
	local server
	server="$(wineserver_bin)"
	if [ -z "$server" ]; then
		sleep 10 # unknown layout: give wine time to finish
		return
	fi
	WINEPREFIX="$PREFIX/pfx" timeout "${1:-120}" "$server" -w \
		|| WINEPREFIX="$PREFIX/pfx" "$server" -k || true
}

steam_running() { pgrep -x steam >/dev/null; }

# --- Proton -------------------------------------------------------------------

STEAM_ROOT="$("${STEAMPY[@]}" info | sed -n 's/^root=//p')"
ALL_TOOLS="$("${STEAMPY[@]}" list-tools)"
TOOLS="$(awk -F'\t' -v keep=" $PROTON_SUPPORTED " 'index(keep, " " $1 " ")' <<<"$ALL_TOOLS")"

if [ -z "$PROTON_WANTED" ]; then
	[ -n "$TOOLS" ] || die "no supported Proton build found. In Steam, search the library for \"Proton 10.0\" and install it, then run this script again."
	for name in $PROTON_SUPPORTED; do
		if cut -f1 <<<"$TOOLS" | grep -qx "$name"; then PROTON_WANTED="$name"; break; fi
	done
	if [ "$GUI" = 1 ] && [ "$(wc -l <<<"$TOOLS")" -gt 1 ]; then
		choices=()
		while IFS=$'\t' read -r name display _; do
			choices+=("$([ "$name" = "$PROTON_WANTED" ] && echo TRUE || echo FALSE)" "$name" "$display")
		done <<<"$TOOLS"
		PROTON_WANTED="$(zenity --list --radiolist --title="GTA 2 installer" --text="Proton version (Proton 10.0 is the tested one)" \
			--column="" --column="Tool" --column="Proton" --hide-column=2 --height=350 "${choices[@]}")" \
			|| die "installation cancelled"
	fi
fi
IFS=$'\t' read -r PROTON_TOOL PROTON_LABEL PROTON_DIR < <("${STEAMPY[@]}" find-tool "$PROTON_WANTED") \
	|| die "Proton build not found: $PROTON_WANTED. Installed: $(cut -f2 <<<"$ALL_TOOLS" | paste -sd, -)"
case " $PROTON_SUPPORTED " in
*" $PROTON_TOOL "*) ;;
*) warn "$PROTON_LABEL is not among the tested Proton builds, continuing anyway" ;;
esac

log "Install root: $ROOT"
log "Language: ${LANG_CODE:-en} ($GXT.gxt), $([ "$VANILLA" = 1 ] && echo vanilla || echo 'Frontend Fix + Widescreen Fix')"
log "Using $PROTON_LABEL ($PROTON_TOOL)"
mkdir -p "$GAME" "$PREFIX"

# --- game ---------------------------------------------------------------------

if [ -f "$GAME/gta2.exe" ]; then
	log "Game already installed in $GAME, skipping the Rockstar installer"
else
	if [ -n "$LOCAL_INSTALLER" ]; then
		[ -f "$LOCAL_INSTALLER" ] || die "installer not found: $LOCAL_INSTALLER"
		setup_exe="$(realpath "$LOCAL_INSTALLER")"
	else
		setup_exe="$(fetch "$INSTALLER")"
	fi
	work="$(mktemp -d)"
	# Unpack the InstallShield package ourselves: the launcher stub of
	# GTA2INSTALLER.exe randomly hangs under Proton 11 / Experimental.
	python3 -I "$SCRIPT_DIR/lib/unpack_installer.py" "$setup_exe" "$work/disk1" >/dev/null \
		|| die "cannot unpack $setup_exe"
	if [ "$INTERACTIVE" = 1 ]; then
		log "Starting the InstallShield wizard; install to $(winpath "$GAME")"
		(cd "$work/disk1" && proton setup.exe) >"$work/proton.log" 2>&1 &
		launcher=$!
		# Done once the installer registered the game and its windows are gone
		# ("proton run" itself may never return on newer builds).
		while kill -0 "$launcher" 2>/dev/null; do
			if grep -q 'Rockstar Games\\\\GTA2\]' "$PREFIX/pfx/system.reg" 2>/dev/null \
				&& ! pgrep -f 'GTA2INSTALLER|[Ss]etup\.exe' >/dev/null; then
				break
			fi
			sleep 2
		done
		wait_wine 60
		kill "$launcher" 2>/dev/null || true
		if [ ! -f "$GAME/gta2.exe" ]; then
			# The user picked another folder: follow the path the installer registered.
			reg_path="$(sed -n 's/^"path"="\(.*\)"\r\?$/\1/p' "$PREFIX/pfx/system.reg" | tail -1 | sed 's/\\\\/\\/g')"
			case "$reg_path" in
			Z:*) GAME="$(printf '%s' "${reg_path#Z:}" | tr '\\' '/')" ;;
			C:*) GAME="$PREFIX/pfx/drive_c$(printf '%s' "${reg_path#C:}" | tr '\\' '/')" ;;
			esac
		fi
	else
		log "Installing GTA 2 silently (this takes a minute)"
		sed "s|@INSTALL_DIR@|$(winpath "$GAME" | sed 's/\\/\\\\/g')|" "$SCRIPT_DIR/lib/setup.iss" >"$work/setup.iss"
		# Newer Proton builds may keep "proton run" alive after the installer is
		# done: watch InstallShield's result log instead.
		(cd "$work/disk1" && proton setup.exe /s /f1"$(winpath "$work/setup.iss")" /f2"$(winpath "$work/setup.log")") \
			>"$work/proton.log" 2>&1 &
		launcher=$!
		for _ in $(seq 1 900); do
			grep -q '^ResultCode=' "$work/setup.log" 2>/dev/null && break
			kill -0 "$launcher" 2>/dev/null || break
			sleep 1
		done
		wait_wine 60
		kill "$launcher" 2>/dev/null || true
		wait "$launcher" 2>/dev/null || true
		grep -q '^ResultCode=0' "$work/setup.log" 2>/dev/null \
			|| die "the Rockstar installer failed or timed out (logs in $work)"
	fi
	[ -f "$GAME/gta2.exe" ] || die "gta2.exe not found after installation"
	rm -rf "$work"
fi

# --- registry -----------------------------------------------------------------
# UseXVidMode=N: 9.6 crashes in winex11's XVidMode code under Xwayland/gamescope.

log "Configuring the Proton prefix"
reg="$(mktemp --suffix=.reg)"
cat >"$reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
"dinput"="native,builtin"

[HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver]
"UseXVidMode"="N"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\DMA Design Ltd\\GTA2\\Screen]
"start_mode"=dword:00000000
"full_width"=dword:00000500
"full_height"=dword:00000320
"window_width"=dword:00000500
"window_height"=dword:00000320

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\DMA Design Ltd\\GTA2\\Option]
"Language"="$GXT"
EOF
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" STEAM_COMPAT_DATA_PATH="$PREFIX" \
	timeout 180 "$PROTON_DIR/proton" run regedit /S "$(winpath "$reg")" >/dev/null 2>&1 || true
wait_wine 60
rm -f "$reg"
grep -q '"UseXVidMode"="N"' "$PREFIX/pfx/user.reg" 2>/dev/null \
	|| die "could not write the Proton registry settings (prefix: $PREFIX)"

# --- mods ---------------------------------------------------------------------

log "Installing languages, ASI loader and GInput"
cp "$SCRIPT_DIR"/payload/data/*.gxt "$GAME/data/"
mkdir -p "$GAME/scripts"
cp -r "$SCRIPT_DIR"/payload/scripts/. "$GAME/scripts/"
unzip -p "$(fetch "$ASI_LOADER")" dinput8.dll >"$GAME/dinput.dll"

if [ "$VANILLA" = 1 ]; then
	rm -f "$GAME"/scripts/FrontendFixII.* "$GAME"/scripts/GTA2.WidescreenFix.*
else
	log "Installing Frontend Fix and Widescreen Fix"
	ffix="$(fetch "$FRONTEND_FIX")"
	unzip -o -q "$ffix" 'data/*' -d "$GAME"
	unzip -o -q -j "$ffix" FrontendFixII.asi FrontendFixII.ini -d "$GAME/scripts"
	unzip -o -q -j "$(fetch "$WIDESCREEN_FIX")" scripts/GTA2.WidescreenFix.asi -d "$GAME/scripts"
	cp "$SCRIPT_DIR/lib/GTA2.WidescreenFix.ini" "$GAME/scripts/"

	# Frontend Fix reads its settings from ufiles/settings.xml, not the registry.
	# "borderless windowed" is required: "windowed" shows a black screen in gamescope.
	settings="$GAME/ufiles/settings.xml"
	mkdir -p "$GAME/ufiles"
	if [ -f "$settings" ]; then
		sed -i "s|<Language value=\"[^\"]*\" />|<Language value=\"$GXT\" />|" "$settings"
	else
		cat >"$settings" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Settings>
	<version value="1" />
	<controls>
		<Forward value="17" />
		<Backward value="31" />
		<Left value="30" />
		<Right value="32" />
		<Attack value="238" />
		<EnterExit value="33" />
		<HandbrakeJump value="57" />
		<PreviousWeapon value="242" />
		<NextWeapon value="241" />
		<Special value="15" />
		<Special2 value="29" />
	</controls>
	<audio>
		<SfxVolume value="87" />
		<MusicVolume value="87" />
	</audio>
	<display>
		<ScreenWidth value="1280" />
		<ScreenHeight value="800" />
		<ScreenType value="borderless windowed" />
	</display>
	<game>
		<LightingType value="dusk" />
		<Language value="$GXT" />
		<MouseControlledHeading value="false" />
	</game>
</Settings>
EOF
	fi
fi

# --- Steam shortcut -----------------------------------------------------------

if [ "$STEAM" = 1 ]; then
	restart_steam=0
	if steam_running; then
		if [ "$GUI" = 1 ]; then
			zenity --question --title="GTA 2 installer" --width=420 \
				--text="Steam has to be closed to add the game to your library.\n\nClose Steam now? It will be restarted afterwards." \
				|| die "Steam is still running: close it and run the installer again, or use --no-steam"
		else
			log "Closing Steam to edit the library (it will be restarted)"
		fi
		steam -shutdown >/dev/null 2>&1 || true
		for _ in $(seq 1 60); do steam_running || break; sleep 1; done
		steam_running && die "Steam did not close; close it manually and run the installer again"
		restart_steam=1
	fi

	log "Adding \"$SHORTCUT_NAME\" to Steam"
	art="$SCRIPT_DIR/artwork"
	icon="$GAME/rockstar.ico"
	if [ -f "$art/icon.png" ]; then
		cp "$art/icon.png" "$ROOT/icon.png"
		icon="$ROOT/icon.png"
	fi
	appid="$("${STEAMPY[@]}" add-shortcut \
		--name "$SHORTCUT_NAME" \
		--exe "$GAME/gta2.exe" \
		--start-dir "$GAME" \
		--icon "$icon" \
		--launch-options "STEAM_COMPAT_DATA_PATH=\"$PREFIX\" %command%")"
	"${STEAMPY[@]}" set-compat --appid "$appid" --tool "$PROTON_TOOL"
	artwork_args=()
	for kind in portrait landscape hero logo; do
		for f in "$art/$kind".png "$art/$kind".jpg; do
			[ -f "$f" ] && artwork_args+=("--$kind" "$f") && break
		done
	done
	[ ${#artwork_args[@]} -gt 0 ] && "${STEAMPY[@]}" set-artwork --appid "$appid" "${artwork_args[@]}"

	if [ "$restart_steam" = 1 ]; then
		log "Restarting Steam"
		setsid steam >/dev/null 2>&1 </dev/null &
	fi
fi

log "Done. GTA 2 is installed in $GAME"
[ "$STEAM" = 1 ] && log "Launch \"$SHORTCUT_NAME\" from your Steam library (Game Mode works best)."
if [ "$GUI" = 1 ]; then
	zenity --info --title="GTA 2 installer" --width=380 \
		--text="GTA 2 is installed.\n\nLaunch \"$SHORTCUT_NAME\" from your Steam library." 2>/dev/null || true
fi

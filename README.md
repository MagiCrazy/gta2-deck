# gta2-deck

Install **Grand Theft Auto 2** on a Steam Deck in one command: the official
Rockstar freeware release (9.6), playable with the controller, in your
language, launched from Steam like any other game.

## Quick start

Takes about five minutes. You need an internet connection.

1. **Install Proton 11.0** (once). In Game Mode, open your **Library**, search
   for `Proton 11.0` and install it. Skip this step if it is already installed.
2. **Switch to Desktop Mode.** Press the **Steam** button → **Power** →
   **Switch to Desktop**.
3. **Open a terminal.** Click the application launcher (bottom-left corner) →
   **System** → **Konsole**.
4. **Run the installer.** Type or paste this line in Konsole, then press
   **Enter**:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/MagiCrazy/gta2-deck/main/install.sh | bash
   ```

   No keyboard? Press **Steam + X** to show the on-screen keyboard, or open
   this page in Firefox, copy the line, and paste it in Konsole with
   **Ctrl + Shift + V** (right-click → *Paste* also works).
5. **Answer the questions.** Pick your language, keep *Frontend Fix* (answer
   **Yes**), choose whether you want the GTA 3-style radar (a minimap that is
   not in the original game), keep the proposed Proton version. When asked to close Steam,
   answer **Yes**: it is restarted at the end. Installation takes about a
   minute; a window tells you when it is done.
6. **Go back to Game Mode.** Double-click **Return to Gaming Mode** on the
   desktop.
7. **Play.** *Grand Theft Auto 2* is in your Library (also under the
   **Non-Steam** tab). Press **Play**.

Controls are listed [below](#controls-ginput-default-control-set). Settings
(language, volume, display) are in the game's **Options** menu. To remove the
game, see [Uninstall](#uninstall).

Everything else in this README is for the curious and for troubleshooting.

## What it does

1. Downloads the official Rockstar freeware installer (`GTA2INSTALLER.exe`,
   checksum-verified), unpacks the InstallShield package it embeds and runs
   it **silently under Proton** (its launcher stub randomly hangs under
   Proton 11 / Experimental, so it is bypassed).
2. Adds the French, German and Italian texts missing from the freeware release
   (without them the game crashes when you pick those languages in the menu).
3. Installs controller support: [Ultimate ASI Loader] + GInput (PlayStation
   control scheme, rumble).
4. Optionally (recommended) installs [Frontend Fix] + [Widescreen Fix]:
   in-game settings menu instead of the external `gta2 manager.exe`,
   PlayStation-style menus and loading screens, and a fix for the black main
   menu after quitting a game.
   Optionally adds the [GTA2 Radar] (GTA 3-style minimap with mission blips),
   keeping the game's own objective arrows.
5. Configures the Proton prefix (1280×800, language, the workarounds below).
6. Creates the Steam shortcut and forces the chosen Proton build (Proton 11.0
   by default). Steam is closed while its library files are edited and
   restarted afterwards.
7. Adds library artwork (capsule, banner, logo, icon) to the shortcut.

Everything goes into one folder (`~/Games/gta2` by default):

```
~/Games/gta2/
├── game/     # GTA 2
└── prefix/   # Proton prefix (Windows registry, saves)
```

No map packs, no gameplay changes: the original game with a controller.

## Requirements

- Steam Deck (or any SteamOS / Linux box with Steam)
- One of the tested Proton builds installed (Steam → Library → search
  "Proton 11.0" → Install):

  | Proton | Status |
  |---|---|
  | 11.0 | default, tested in Game Mode and by `tests/matrix.sh` |
  | 10.0 | tested in Game Mode and by `tests/matrix.sh` |
  | Experimental, Hotfix | should work (same base as 11.0), not re-tested for v1.0 |
  | 9.0 | not supported: the Rockstar installer never completes under it |
  | others (8.0, GE-Proton...) | not tested; usable with `--proton`, contributions welcome |

- ~450 MB of free space

## Options

```bash
curl -fsSL https://raw.githubusercontent.com/MagiCrazy/gta2-deck/main/install.sh | bash -s -- --lang fr
```

| Option | Effect |
|---|---|
| `--dir DIR` | install root (default `~/Games/gta2`) |
| `--lang LANG` | `en`, `fr`, `de`, `it` or `es` |
| `--proton NAME` | Proton build, e.g. `"Proton 11.0"` or `proton_11` |
| `--vanilla` | skip Frontend Fix + Widescreen Fix (original menus) |
| `--radar` | add the GTA 3-style radar (not with `--vanilla`) |
| `--installer FILE` | use your own `GTA2INSTALLER.exe` |
| `--interactive` | show the InstallShield wizard instead of a silent install |
| `--no-steam` | do not touch the Steam library |
| `--account-id ID` | Steam account to add the shortcut to (default: last login) |
| `-y` | no questions |

Passing any option disables the zenity dialogs. Running the script again is
safe: an existing installation is kept and the shortcut is updated, not
duplicated.

## Controls (GInput, default control set)

| Action | Button |
|---|---|
| Forward / Backward | A / X |
| Turn | D-pad left / right |
| Attack | R2 |
| Handbrake / Jump | R1 |
| Enter / exit vehicle | Y |
| Special | B |
| Previous / next weapon | L2 / L1 |
| Pause | Start |

GTA 2 uses "tank" controls on every platform, PlayStation included: you rotate
the character or car and move forward in the direction it faces. Other control
sets are described in `game/scripts/docs/GAME_CONTROLS.txt` and selected in
`game/scripts/GInputII.ini`.

## Technical notes

- `UseXVidMode=N` (`HKCU\Software\Wine\X11 Driver`): without it, 9.6 crashes on
  start in Wine's XVidMode code, both in Desktop Mode and in gamescope.
- `dinput=native,builtin` DLL override: loads the ASI loader (`dinput.dll`).
- `do_play_movie=1` (`HKLM\Software\Wow6432Node\DMA Design Ltd\GTA2\Screen`):
  the intro movie is off unless `gta2 manager.exe` wrote this value.
- Frontend Fix stores its settings in `game/ufiles/settings.xml`. The screen
  mode must be **borderless windowed**: plain windowed mode renders a black
  screen in gamescope.
- With Frontend Fix, screen mode and language are **not** written to the
  registry: Frontend Fix deletes those values on its first start, and while
  they exist that first start opens an oversized, cropped window.
- Frontend Fix unconditionally skips the intro movie (it patches the start-up
  state at `0x4D145C` in `gta2.exe`). The installer patches one byte of the
  downloaded `FrontendFixII.asi` so that it writes the original value back;
  the bytes are checked first and the plugin is left untouched if they differ.
- Radar v0.100 always hides the game's objective arrows (it NOPs 11 bytes at
  `0x4CA4D2`). The installer patches one byte of the downloaded
  `GTA2Radar.asi` so that it NOPs 0 bytes instead; same checks as above.
- Widescreen Fix renders at the Deck's native 1280×800 (`ResX`/`ResY` in
  `game/scripts/GTA2.WidescreenFix.ini`); intro and end credits are kept
  (`SkipMovie = 0`, `SkipCredits = 0`).
- The Steam shortcut points Proton to `prefix/` through its launch options
  (`STEAM_COMPAT_DATA_PATH=... %command%`), so removing the shortcut never
  deletes the game or the saves.

## Known limitations

- **Play from Game Mode.** Launched from Steam in Desktop Mode, the game runs,
  but Steam's Big Picture screen can stay black after you quit (press **B** to
  abort).
- The intro movie plays at its original size, in the middle of the screen.
- Rumble is very weak (GInput only has an on/off switch).

## Tests

`tests/matrix.sh` installs the game with every installed Proton build (with
and without Frontend Fix) into throwaway folders, starts it in a headless
gamescope and checks that it keeps running with its plugins loaded. It never
touches the Steam library.

```bash
tests/matrix.sh --installer ~/GTA2INSTALLER.exe
```

## Uninstall

In Desktop Mode, open Konsole and run:

```bash
curl -fsSL https://raw.githubusercontent.com/MagiCrazy/gta2-deck/main/uninstall.sh | bash
```

Answer **y** to confirm. It removes the Steam shortcut, its artwork and
`~/Games/gta2` (game, Proton prefix **and saves**), closing and restarting
Steam if needed. Add `-s -- --keep-files` after `bash` to only remove the
shortcut and keep the game folder.

## Credits

- **Rockstar Games / Take-Two Interactive** — Grand Theft Auto 2, released as
  freeware in 2004.
- **ThirteenAG** — [Ultimate ASI Loader] and [Widescreen Fix] (MIT).
- **gennariarmando** — [Frontend Fix] and [GTA2 Radar].
- **GInput for GTA2** — controller plugin, from the
  [GTAForums topic](https://gtaforums.com/topic/988318-ginput-for-gta2/).
- **btpf** — [GTA2 Deck Edition], the mod pack that showed this setup works on
  the Deck.
- Library artwork (`artwork/`), from [SteamGridDB](https://www.steamgriddb.com):
  - capsules (`portrait.png`, `landscape.png`) by
    [nBurbidge](https://www.steamgriddb.com/profile/76561198024748672)
  - banner (`hero.jpg`) by
    [Jib](https://www.steamgriddb.com/profile/76561198394798289)
  - logo (`logo.png`) by
    [CluckenDip](https://www.steamgriddb.com/profile/76561198120642113)
  - icon (`icon.png`, extracted from the original `.ico`) by
    [Pi0h1](https://www.steamgriddb.com/profile/76561198073304281)

## Disclaimer

GTA 2 and its files belong to Take-Two Interactive. The freeware installer is
attached to this repository's release and the missing language files (from the
1999 retail CD) are included for convenience, so the game can be installed in
one step. This project is not affiliated with Rockstar Games or Take-Two
Interactive. The scripts themselves are MIT-licensed (see `LICENSE`).

[Ultimate ASI Loader]: https://github.com/ThirteenAG/Ultimate-ASI-Loader
[Widescreen Fix]: https://github.com/ThirteenAG/WidescreenFixesPack
[Frontend Fix]: https://github.com/gennariarmando/gta2-frontend-fix
[GTA2 Radar]: https://github.com/gennariarmando/gta2-radar
[GTA2 Deck Edition]: https://github.com/btpf/GTA2DeckEdition

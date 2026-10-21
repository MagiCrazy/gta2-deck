# gta2-deck

Install **Grand Theft Auto 2** on a Steam Deck in one command: the official
Rockstar freeware release (9.6), playable with the controller, in your
language, launched from Steam like any other game.

```bash
curl -fsSL https://raw.githubusercontent.com/MagiCrazy/gta2-deck/main/install.sh | bash
```

Run it from **Desktop Mode** (Konsole). Without options it asks two questions
(language, Frontend Fix yes/no), installs everything, adds *Grand Theft Auto 2*
to your Steam library and forces Proton. Go back to Game Mode and play.

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
5. Configures the Proton prefix (1280×800, language, the workarounds below).
6. Creates the Steam shortcut and forces the chosen Proton build (Proton 10.0
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
  "Proton 10.0" → Install):

  | Proton | Status |
  |---|---|
  | 10.0 | default, tested |
  | 11.0, Experimental, Hotfix | tested by `tests/matrix.sh` |
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
- Frontend Fix stores its settings in `game/ufiles/settings.xml`. The screen
  mode must be **borderless windowed**: plain windowed mode renders a black
  screen in gamescope.
- The Steam shortcut points Proton to `prefix/` through its launch options
  (`STEAM_COMPAT_DATA_PATH=... %command%`), so removing the shortcut never
  deletes the game or the saves.

## Known limitations

- Rumble is very weak (GInput only has an on/off switch).
- The GTA 3-style radar mod is not included yet.

## Tests

`tests/matrix.sh` installs the game with every installed Proton build (with
and without Frontend Fix) into throwaway folders, starts it in a headless
gamescope and checks that it keeps running with its plugins loaded. It never
touches the Steam library.

```bash
tests/matrix.sh --installer ~/GTA2INSTALLER.exe
```

## Uninstall

From a clone of this repository, with Steam closed:

```bash
./uninstall.sh            # shortcut + ~/Games/gta2
./uninstall.sh --keep-files
```

## Credits

- **Rockstar Games / Take-Two Interactive** — Grand Theft Auto 2, released as
  freeware in 2004.
- **ThirteenAG** — [Ultimate ASI Loader] and [Widescreen Fix] (MIT).
- **gennariarmando** — [Frontend Fix].
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
[GTA2 Deck Edition]: https://github.com/btpf/GTA2DeckEdition

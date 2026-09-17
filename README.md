# Fix-CraftFromContainers

A PowerShell script that fixes **CraftFromContainers** ([ContainerCrafting1point0fork](https://thunderstore.io/c/valheim/p/TeamNibake/ContainerCrafting1point0fork/) by TeamNibake) on **Valheim 1.0**, where crafting from nearby chests no longer works for upgradable gear.

## Symptoms

With the materials in a chest next to you:

- The Craft button stays greyed out with **"Missing requirement"** for anything upgradable — weapons, tools, armor, shields (flint axe, club, bow, leather armor...).
- The required materials are nonetheless shown in **yellow**, with the amounts held in the chests.
- Arrows, torches, food and other non-upgradable recipes craft fine.
- Putting the same materials in your own inventory makes the recipe craftable.

## Cause

Valheim 1.0 added a hidden "upgrader" ingredient (`m_upgraderResource = true`, e.g. `$item_upgrader_tier1`) to every upgradable item. The game only takes it into account at an upgrader station and skips it everywhere else. The mod does not: it counts it as a normal material, finds 0 of the 1 needed and refuses the craft.

## What the script does

It rewrites three methods inside the mod's own DLL so they follow the same rule as the game — at a normal station, ignore upgrader ingredients; at an upgrader station, use only those:

| Method | Role |
| --- | --- |
| `HaveRequirementItems_Patch.Postfix` | may I craft this? |
| `ConsumeResources_Patch.Prefix` | take the materials out of the chests |
| `BepInExPlugin.PullResources` | Ctrl key: pull materials into your inventory |

Nothing in the Valheim installation is touched, and the original DLL is backed up next to itself as `CraftFromContainers.dll.backup-<date>` before anything is written.

## Requirements

- Windows, Valheim 1.0 with BepInEx
- The mod installed through Thunderstore Mod Manager, r2modman, or by hand
- Nothing to download: the patching library (Mono.Cecil) ships with BepInEx

## Usage

Close Valheim first, then right-click the script and pick **Run with PowerShell** — or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-CraftFromContainers.ps1
```

If Windows blocks a downloaded script: right-click the file → Properties → tick **Unblock** → OK.

Start the game with **Start modded** and craft an upgradable item with the materials in a nearby chest.

### Options

| Option | Purpose |
| --- | --- |
| `-Path <dll>` | patch one specific `CraftFromContainers.dll` |
| `-SearchRoot <folder>` | also scan this folder (mod manager moved, game outside Steam) |
| `-Restore` | undo: restore the newest backup |
| `-Force` | patch a package that is not the TeamNibake fork |
| `-NoPause` | do not wait for a key press at the end |

By default the script scans Thunderstore Mod Manager and r2modman profiles, plus Valheim folders found in your Steam libraries, and patches every copy of the fork it finds.

## Notes and limits

- A mod update or reinstall through Thunderstore overwrites the fix — just run the script again.
- Older CraftFromContainers packages (aedenthorn, rendl0449, ...) are skipped: they throw exceptions on Valheim 1.0 and this patch would not make them work. Install the TeamNibake fork instead.
- If a mod version is not recognised, the script stops and says so rather than writing a broken file.
- It does not fix a greyed-out button that has a legitimate cause: not enough materials, crafting station level too low, another mod interfering.
- Tested on ContainerCrafting1point0fork 3.9.3 with Valheim 1.0.14.

This is an unofficial community fix, not affiliated with the mod author or Iron Gate. Use at your own risk; the backup is there for a reason.

---

## En bref (français)

Sur Valheim 1.0, CraftFromContainers ne permet plus de fabriquer les objets améliorables (armes, outils, armures) à partir des coffres : le bouton reste grisé avec « Missing requirement », alors que les matériaux s'affichent en jaune. En cause : un ingrédient d'amélioration caché, ajouté par Valheim 1.0, que le jeu ignore à un établi normal mais que le mod compte quand même.

Le script corrige le fichier du mod pour qu'il applique la même règle que le jeu. Il ne modifie rien dans le jeu et sauvegarde le fichier d'origine.

Jeu fermé, clic droit sur le script → **Exécuter avec PowerShell**. Pour annuler : relancer avec `-Restore`. Après une mise à jour du mod par Thunderstore, il faut le relancer.

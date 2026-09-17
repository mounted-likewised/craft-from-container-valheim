<#
.SYNOPSIS
    Fixes CraftFromContainers (TeamNibake/ContainerCrafting1point0fork) on Valheim 1.0.

.DESCRIPTION
    Valheim 1.0 added a hidden "upgrader" ingredient (m_upgraderResource = true,
    e.g. $item_upgrader_tier1) to every upgradable item: weapons, tools, armor, shields.
    Vanilla skips that requirement unless you stand at an upgrader station, but the mod
    counts it like a normal material, finds 0 of the 1 needed and refuses to craft.

    Result: materials show up in yellow (they ARE seen in your chests), yet the Craft
    button stays greyed out with "Missing requirement" for anything upgradable, while
    arrows, torches, food and other non-upgradable recipes work fine.

    This script rewrites three methods inside the mod's DLL so they follow the vanilla
    rule: at a normal station, ignore upgrader ingredients; at an upgrader station,
    only use those.

        HaveRequirementItems_Patch.Postfix  -> may I craft this?
        ConsumeResources_Patch.Prefix       -> take the materials out of the chests
        BepInExPlugin.PullResources         -> Ctrl key: pull materials to your inventory

    Nothing in the Valheim installation is modified; only the mod's own DLL is patched,
    and the original is backed up next to it first.

.PARAMETER Path
    Optional. Full path to a specific CraftFromContainers.dll. If omitted, the script
    scans: Thunderstore Mod Manager and r2modman profiles, and the Valheim folder
    itself (Steam libraries, for a manual BepInEx install).

.PARAMETER SearchRoot
    Optional. Extra folder to scan, for setups the script cannot guess - a mod manager
    whose data folder was moved, or a game installed outside Steam.
    Example: -SearchRoot "D:\Games"

.PARAMETER Restore
    Undo the patch: put the newest backup back in place.

.PARAMETER NoPause
    Do not wait for a key press at the end (for unattended runs).

.NOTES
    Windows + Thunderstore Mod Manager / r2modman. Close Valheim before running.
    A mod update or reinstall through Thunderstore overwrites the fix; run it again.

    Easiest way to run it: right-click the file -> "Run with PowerShell".
    If the file was downloaded, Windows may refuse to run it: right-click ->
    Properties -> tick "Unblock" -> OK, then try again.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Fix-CraftFromContainers.ps1
#>

[CmdletBinding()]
param(
    [string] $Path,
    [string] $SearchRoot,
    [switch] $Restore,
    [switch] $Force,
    [switch] $NoPause
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "  $msg" }
function Write-Ok($msg)   { Write-Host "  [OK] $msg"   -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!] $msg"    -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [X] $msg"    -ForegroundColor Red }

# Keeps the window open when the script is started from Explorer
# (right-click -> "Run with PowerShell"), which closes it as soon as the script ends.
function Finish($code) {
    if (-not $NoPause) {
        Write-Host ""
        try { Read-Host "Press Enter to close" | Out-Null } catch { }
    }
    exit $code
}

Write-Host ""
Write-Host "CraftFromContainers - Valheim 1.0 upgrader-ingredient fix" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name "valheim*" -ErrorAction SilentlyContinue) {
    Write-Err "Valheim is running. Close the game, then run this script again."
    Finish 1
}

# ---------------------------------------------------------------- find the mod

function Get-ValheimFolders {
    # Steam install(s), for a BepInEx installed by hand in the game folder.
    $found = @()
    try {
        $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
    } catch { $steam = $null }
    $libraries = @()
    if ($steam) {
        $libraries += $steam
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($line in Get-Content $vdf) {
                if ($line -match '"path"\s+"(.+?)"') { $libraries += $matches[1].Replace('\\', '\') }
            }
        }
    }
    foreach ($lib in ($libraries | Sort-Object -Unique)) {
        $game = Join-Path $lib "steamapps\common\Valheim"
        if (Test-Path $game) { $found += $game }
    }
    return $found
}

$searchRoots = @(
    (Join-Path $env:APPDATA "Thunderstore Mod Manager\DataFolder\Valheim\profiles"),
    (Join-Path $env:APPDATA "r2modmanPlus-local\Valheim\profiles")
)
$searchRoots += Get-ValheimFolders
if ($SearchRoot) { $searchRoots += $SearchRoot }
$profileRoots = $searchRoots | Where-Object { Test-Path $_ } | Sort-Object -Unique

if ($Path) {
    if (-not (Test-Path $Path)) { Write-Err "File not found: $Path"; Finish 1 }
    $dlls = @((Get-Item $Path).FullName)
} else {
    if (-not $profileRoots) {
        Write-Err "No mod folder found (Thunderstore Mod Manager, r2modman, or a Valheim install)."
        Write-Step "Point the script at your setup, for example:"
        Write-Step '  -Path "D:\...\BepInEx\plugins\TeamNibake-ContainerCrafting1point0fork\CraftFromContainers.dll"'
        Write-Step '  -SearchRoot "D:\Games"'
        Finish 1
    }
    Write-Step "Scanning: $($profileRoots -join '; ')"
    $dlls = @()
    foreach ($root in $profileRoots) {
        $dlls += Get-ChildItem -Path $root -Recurse -Filter "CraftFromContainers.dll" -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match "\\BepInEx\\plugins\\" } |
                 ForEach-Object { $_.FullName }
    }
    $dlls = $dlls | Sort-Object -Unique
}

if (-not $dlls) {
    Write-Err "CraftFromContainers.dll was not found in the folders scanned above."
    Write-Step "Install 'ContainerCrafting1point0fork' by TeamNibake in Thunderstore first, then run this again."
    Write-Step "If the mod is installed somewhere else, re-run with -Path or -SearchRoot (see the top of this file)."
    Finish 1
}

# ---------------------------------------------------------------- restore mode

if ($Restore) {
    $restored = 0
    foreach ($dll in $dlls) {
        $backup = Get-ChildItem -Path (Split-Path $dll) -Filter "CraftFromContainers.dll.backup-*" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $backup) { Write-Warn "No backup next to $dll"; continue }
        Copy-Item $backup.FullName $dll -Force
        Write-Ok "Restored $dll from $($backup.Name)"
        $restored++
    }
    if ($restored -eq 0) { Write-Err "Nothing restored."; Finish 1 }
    Finish 0
}

# ---------------------------------------------------------------- load Cecil

# Mono.Cecil ships with BepInEx, so nothing has to be downloaded.
$cecil = $null
foreach ($dll in $dlls) {
    $bepinex = $dll
    while ($bepinex -and (Split-Path $bepinex -Leaf) -ne "BepInEx") { $bepinex = Split-Path $bepinex -Parent }
    if ($bepinex) {
        $candidate = Join-Path $bepinex "core\Mono.Cecil.dll"
        if (Test-Path $candidate) { $cecil = $candidate; break }
    }
}
if (-not $cecil) {
    foreach ($root in $profileRoots) {
        $cecil = Get-ChildItem -Path $root -Recurse -Filter "Mono.Cecil.dll" -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match "\\BepInEx\\core\\" } |
                 Select-Object -First 1 -ExpandProperty FullName
        if ($cecil) { break }
    }
}
if (-not $cecil) { Write-Err "Mono.Cecil.dll not found in BepInEx\core. Is BepInEx installed in the profile?"; Finish 1 }
Add-Type -Path $cecil

$OC = [Mono.Cecil.Cil.OpCodes]

function Get-ContinueTargets($body) {
    # In each patched loop the mod starts an iteration with:
    #     if (!requirement.m_resItem) continue;         -> brfalse <loop continue>
    #     amount = requirement.GetAmount(q) * n;
    #     if (amount <= 0) continue;                    -> ble <loop continue>   (not in every method)
    # Insert right after the first test; jump to whichever target is further in
    # the method, which is the real end-of-iteration.
    $ins = $body.Instructions
    $insertAfter = $null; $targets = @()
    for ($i = 0; $i -lt $ins.Count - 2; $i++) {
        if ($ins[$i].OpCode.Code -eq 'Ldfld' -and "$($ins[$i].Operand)" -match 'Requirement::m_resItem' -and
            "$($ins[$i+1].Operand)" -match 'UnityEngine.Object::op_Implicit' -and
            $ins[$i+2].OpCode.Code -like 'Brfalse*') {
            $insertAfter = $ins[$i+2]
            $targets += $ins[$i+2].Operand
            break
        }
    }
    if (-not $insertAfter) { return $null }
    for ($i = 0; $i -lt $ins.Count - 1; $i++) {
        if ("$($ins[$i].Operand)" -match 'Requirement::GetAmount') {
            for ($j = $i; $j -lt [Math]::Min($i + 10, $ins.Count); $j++) {
                if ($ins[$j].OpCode.Code -like 'Ble*') { $targets += $ins[$j].Operand; break }
            }
            break
        }
    }
    $target = $targets | Sort-Object Offset -Descending | Select-Object -First 1
    return [PSCustomObject]@{ InsertAfter = $insertAfter; Target = $target }
}

function Patch-Method($module, $method, $refs) {
    $body = $method.Body
    $reqLocal = $body.Variables | Where-Object { $_.VariableType.Name -eq "Requirement" } | Select-Object -First 1
    if (-not $reqLocal) { throw "unsupported version of this mod (no Requirement loop in $($method.Name))" }

    $spot = Get-ContinueTargets $body
    if (-not $spot) { throw "unsupported version of this mod (code shape of $($method.Name) not recognised)" }

    $opImplicit = ($body.Instructions | Where-Object { "$($_.Operand)" -match 'UnityEngine.Object::op_Implicit' } |
                   Select-Object -First 1).Operand

    [Mono.Cecil.Rocks.MethodBodyRocks]::SimplifyMacros($body)
    $il = $body.GetILProcessor()
    $cont = $spot.InsertAfter.Next
    $noStation = $il.Create($OC::Pop)

    # if (station != null ? station.m_upgrader != req.m_upgraderResource
    #                     : req.m_upgraderResource) continue;   <- exactly what vanilla does
    $seq = @(
        $il.Create($OC::Ldarg_0),
        $il.Create($OC::Callvirt, $refs.GetStation),
        $il.Create($OC::Dup),
        $il.Create($OC::Call, $opImplicit),
        $il.Create($OC::Brfalse, $noStation),
        $il.Create($OC::Ldfld, $refs.Upgrader),
        $il.Create($OC::Ldloc, $reqLocal),
        $il.Create($OC::Ldfld, $refs.UpgraderResource),
        $il.Create($OC::Bne_Un, $spot.Target),
        $il.Create($OC::Br, $cont),
        $noStation,
        $il.Create($OC::Ldloc, $reqLocal),
        $il.Create($OC::Ldfld, $refs.UpgraderResource),
        $il.Create($OC::Brtrue, $spot.Target)
    )
    $prev = $spot.InsertAfter
    foreach ($i in $seq) { $il.InsertAfter($prev, $i); $prev = $i }
    [Mono.Cecil.Rocks.MethodBodyRocks]::OptimizeMacros($body)
}

# ---------------------------------------------------------------- patch

$rocks = Join-Path (Split-Path $cecil) "Mono.Cecil.Rocks.dll"
if (-not (Test-Path $rocks)) { Write-Err "Mono.Cecil.Rocks.dll not found next to Mono.Cecil.dll."; Finish 1 }
Add-Type -Path $rocks

$patchedCount = 0
foreach ($dll in $dlls) {
    Write-Host ""
    Write-Host "Mod: $dll"

    $manifest = Join-Path (Split-Path $dll) "manifest.json"
    $modName = $null
    if (Test-Path $manifest) {
        try {
            $mf = Get-Content $manifest -Raw | ConvertFrom-Json
            $modName = $mf.name
            Write-Step "$($mf.name) $($mf.version_number)"
        } catch { }
    }

    # Older CraftFromContainers packages (aedenthorn, rendl0449, ...) are broken on
    # Valheim 1.0 for unrelated reasons; patching them fixes nothing.
    if (-not $Force -and $modName -and $modName -ne "ContainerCrafting1point0fork") {
        Write-Warn "Not the TeamNibake fork - this build does not work on Valheim 1.0 at all. Skipped."
        Write-Step "Install 'ContainerCrafting1point0fork' by TeamNibake instead (-Force patches this one anyway)."
        continue
    }

    $module = $null
    try {
        $module = [Mono.Cecil.ModuleDefinition]::ReadModule($dll)

        $plugin = $module.GetType("CraftFromContainers.BepInExPlugin")
        if (-not $plugin) { throw "this DLL is not CraftFromContainers (type BepInExPlugin missing)" }

        $targets = @(
            @{ Type = "HaveRequirementItems_Patch"; Method = "Postfix"; What = "allow crafting" },
            @{ Type = "ConsumeResources_Patch";     Method = "Prefix";  What = "take materials from chests" },
            @{ Type = $null;                        Method = "PullResources"; What = "Ctrl: pull materials" }
        )

        $methods = @()
        foreach ($t in $targets) {
            $owner = if ($t.Type) { $plugin.NestedTypes | Where-Object Name -eq $t.Type } else { $plugin }
            if (-not $owner) { throw "$($t.Type) not found - unsupported mod version" }
            $m = $owner.Methods | Where-Object Name -eq $t.Method | Select-Object -First 1
            if (-not $m -or -not $m.HasBody) { throw "$($t.Type).$($t.Method) not found - unsupported mod version" }
            $methods += [PSCustomObject]@{ Method = $m; What = $t.What }
        }

        $already = $methods | Where-Object {
            $_.Method.Body.Instructions | Where-Object { "$($_.Operand)" -match 'Requirement::m_upgraderResource' }
        }
        if ($already.Count -eq $methods.Count) {
            Write-Ok "Already patched - nothing to do."
            $module.Dispose(); $module = $null
            continue
        }
        if ($already.Count -gt 0) { Write-Warn "Partially patched; re-applying to a fresh copy is safer (use -Restore first)." }

        # Build the references from types the mod already uses, so the game's
        # assemblies are not needed.
        $reqType = (($methods[0].Method.Body.Instructions |
                     Where-Object { "$($_.Operand)" -match 'Requirement::m_resItem' } |
                     Select-Object -First 1).Operand).DeclaringType
        $stationType = $module.GetTypeReferences() | Where-Object { $_.FullName -eq "CraftingStation" } | Select-Object -First 1
        $playerType  = $module.GetTypeReferences() | Where-Object { $_.FullName -eq "Player" } | Select-Object -First 1
        if (-not $reqType -or -not $stationType -or -not $playerType) { throw "could not resolve game types from the mod" }

        $getStation = New-Object Mono.Cecil.MethodReference("GetCurrentCraftingStation", $stationType, $playerType)
        $getStation.HasThis = $true

        $refs = @{
            Upgrader         = New-Object Mono.Cecil.FieldReference("m_upgrader", $module.TypeSystem.Boolean, $stationType)
            UpgraderResource = New-Object Mono.Cecil.FieldReference("m_upgraderResource", $module.TypeSystem.Boolean, $reqType)
            GetStation       = $module.ImportReference($getStation)
        }

        foreach ($m in $methods) {
            Patch-Method $module $m.Method $refs
            Write-Ok "patched: $($m.What)"
        }

        $backup = "$dll.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Copy-Item $dll $backup -Force
        Write-Ok "backup: $(Split-Path $backup -Leaf)"

        $tmp = [IO.Path]::GetTempFileName()
        $module.Write($tmp)
        $module.Dispose(); $module = $null
        Copy-Item $tmp $dll -Force
        Remove-Item $tmp -Force
        Write-Ok "written: $dll"
        $patchedCount++
    }
    catch {
        if ($module) { try { $module.Dispose() } catch { } }
        Write-Err "not patched: $($_.Exception.Message)"
    }
}

Write-Host ""
if ($patchedCount -gt 0) {
    Write-Host "Done. Start Valheim with 'Start modded' and craft an upgradable item" -ForegroundColor Cyan
    Write-Host "(flint axe, club, bow, leather armor) with the materials in a nearby chest." -ForegroundColor Cyan
    Write-Host "To undo: run this script again with  -Restore" -ForegroundColor Cyan
} else {
    Write-Host "No file was changed." -ForegroundColor Cyan
}
Write-Host ""
Finish 0

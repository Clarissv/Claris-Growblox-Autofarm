# Claris Growblox Autofarm

WindUI script for Growblox, intended to run through Delta. Version 0.1.5.

Version 0.1.5 adds Anti-AFK and automatic PNB recovery from the world picker. It re-enters the saved breaking world, waits for the avatar and outstanding requests, then plans a walking/jumping route back to the saved PNB position. Movement now uses accessible floors, entrances, and stepping platforms instead of steering straight toward the final position and repeatedly jumping under the dirt.

Version 0.1.4 uses a single block directly above the player: place, break, collect, repeat. New drops stay close to the avatar instead of appearing in the old outer columns. Pickup requests run in batches of up to eight with reserved stack room, one inventory reconciliation per batch, and one gem balance refresh after collection. The completed placement delay also counts toward the initial punching grace period.

Version 0.1.3 collects nearby loose gems, seeds, and returned blocks directly by drop UID while standing at the PNB spot. It waits for drop readiness, respects backpack room and pickup retry cooldowns, and reconciles inventory with the server. Place & Break and Moving Drops now have On/Off toggles that reflect the running task and turn Off on completion, failure, or stop.

Version 0.1.2 fixes Place & Break stopping after one block while waiting for a `tileChanged` echo. Placement is confirmed by a server inventory delta while automatic pickups are paused. Breaking uses the normal client hit completion and a short correction-settling period. The script leaves the game's existing tile-change listener intact.

Version 0.1.1 fixes startup when Delta's `shared` table differs from the game's `shared` table. It resolves the module map through the game's runtime environment or GC tables, loads the inventory independently of missing farming hooks, and retains the original connection error in diagnostics.

## Features

- **Place & Break:** choose a block from your inventory, place one directly above your saved PNB position, break it, collect nearby loose gems, seeds, and returned blocks, and repeat. Refill from the right Display Box when the backpack runs out. Put seeds in the left Display Box at the configured count, which defaults to 200. Stop when both backpack and block storage are empty.
- **Moving Drops:** take the selected blocks from a dedicated farm Display Box, use the linked door to the breaking world, deposit the trip's blocks in the PNB storage box, and return through the other linked door. Continue until stopped or the farm box is empty. Harvesting remains manual.
- **Named configurations:** Save, Load, New, and Delete multiple profiles containing the chosen block, every saved world and tile, the position from which to access each box/door, and timing settings.
- **Anti-AFK:** responds to Roblox's idle event while the script is loaded. Disable it in Settings or unload the script to stop it. The setting is saved per profile.
- **World and position recovery:** PNB automatically rejoins its saved world when Growblox sends the avatar to the world picker. It waits for loading/respawn and returns to the breaking spot through reachable floors and platforms. Stop cancels recovery. Rejoin is saved per profile and defaults to On, including profiles from earlier versions.
- **Control and recovery:** one task runs at a time. Turn its toggle Off to restore the game controls. The toggle also turns Off when the task completes or encounters an error. Server confirmations, request timeouts, and transfer checkpoints prevent an unsuccessful action from silently advancing the loop.

This implementation was traced from the supplied client dump. Offline compilation and mock tests verify the code paths described by their test output. It still needs an in-game test for Delta's debug APIs, actual server acceptance, navigation, and door transfers. Use **Settings → Copy diagnostics** to report the first failure.

## Put this project on GitHub

Publish **the contents of this `logic` folder** at the repository root. Your `prompt` folder, game dump, and original WindUI checkout stay outside the repository. The necessary WindUI bundle and its MIT license are already in `vendor` and in each release.

1. Sign in to GitHub as `Clarissv` and create a **public**, empty repository called `Claris-Growblox-Autofarm`. Leave the automatic README, license, and gitignore options unchecked.
2. Open PowerShell and run:

   ```powershell
   Set-Location -LiteralPath 'F:\VSCode\Luau\Claris Growblox Autofarm\logic'
   git init -b main
   git add .
   git commit -m "Add Growblox PNB, moving drops, and configuration profiles"
   git remote add origin https://github.com/Clarissv/Claris-Growblox-Autofarm.git
   git push -u origin main
   ```

3. Complete GitHub sign-in if Git requests it. Check that the repository's root contains `loader.lua`, `main.lua`, `releases`, and `vendor`.
4. Join a Growblox world, wait until the character can move, and execute this in Delta:

   ```lua
   loadstring(game:HttpGet("https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"))()
   ```

The URL becomes usable after the upload. The loader downloads a specific release of the script and WindUI. Rebuilding creates another release and updates the loader while preserving earlier releases.

For a browser upload instead, open the empty repository's **uploading an existing file** link and drag this folder's contents into the upload area. Preserve `src`, `tests`, `vendor`, and `releases` as folders. Commit directly to `main`.

For an existing checkout with the GitHub remote configured, upload this rebuilt update with:

```powershell
Set-Location -LiteralPath 'F:\VSCode\Luau\Claris Growblox Autofarm\logic'
git add .
git commit -m "Add anti-AFK, world recovery, and platform navigation"
git push
```

## Set up Place & Break

1. Select the block on the **Place & Break** tab. Press **Refresh inventory choices** after obtaining a new block.
2. Arrange the storage row as `Seed box - Empty - Player - Empty - Block box`. Leave the tile directly above the player empty.
3. Stand still on the middle platform and press **Save PNB spot and matching boxes**. This saves the two boxes automatically when the screenshot's layout matches. If needed, stand beside each box and save it separately.
4. Keep each Display Box dedicated to its corresponding item. Mixed boxes are rejected because Growblox's withdrawal action can take every item type in a box.
5. On **Configurations**, enter a name such as `Sugar Cane - Farm 1`, then press **Save profile / Save as**.
6. Turn **Place & Break** On. Turn it Off to end the task. The UI stays accessible through the floating Claris button.

The script walks to saved positions and storage through the game's normal 2D controls. Loose-drop collection itself keeps the player at the PNB spot and targets drops close to the single farming tile. Full block stacks leave excess blocks for later cycles; reaching the seed threshold deposits seeds and frees room. Repeated server pickup refusal stops the task with a diagnostic containing the rejected UIDs, item IDs, and positions. Keep paths reachable and avoid moving the player manually during a task. If a position times out, check the path and save it again.

For the raised dirt setup, save the PNB position while standing on top of the dirt. Keep access to the entrance beside the world lock and the stepping platforms. The planner reads the current collision map, uses entrances only when the game allows walking through them, and avoids harmful blocks. It can move sideways or down to reach a better jump position, then jump back onto the dirt. A stalled route is replanned up to four times within the movement timeout; a sealed or unreachable spot produces a diagnostic.

**Settings → Anti-AFK** and **Rejoin world and return to PNB** both default to On. Loading an older profile adds these defaults without changing its saved locations. Rejoining applies to Place & Break; Moving Drops retains its transfer checkpoints and existing recovery rules. If Roblox changes servers, the script arms Delta's teleport queue before farming starts. When that function is available, the same GitHub loader resumes the saved farm after arrival. Otherwise, run the loader again and use **Configurations → Resume saved farm**. A different live world is treated as an unexpected change and stops PNB.

Existing profiles and saved locations still work. Collect any drops remaining in the old outer columns manually once; the new loop does not place blocks there. **Settings → Time to wait for drops** now defaults to 0.1 seconds and allows zero. Loaded profiles retain their saved delay, so set this to 0.1 or zero and save again if your old profile uses 0.75 seconds. The game still controls drop readiness; lowering this extra delay does not bypass that wait.

## Set up Moving Drops

1. Select the block on **Place & Break**. This choice also applies to Moving Drops.
2. In the farm world, harvest manually and place the harvested blocks in the farm Display Box.
3. Stand beside that box and press **Save Farm storage** on **Moving Drops**. Stand beside the linked door and save **Farm door to breaking world**.
4. In the breaking world, save the destination Display Box using **Save block storage** on **Place & Break**. Stand beside the return door and save **Breaking door to farm world**.
5. Verify the doors link to the intended worlds and arrival doors. Save the named profile after recording both worlds.
6. Return to the farm world and turn **Moving Drops** On. Turn it Off to stop.

The script records only the newly withdrawn blocks as each trip's cargo. Blocks already in the backpack are retained. If the backpack has no room, free up space before starting.

When a linked door changes Roblox servers, Delta's teleport queue reloads the GitHub loader and resumes the saved transfer when that executor function is available. If Delta does not expose a teleport queue, execute the loader again after arrival and press **Configurations → Resume saved transfer**.

An interrupted storage request leaves a `pickupPending` or `depositPending` checkpoint. Check the backpack and both boxes before pressing **Clear saved transfer** and starting again. This avoids repeating a storage action whose result was lost. Normal Stop clears the automatic resume checkpoint; restarting starts a fresh task.

## Configuration files

Profiles are saved in Delta's local `ClarisGrowblox/profiles/<name>.json` files. Saving again under a different name creates another profile. Loading a profile changes the script's selected block, saved locations, and settings; it does not move the player.

Saved files are validated before loading. Profile names accept letters, numbers, spaces, underscores, and hyphens. Each save is checked by reading it back; an existing file is backed up as `.json.bak`. Transfer recovery uses `ClarisGrowblox/resume.json`, tied to the Roblox account and expiring after six hours.

Automatic PNB recovery uses `ClarisGrowblox/pnb-resume.json`, containing the running farm's profile and configuration. It refreshes every two minutes during a running farm and is checked against the account and a six-hour expiry. Normal Stop or completion clears it. A pending server teleport preserves it for the queued loader or **Resume saved farm**.

## Development

Edit `src/main.lua`, `src/core.lua`, and `src/navigation.lua`, then run from this folder:

```powershell
npm run build
npm test
npm run test:lua
```

The build uses only Node's standard library and the supplied `../WindUI` checkout; no npm installation is required. `tests/run.ps1` uses the existing Lua library at `C:\Program Files\VideoLAN\VLC\plugins\lua\liblua_plugin.dll`. An alternate compatible DLL can be supplied with `-LuaLibrary`. The Lua test runner compiles the complete generated script and loader and executes the offline fixtures.

Version 0.1.5 passes 75 offline checks: 14 configuration/layout/storage tests, 59 tests executing the generated runtime against mock services and a mock server, and two release checks. New cases include a simulated climb around blocked dirt through a side entrance, inaccessible/harmful supports, stop during navigation/rejoin, re-entry from the picker including an interrupted inventory RPC, loading/respawn, failed entry retry limits, anti-AFK settings and cleanup, and account/expiry/renewal checks for PNB recovery. Existing drop, inventory, and toggle checks remain. Live server acceptance, actual navigation, and Delta's teleport queue still need in-game verification.

Push the rebuilt files, new `releases/<revision>` folder, and updated `loader.lua` together. Do not modify an existing release's files. Keep the same GitHub `loadstring` when updating the project.

## Sources and limitations

See `RESEARCH.md` for the client-dump evidence behind the game adapter. Runtime access requires Delta's `getgc` and debug upvalue/function-name APIs. Randomized module references are resolved through the game's own shared registry. A future game update can change those references or private handlers; the script stops with a diagnostic when it cannot identify them.

The original instructions and screenshot were read without modification.

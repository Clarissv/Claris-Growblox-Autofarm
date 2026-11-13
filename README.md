# Claris Growblox Autofarm

WindUI script for Growblox, intended to run through Delta. Version 0.1.8.

Version 0.1.8 fixes recovery when the picker appears during an exit animation, inventory read, or an earlier recovery attempt. It also detects the visible picker even if the game still reports the old world and avatar, and performs the normal picker HUD/focus cleanup after successful entry. Rejoining looks for the saved breaking world in Recently Visited Worlds, falls back to its saved name, waits for one second of stable loading, then returns to PNB. Interrupted inventory replies are checked against current world/avatar state before being applied.

Version 0.1.7 adds a Discord Webhook tab with Send stats now, an automatic reporting toggle, an interval input in minutes, and optional saved Display Box counts. Reports include player level and gem balance, world/profile, farm status, backpack blocks/seeds, and session totals. Webhook settings are saved per profile; older profiles default to reports Off.

Version 0.1.6 fixes a false movement timeout during storage refill or the return to PNB. Waypoints and the final destination now use the same arrival checks, so an avatar slightly off-center on the saved tile finishes moving and resumes farming.

Version 0.1.5 adds Anti-AFK and automatic PNB recovery from the world picker. It re-enters the saved breaking world, waits for the avatar and outstanding requests, then plans a walking/jumping route back to the saved PNB position. Movement now uses accessible floors, entrances, and stepping platforms instead of steering straight toward the final position and repeatedly jumping under the dirt.

Version 0.1.4 uses a single block directly above the player: place, break, collect, repeat. New drops stay close to the avatar instead of appearing in the old outer columns. Pickup requests run in batches of up to eight with reserved stack room, one inventory reconciliation per batch, and one gem balance refresh after collection. The completed placement delay also counts toward the initial punching grace period.

Version 0.1.3 collects nearby loose gems, seeds, and returned blocks directly by drop UID while standing at the PNB spot. It waits for drop readiness, respects backpack room and pickup retry cooldowns, and reconciles inventory with the server. Place & Break and Moving Drops now have On/Off toggles that reflect the running task and turn Off on completion, failure, or stop.

Version 0.1.2 fixes Place & Break stopping after one block while waiting for a `tileChanged` echo. Placement is confirmed by a server inventory delta while automatic pickups are paused. Breaking uses the normal client hit completion and a short correction-settling period. The script leaves the game's existing tile-change listener intact.

Version 0.1.1 fixes startup when Delta's `shared` table differs from the game's `shared` table. It resolves the module map through the game's runtime environment or GC tables, loads the inventory independently of missing farming hooks, and retains the original connection error in diagnostics.

## Features

- **Place & Break:** choose a block from your inventory, place one directly above your saved PNB position, break it, collect nearby loose gems, seeds, and returned blocks, and repeat. Refill from the right Display Box when the backpack runs out. Put seeds in the left Display Box at the configured count, which defaults to 200. Stop when both backpack and block storage are empty.
- **Moving Drops:** take the selected blocks from a dedicated farm Display Box, use the linked door to the breaking world, deposit the trip's blocks in the PNB storage box, and return through the other linked door. Continue until stopped or the farm box is empty. Harvesting remains manual.
- **Named configurations:** Save, Load, New, and Delete multiple profiles containing the chosen block, every saved world and tile, the position from which to access each box/door, and timing settings.
- **Discord reports:** send stats manually or automatically every 1-1440 minutes, defaulting to five. Include selected block/seed counts from the saved storage boxes in the current world. Reporting runs independently of farming and respects Discord cooldowns.
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
git commit -m "Fix world picker recovery and recent world re-entry"
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

Recovery checks the picker throughout loading, including when it appears after an inactive exit animation or interrupts a previous recovery. The script uses the same Recent worlds list as the game, selects the first matching entry for the saved PNB world, and uses the saved name if the list has no match or returns an error. Another world at the top of Recent does not replace the saved farming setup. When the picker UI hook is available, recovery recognizes its visibility separately from the internal world name and restores the game's HUD after entry. Copied diagnostics report the picker hook/visibility and Recent selection. Entry is limited to three attempts per recovery; three consecutive interrupted recoveries stop with a diagnostic. Malformed inventory responses get up to three read-only attempts, and a genuine invalid response still stops the task.

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

## Set up Discord reports

1. In Discord, open the destination channel's settings, choose **Integrations → Webhooks**, create a webhook, and copy its URL.
2. In the script's **Discord Webhook** tab, paste the URL into **Discord webhook URL**.
3. Enter your interval in **Send every (minutes)**, for example `1`, `5`, or `30`. Values from 1 to 1440 are accepted, including decimals such as `1.5`.
4. Leave **Include Display Box counts** On to report the saved block box, seed box, and farm box. Select the block and save these boxes using the existing setup controls. Reports count only the selected block or its seed, including matching stacks in a mixed box. Farming still requires dedicated storage.
5. Press **Send stats now** to check delivery, then turn **Automatic webhook reports** On. Enabling sends a report and starts the interval. Editing the interval schedules the next report from that change; manual sends also restart the interval. Discord's retry delay can postpone a report.
6. Use **Configurations → Save profile / Save as** to keep the URL, interval, and toggles. Webhook controls can be changed while farming; saving a profile retains the existing requirement to stop the farm first.

Reports include Roblox player name, Growblox level and gem balance, current world/profile, farm status, selected block, backpack blocks/seeds, and blocks broken, gems collected, trips, and blocks moved during this script session. Session totals reset when reloading the script. Level and gem balance use the game's read-only APIs; failed or slow queries show **Unavailable**. Backpack and box counts come from the client's current data without moving the avatar or taking anything from storage. Boxes in another world, missing saved locations, or invalid saved tiles are marked explicitly; the reporter does not enter another world to read them.

Automatic reporting continues while the script is loaded, including when the farm is Off or recovering. Turn its reporting toggle Off or unload the script to end future reports. A request already sent can still finish. **Webhook status** shows delivery results, last successful send, and the next interval. HTTP errors and Discord rate limits do not stop farming. Reports wait for unsettled requests before sending again. Delta must expose `request`, `http_request`, or a supported equivalent for Discord delivery.

The webhook URL is saved in the local profile and farm recovery files. Keep those files and the URL private. The URL is excluded from reports and copied diagnostics; the project's gitignore excludes the local `ClarisGrowblox` data folder.

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

Version 0.1.8 passes 111 offline checks: 19 configuration/layout/storage tests, 90 tests executing the generated runtime against mock services and a mock server, and two release checks. Added recovery fixtures cover delayed picker transitions, brief false readiness, invalid/interrupted inventory responses, a second picker return during recovery, bounded retries, Recent selection/fallback, correct picker discovery, and HUD/focus restoration with a stale active world. Existing webhook, navigation, refill, drop, inventory, recovery, anti-AFK, and toggle checks remain. Live game/server behavior, picker-hook discovery in Delta, the teleport queue, and real Discord delivery still need in-game verification.

Push the rebuilt files, new `releases/<revision>` folder, and updated `loader.lua` together. Do not modify an existing release's files. Keep the same GitHub `loadstring` when updating the project.

## Sources and limitations

See `RESEARCH.md` for the client-dump evidence behind the game adapter. Runtime access requires Delta's `getgc` and debug upvalue/function-name APIs. Randomized module references are resolved through the game's own shared registry. A future game update can change those references or private handlers; the script stops with a diagnostic when it cannot identify them.

The original instructions and screenshot were read without modification.

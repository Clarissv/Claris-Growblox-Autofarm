# Claris Growblox Autofarm

WindUI script for Growblox, intended to run through Delta. Version 0.1.22.

Version 0.1.22 adds **Configurations → Export config / Import config** for emulator-to-cloud-phone and multi-account setup. Export copies the current settings, saved locations, full farm list, per-world harvest boxes, and harvesting method into portable JSON. It also saves an export file when Delta file functions are available. Import validates the text, saves a named profile and account-bound session on the destination device, and keeps farming Off. Exported setups contain settings only; running cargo/progress stays local to its account. Saved profile JSON files can also be imported.

Version 0.1.21 adds tree harvesting with **Fist** and **Dear John Tractor**. It breaks ripe trees before collecting matching blocks and seeds into the same Farm Display Box, preserves top-down zigzag direction, and skips empty or growing rows. Planting checks live row space before positioning and suspends harvesting vehicles during planting travel. Moving Drops now accepts a mixed block/seed Farm box, keeps up to 200 seeds between block trips, and returns held seeds to that box when all blocks have moved. **Full Rotation** plants the entire Planting world list, waits for maturity, harvests and processes each farm through PNB, returns seeds to planting stock, and repeats with saved progress across world changes.

Version 0.1.20 removes empty Harvest Drops travel. It checks the current matching loose drops before visiting a row, skips empty rows while retaining each farm row's zigzag direction, and stops crossing a row once its selected drops are gone. Positioning cancels if its destination is cleared during travel. With no matching floating blocks and none held in the backpack, it finishes after the existing short settling check without walking or respawning. Storage travel occurs when selected blocks need depositing; a full backpack is stored before travelling to another row. Planting retains its v0.1.19 route.

Version 0.1.19 gives Harvest Drops and Planting a stable top-down zigzag: start at the top-left supported row, cross to the right, descend to the next supported row at that side, then cross to the left and repeat. "Down one" means the next farm row, which may be several tiles below. With edge platforms in the second-to-last columns, navigation leaves the platform slowly through the outer empty column and steers back onto the next row. Individual box roofs and stepping stones do not change the direction of long farm rows. Planting keeps its row layout through seed refills and saved progress; a harvest storage/respawn trip returns to the current row before continuing. Supported multirow harvests request pickups after reaching the matching row, preserving partial-stack waits and precise retries. Other layouts retain the existing navigation and pickup fallback. The pickup, fast-loading, and native-menu Respawn fixes from v0.1.16–0.1.18 are included.

Version 0.1.18 fixes Respawn to Farm storage silently walking back because the script looked for Respawn on the world table. The supplied client exposes it on the native menu adapter. Attachment now finds that adapter using its matching world-entry function and world-owned currentWorld function, including during the faster startup. Harvest invokes the native menu action after pickups settle, waits for respawn, confirms the backpack, and walks the remaining distance to storage. Diagnostics show the bound Respawn source and whether the return was requested, completed, skipped because storage was within four tiles, or unavailable. Unavailable actions produce a visible walking-fallback message.

Version 0.1.17 speeds up Moving Drops attachment after script reloads and server changes. Startup attaches movement, storage, and the live backpack first; punching and planting hooks are discovered when their tasks start. The loader caches verified release files locally and starts both downloads together when a release is new. Transfer trips use four inventory reads rather than six, preserving before/after confirmation for each storage action. Door entry and resumed transfers wait for the destination avatar to be ready instead of imposing the old half-second door wait and three-second teleport startup delay. Diagnostics show attachment time, cached/downloaded files, and the last door's readiness wait.

Version 0.1.16 fixes Harvest Drops stopping for upper-row blocks while walking on the row below. After the server rejects distant pickup, navigation and collection stops require the native horizontal distance and vertical body overlap. A refusal during a row pass releases that stack for a precise approach instead of consuming all retries while holding off-center. Diagnostics include the rejected pickup's avatar position, distance to the drop, and overlap result. Session restore warnings now distinguish account mismatch from unsupported save schema and appear separately from save failures.

Version 0.1.15 fixes trails of blocks left during a harvest pass. The player holds near a stack until its pickup replies finish and the stack is empty, including partial takes, pending drops, readiness delays, and clusters requiring more than eight requests. A full backpack still returns to storage and resumes collection. Straight row travel is retained between these collection stops. Pickup waiting has its own timeout and does not count as a failed movement step.

Version 0.1.14 removes per-tile braking on straight walking segments and collects nearby blocks while moving along a harvest row. Harvest keeps its direction until the forward portion is processed, then handles remaining blocks or another row. A full backpack ends the current pass before returning to storage. **Respawn to Farm storage** defaults to On: when farther than four tiles from the saved standing position and the native hook is available, it waits for pickups and inventory reconciliation, respawns, confirms the backpack, and walks the remaining distance to the box. Turn this Off for farms whose respawn point is far from storage.

Version 0.1.13 fixes Harvest Drops navigation stopping at storage when a drop requires a route through distant edge platforms. Both pickup approach and the movement follower now search the full world, with up to 90 seconds per harvest movement. The planner can descend open columns longer than eight tiles and allows enough simulation time to land after a tall fall. Planting uses the same descent fix. Supported pickup positions cover the native vertical reach, and failed approaches distinguish missing support from a missing route.

Version 0.1.12 reduces startup work after a reported freeze before the UI appeared. Discovery yields between batches and caches function metadata for the duration of attachment. The seed dropdown shows up to 40 relevant or matching choices, builds them once per refresh, and includes a separate search field for other seeds. Diagnostics include the current startup stage, discovery yields, and rendered seed count.

Version 0.1.11 adds Planting: choose a seed, save its dedicated Display Box, and enter an ordered list of dirt farm worlds. It fills supported empty foreground tiles, refills at zero seeds, and continues through the list. Settings and saved places now restore from a local session file after script reloads and server teleports, including Moving Drops setups.

Version 0.1.10 fixes startup's dependence on three exact module keys. It can recover the registry from protected proxy method upvalues, use item definitions captured by the active world's functions, or find one validated definition table in GC. It only loads the known item module when needed. Diagnostics show registry availability, discovered world/controller counts, and the item-definition source or failure.

Harvest Drops breaks ripe trees of the selected block first, then collects matching loose blocks and seeds throughout the current farm world into the same saved Farm Display Box. Supported long rows use top-down zigzag order and skip rows without work. Growing trees remain planted. An optional setting starts Moving Drops after successful collection and storage.

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
- **Moving Drops:** move selected blocks from a Farm Display Box through linked doors to PNB storage. The Farm box can also contain matching seeds; keep the seed stack during block trips, then return seeds to the Farm box when finished.
- **Harvest Drops:** choose Fist or Dear John Tractor, break ripe trees in top-down zigzag order, then collect and store matching blocks and seeds in the same Farm Display Box. Store either stack when full and optionally start Moving Drops afterward.
- **Planting:** fill supported empty tiles with the selected seed across multiple dirt farms. Refill from a dedicated seed Display Box, skip occupied/floating/denied/unreachable cells, and preserve progress across server changes. It never punches obstacles or combines existing trees with another seed.
- **Named configurations:** Save, Load, New, and Delete multiple profiles containing the chosen block, every saved world and tile, the position from which to access each box/door, and timing settings.
- **Full Rotation:** plant every world in the Planting list, wait for tree maturity, harvest each farm, move its blocks to PNB, replenish planting seeds, and repeat until stopped. Save a harvest box in every farm world and use the PNB seed box for planting stock.
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
git commit -m "Bind the native Respawn action for harvest storage returns"
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

## Collect harvested drops into Farm storage

1. On **Place & Break**, select the harvested block, such as Sugar Cane. The same selected block applies to Harvest Drops and Moving Drops.
2. In the farm world, stand beside a Display Box for the selected block and its seed and use **Harvest Drops → Save Farm storage**. The location is shared with **Moving Drops → Farm storage**, so an existing saved box works. Save your profile after setup.
3. Choose **Harvest method → Fist** or **Dear John Tractor**, then turn **Collect harvest** On. Ripe trees are broken first; growing trees stay planted. Matching loose blocks and seeds, including those already held, are then collected and stored in the same box. **Respawn to Farm storage** defaults to On; keep it enabled when the respawn door is near the box or turn it Off to walk back.
4. Enable **Start Moving Drops after collection** before starting if you want automatic transport. Both linked doors and the destination block box must already be saved. This option is saved per profile and defaults to Off for older profiles. When collection finishes, Collect harvest turns Off and Moving Drops turns On for the transfer. With the option Off, you can start Moving Drops manually afterward.
5. Turn the active task toggle Off to stop. The status shows collection, movement, and storage progress; collected/stashed session totals also appear in Discord reports.

Collection reads the current world's loose-drop list and targets the selected block and its matching seed. It respects drop readiness, retry cooldowns, and backpack capacity. There is no identified server action to move loose drops directly into a Display Box, so collection and verified deposit are separate actions. If distant UID pickups are accepted, the script can stay at the box. If refused, it uses the collision-aware walking/jumping planner to get near the drops and returns to storage as needed. Live pickup reach determines which path is used.

Pickup routes and walking returns to storage search the full world, including distant edge platforms and long open columns. Straight supported walking steps form a single run, with precise stops at destinations, turns, jumps, and landings. After a distant pickup refusal, the chosen standing position must overlap the drop vertically and be less than 0.6 tiles away horizontally. When at a stack, the player holds position through server replies, partial takes, readiness delays, and additional batches until the stack is removed or the backpack fills. A refused route pickup leaves the stack for a precise approach before retrying. Pickup batches still respect cooldowns and capacity. Each harvest movement allows up to 90 seconds of travel; pickup waits have their own action timeout, reset on successful collection. Route search yields and checks for Stop or a world change. Keep the saved box and farm platforms reachable. A failed deposit retains the backpack blocks; an unreachable or repeatedly refused drop stops with its UID and coordinates. Automatic transport begins only after successful collection, including a short empty-list settling check. Expected storage respawns wait for a stable avatar and verify the backpack before depositing; an unexpected world change or respawn can interrupt collection. Standalone harvest pauses on unexpected world changes; Full Rotation can return to its saved harvest phase. Pending accepted pickups still settle after Stop, so wait for requests before restarting collection. Harvest Drops leaves gems and unrelated crops alone. Fist targets only the selected crop. Tractor uses the game's native harvesting behavior and therefore requires a farm without other seed types. It equips only during harvesting rows, removes the tractor during other travel, and restores previous footwear on completion, error, or Stop. Missing growth/equipment hooks pause with a diagnostic.

## Set up Moving Drops

1. Select the block on **Place & Break**. This choice also applies to Moving Drops.
2. In the farm world, use Harvest Drops to break ripe trees and store matching blocks and seeds in the Farm Display Box. You can also fill the box manually.
3. Stand beside that box and press **Save Farm storage** on **Moving Drops**. Stand beside the linked door and save **Farm door to breaking world**.
4. In the breaking world, save the destination Display Box using **Save block storage** on **Place & Break**. Stand beside the return door and save **Breaking door to farm world**.
5. Verify the doors link to the intended worlds and arrival doors. Save the named profile after recording both worlds.
6. Return to the farm world and turn **Moving Drops** On. Turn it Off to stop.

The script records only the newly withdrawn blocks as each trip's cargo. Blocks already in the backpack are retained. If the backpack has no room, free up space before starting. Mixed Farm boxes may contain only the selected block and its seed. Seeds returned alongside blocks are confirmed separately and held through block trips, up to the native 200-item stack limit. On completion, all held matching seeds are deposited back into the Farm box. Stop or an interrupted transfer can leave seeds in the backpack; the script does not discard them. PNB block and seed boxes remain dedicated.

When a linked door changes Roblox servers, Delta's teleport queue reloads the GitHub loader and resumes the saved transfer when that executor function is available. If Delta does not expose a teleport queue, execute the loader again after arrival and press **Configurations → Resume saved transfer**.

After a release's first load, the loader reuses its validated main script and WindUI files from `ClarisGrowblox/cache/<revision>` across server changes. A new release downloads its own files; damaged cache files are fetched again. If Delta's file functions are unavailable or cache writes fail, loading continues with ordinary downloads. The small GitHub loader is still fetched to select the current release. Startup skips the full punching/planting function scan for Moving Drops and Harvest Drops. Place & Break and Planting perform that scan when selected. Transfers proceed as soon as the destination world and avatar are ready, with request timeouts and cargo checkpoints retained.

An interrupted storage request leaves a `pickupPending`, `depositPending`, or `seedReturnPending` checkpoint. Check the backpack and both boxes before pressing **Clear saved transfer** and starting again. This avoids repeating a storage action whose result was lost. Normal Stop clears the automatic resume checkpoint; restarting starts a fresh task.

## Set up Discord reports

1. In Discord, open the destination channel's settings, choose **Integrations → Webhooks**, create a webhook, and copy its URL.
2. In the script's **Discord Webhook** tab, paste the URL into **Discord webhook URL**.
3. Enter your interval in **Send every (minutes)**, for example `1`, `5`, or `30`. Values from 1 to 1440 are accepted, including decimals such as `1.5`.
4. Leave **Include Display Box counts** On to report the saved block box, seed box, and farm box. Select the block and save these boxes using the existing setup controls. Reports count only the selected block or its seed, including matching stacks in a mixed box. PNB and standalone planting require dedicated storage; the Farm box accepts matching blocks and seeds.
5. Press **Send stats now** to check delivery, then turn **Automatic webhook reports** On. Enabling sends a report and starts the interval. Editing the interval schedules the next report from that change; manual sends also restart the interval. Discord's retry delay can postpone a report.
6. Use **Configurations → Save profile / Save as** to keep the URL, interval, and toggles. Webhook controls can be changed while farming; saving a profile retains the existing requirement to stop the farm first.

Reports include Roblox player name, Growblox level and gem balance, current world/profile, farm status, selected block, backpack blocks/seeds, and blocks broken, gems collected, trips, blocks moved, harvest blocks collected, and blocks stashed during this script session. Session totals reset when reloading the script. Level and gem balance use the game's read-only APIs; failed or slow queries show **Unavailable**. Backpack and box counts come from the client's current data without moving the avatar or taking anything from storage. Boxes in another world, missing saved locations, or invalid saved tiles are marked explicitly; the reporter does not enter another world to read them.

Automatic reporting continues while the script is loaded, including when the farm is Off or recovering. Turn its reporting toggle Off or unload the script to end future reports. A request already sent can still finish. **Webhook status** shows delivery results, last successful send, and the next interval. HTTP errors and Discord rate limits do not stop farming. Reports wait for unsettled requests before sending again. Delta must expose `request`, `http_request`, or a supported equivalent for Discord delivery.

The webhook URL is saved in the local profile, session, and task recovery files. Keep those files and the URL private. The URL is excluded from reports and copied diagnostics; the project's gitignore excludes the local `ClarisGrowblox` data folder.

## Set up Planting

1. Enter your seed storage world and stand beside a Display Box dedicated to one seed type.
2. Open **Planting → Save seed Display Box**. This saves the box, standing position, and storage world. A box containing seeds also selects its seed automatically. **Seed to plant** shows backpack seeds, the saved selection, available source-box seeds, and the seed related to the selected PNB block. Use **Find seed by name or ID** to find other types. Searches show at most 40 choices and retain your current selection.
3. Enter farm names under **Dirt farm worlds (in order)**, separated by commas, for example `FARM1, FARM2, FARM3`. Duplicate names are removed while preserving order. The storage world must be different from the farm worlds.
4. Turn **Plant seeds** On. The script enters the first farm, plants empty supported tiles, and refills from storage when its backpack runs out. It returns to the unfinished farm after each refill, then moves to the next farm when the current scan is complete.
5. Turn the toggle Off to stop. Named profiles also save the seed type, storage box, and farm list.

Planting requires an empty foreground tile with a solid block or platform directly underneath, matching the native seed placement rule. Doors, air vents, existing trees, and other occupied tiles are skipped; empty air without support is skipped too. Native placement checks still enforce access and reach. The script walks and jumps to each planting tile. Planting routes can search the whole world and have up to 90 seconds to reach a tile, allowing detours to distant edge platforms. Access-denied or unreachable supported tiles are counted in Recent activity; a completed scan does not claim those tiles were filled.

An empty seed box ends the task and identifies the unfinished farm. A mixed box or failed server confirmation stops with a diagnostic. An interrupted seed placement is reconciled from the live tile and backpack before retrying. An interrupted storage withdrawal is not replayed automatically: check the backpack and box, then use **Clear saved planting** before starting again.

Planting saves its farm index before world changes and tracks interrupted seed actions. When Delta's teleport queue is available, the GitHub loader resumes planting after a server change. Otherwise, execute the loader again and use **Planting → Resume planting**. Normal Stop or successful completion clears the planting checkpoint. Settings remain saved.

## Full Rotation guide

See [README-ROTATION.md](README-ROTATION.md) for setup, the complete cycle, saved progress, and recovery instructions.

## Export from an emulator and import on a cloud phone

1. On the source device, open **Configurations → Export config**. This exports the current setup, including changes not yet saved under a named profile. Exporting works while farming runs. Copy the exported text from the clipboard or the **Configuration text** field to your destination device.
2. Run v0.1.22 on the destination device and stop any active task. Open **Configurations**, paste the complete export into **Configuration text**, and optionally enter **Import as profile**. Leaving the name blank keeps the exported profile name.
3. Press **Import config**. The setup is applied and saved locally as that profile, and the session is saved for the destination account. You do not need another Save profile step. Existing profiles with the same name get a `.bak` backup.
4. Check saved locations, seed/block selection, and the farm list, then turn on the task you want. Import keeps tasks Off and clears previous local task-recovery checkpoints; it does not move inventory or transfer an in-progress trip from another device.

For file transfer, Export config also saves `ClarisGrowblox/exports/<profile>.json` when file functions are available. Copy that file to the destination device, enter its local path in **Configuration file path**, and press **Import config file**. Existing `ClarisGrowblox/profiles/<name>.json` profile files work too. If clipboard or file access is unavailable, the exported text remains in the Configuration text field. Exports include saved webhook settings and the webhook URL.

Configs are portable between Roblox accounts, but saved locations still refer to the original world's tiles. For another account, save its PNB spot and matching left/right boxes, press **Full Rotation → Use PNB seeds for planting**, assign its farm list, and save the harvest box in each assigned farm. Save the result under that account's profile name. Moving the character alone does not update coordinates. Each account needs access to its worlds and its own tractor for Tractor mode. Simultaneous accounts should use separate assigned farms and storage; the script has no shared-work coordination. Update linked doors too if using standalone Moving Drops.

## Configuration files

Profiles are saved in Delta's local `ClarisGrowblox/profiles/<name>.json` files. Saving again under a different name creates another profile. Loading a profile changes the script's selected block, saved locations, and settings; it does not move the player.

The current configuration and profile name are also saved automatically to `ClarisGrowblox/session.json`, including changes not yet saved under a named profile. The script restores this account-bound session before building the UI after a reload or server teleport. It saves before task/world transitions and checks for setting changes every second. An existing idle script's newest configuration takes precedence during an in-place reload. Copied diagnostics show session save/restore failures.

Saved files are validated before loading. Profile names accept letters, numbers, spaces, underscores, and hyphens. Each save is checked by reading it back; an existing file is backed up as `.json.bak`. Transfer recovery uses `ClarisGrowblox/resume.json`, tied to the Roblox account and expiring after six hours.

Automatic PNB recovery uses `ClarisGrowblox/pnb-resume.json`, containing the running farm's profile and configuration. It refreshes every two minutes during a running farm and is checked against the account and a six-hour expiry. Normal Stop or completion clears it. A pending server teleport preserves it for the queued loader or **Resume saved farm**.

Planting recovery uses `ClarisGrowblox/plant-resume.json`, with the configuration, farm index, refill phase, skipped cells, and any pending seed action. It is checked against the account and a six-hour expiry. Counters such as Seeds planted describe the current loaded script instance.

Rotation recovery uses `ClarisGrowblox/rotation-resume.json`, bound to the account and a six-hour checkpoint expiry. Running rotations refresh it during maturity waits, actions, phase changes, and at least every two minutes while requests are settled. A continuously refreshed checkpoint does not impose a six-hour run limit.

## Development

Edit `src/main.lua`, `src/core.lua`, and `src/navigation.lua`, then run from this folder:

```powershell
npm run build
npm test
npm run test:lua
```

The build uses only Node's standard library and the supplied `../WindUI` checkout; no npm installation is required. `tests/run.ps1` uses the existing Lua library at `C:\Program Files\VideoLAN\VLC\plugins\lua\liblua_plugin.dll`. An alternate compatible DLL can be supplied with `-LuaLibrary`. The Lua test runner compiles the complete generated script and loader and executes the offline fixtures.

Version 0.1.22 passes 266 offline checks: 39 configuration/layout/storage tests, 219 generated-runtime tests against mock services/server, six generated-loader tests, and two release checks. New coverage verifies portable export fields, saved-profile imports, account-independent setup with destination-account session persistence, rollback on import save failure, profile backups, invalid JSON/version/recovery-file rejection, and running-task import guards. Prior harvesting, rotation, transfer, navigation, and recovery checks remain passing. These mocks do not establish live clipboard behavior, tractor/server acceptance, Delta frame times, planting reach, route geometry, permissions, teleport queue behavior, or Discord delivery.

Push the rebuilt files, new `releases/<revision>` folder, and updated `loader.lua` together. Do not modify an existing release's files. Keep the same GitHub `loadstring` when updating the project.

## Sources and limitations

See `RESEARCH.md` for the client-dump evidence behind the game adapter. Runtime access requires Delta's `getgc` and debug upvalue/function-name APIs. Item definitions are identified through active-world function upvalues, the game's shared module registry, or a unique validated GC table. The fallback checks stable item IDs, names, and category fields from the dump; a future game update can change these or private handlers. The script stops with a diagnostic when definitions are missing or ambiguous.

The original instructions and screenshot were read without modification.

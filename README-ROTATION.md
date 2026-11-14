# Full Rotation guide

For **Claris Growblox 0.1.27**. Full Rotation manages every world in your **Planting** farm list using your saved PNB setup and one harvest Display Box per farm.

The usual flow is **fill planting space → PNB while trees grow → harvest a ready farm → transfer its blocks and seeds → replant that farm → repeat**. Planting and ready harvests take priority over breaking. A full farm skips planting even when seed storage contains thousands of seeds.

## Contents

- [Requirements](#requirements)
- [Save the PNB layout](#save-the-pnb-layout)
- [Set the planting seed and farm list](#set-the-planting-seed-and-farm-list)
- [Save each farm's harvest box](#save-each-farms-harvest-box)
- [Choose Fist or Dear John Tractor](#choose-fist-or-dear-john-tractor)
- [Save configuration and start](#save-configuration-and-start)
- [Task priority and examples](#task-priority-and-examples)
- [Routes, drops, and storage](#routes-drops-and-storage)
- [World changes, automatic execution, and recovery](#world-changes-automatic-execution-and-recovery)
- [Discord work reports and failure pings](#discord-work-reports-and-failure-pings)
- [Export to another device](#export-to-another-device)
- [Multiple accounts](#multiple-accounts)
- [Troubleshooting](#troubleshooting)
- [Common questions](#common-questions)
- [Push this guide to GitHub](#push-this-guide-to-github)

## Requirements

- The current GitHub loader and an executor providing the required game, movement, and file functions.
- One selected crop block, with its matching seed used for planting.
- A PNB world with separate seed and block Display Boxes in the layout below.
- Accessible farm worlds with reachable supported rows.
- One reachable harvest Display Box saved separately for every listed farm.
- Matching seeds in your backpack or PNB seed box, existing crop to harvest, or PNB blocks that can produce seeds.
- Your own Dear John Tractor if you choose Tractor harvesting.

Keep the **PNB/seed-storage world outside the farm list**. For example, use `BREAK` for PNB and seed storage, with `FARM1, FARM2` as the farms.

Run the GitHub loader shown under [Save configuration and start](#save-configuration-and-start) to open the setup tabs. Keep tasks Off while saving your initial setup.

Rotation enters worlds directly by name. Linked doors are required for standalone **Moving Drops**, but you do not need to save them for Full Rotation. Keep entrances, side platforms, and access to boxes clear.

## Save the PNB layout

1. Enter the breaking world and arrange five tiles on the same row:

   ```text
   Seed Display Box | Empty tile | PNB spot | Empty tile | Block Display Box
   ```

2. Provide a solid surface to stand on at the PNB spot. Leave the foreground tile directly above the player clear; PNB places and breaks one selected block there.
3. Put **only matching seeds** in the left Display Box and **only the selected blocks** in the right Display Box. These PNB boxes must remain separate.
4. On **Place & Break**, select **Block to farm**. Carry some of the block if needed for the inventory choices, then use **Refresh inventory choices**.
5. Stand at the middle PNB spot and press **Save PNB spot and matching boxes**. Check the saved world and coordinates. The individual **Save block storage** and **Save seed storage** controls can also save their respective boxes while you stand beside them.

For a PNB spot at tile `10, 8`, the seed box must be `8, 8`, the block box `12, 8`, and the block being broken occupies `10, 7`. The two empty tiles between the player and boxes are part of the required layout.

Leave the standalone **Place & Break** toggle Off while running Full Rotation. Rotation manages PNB itself.

## Set the planting seed and farm list

1. On **Planting**, enter **Dirt farm worlds (in order)**, separated by commas. Example:

   ```text
   FARM1, FARM2, FARM3
   ```

2. After selecting the block and saving PNB, open **Full Rotation** and press **Use PNB seeds for planting**.
3. Check Planting: the matching seed should be selected, the storage world should be your PNB world, and the planting seed Display Box should be the saved left PNB box.

**You do not need to select “Seed to plant” separately after pressing this button.** It sets the matching seed and copies the PNB seed box into planting storage. Existing seeds in the left PNB box become planting stock. You do not need a separate planting seed box inside each farm.

If you change the block or move/resave the PNB seed box, press **Use PNB seeds for planting** again. Rotation requires the planting seed to match the selected block and planting storage to be the same box as the left PNB seed box.

World names are normalized, and duplicate names are removed while keeping order. Every listed world needs its own harvest box. Remove worlds this account should not farm. Leave the standalone **Plant seeds** toggle Off.

## Save each farm's harvest box

1. Visit the first world in the Planting list.
2. Choose a reachable Display Box for its harvested blocks and matching seeds.
3. Stand beside it, open **Full Rotation**, and press **Save this farm's harvest box**.
4. Repeat in every listed farm.
5. Check **Farm storage saved per world**. Every world should show its box coordinates instead of a missing-box prompt.

The saved point includes the box tile and the standing position used to access it. Save from a reachable position with permission to use the box. It can start empty or contain matching blocks and seeds together; keep unrelated items out.

The existing **Save Farm storage** controls also remember the box for that world. Saving a box in `FARM2` does not replace `FARM1`'s entry in the rotation map. Resave the affected world's box if you move it.

## Choose Fist or Dear John Tractor

Choose the harvesting method on **Harvest Drops** before starting rotation.

| Method | Behavior | Requirements |
| --- | --- | --- |
| **Fist** | Walks supported rows and hits ripe selected trees before collecting their drops. | Tile access and a reachable route. |
| **Dear John Tractor** | Equips the tractor for the harvesting pass and drives over ripe trees using its native harvesting action. | Your own tractor available to equip, reachable rows, and a farm containing only the selected crop. |

Tractor mode rejects a farm containing another seed type because the vehicle can harvest other crops it touches. Choose Fist if other crops are present; rotation still targets the selected crop.

The script removes harvesting equipment for planting, travel, and collection, and restores previous footwear when its equipment scope ends. Keep side platforms and row paths accessible.

## Save configuration and start

1. Finish PNB, seed selection, the farm list, every harvest box, the harvest method, and optional Discord settings.
2. With tasks stopped, use **Configurations → Save profile / Save as**. Choose a useful name such as `Main Account Farms`.
3. Start with the current GitHub loader:

   ```lua
   loadstring(game:HttpGet("https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"))()
   ```

4. If needed, load the saved profile after connecting. Check the settings. Starting from the PNB world is convenient; rotation can travel from another accessible world too.
5. On **Full Rotation**, turn **Continuous full rotation** On. Leave the standalone Planting, Harvest Drops, Moving Drops, and Place & Break task toggles Off.
6. Watch the first complete cycle and a world change. Check planting results, storage counts, harvesting reach, and recovery before leaving it running.

**No extra named-profile save is needed after turning rotation On.** The profile saves your setup; starting rotation creates and updates its running checkpoint. Current settings also save automatically to the account's local session before task/world transitions.

Use the Full Rotation tab to start rotation, not the standalone Place & Break toggle. Stop tasks before changing the crop, farm assignments, saved locations, or named profile.

## Task priority and examples

A fresh run begins with a planting pass over the full list. It fills empty supported tiles and skips occupied tiles. It records farm maturity timers during those visits, avoiding a second startup visit just to read growing-tree timers.

| Condition | Rotation behavior |
| --- | --- |
| Full farms with growing trees and seeds still in storage | Skips planting and runs PNB while the trees grow. |
| Full farms with ripe trees | Skips occupied planting tiles and processes ready harvests before breaking existing PNB stock. |
| Empty supported planting spaces with seeds available | Fills them during the initial planting pass, before the harvest/wait flow. |
| A farm becomes ready during PNB | Finishes the current block and pickups, stores unused inventory, then leaves for harvest. |
| A farm has been harvested | Transfers its blocks/seeds and replants that farm before more PNB. |
| A later farm matures first | Uses maturity deadlines to choose it instead of waiting at an earlier growing farm. |
| PNB blocks run out while trees grow | Waits in the breaking world for harvest due or new blocks, without repeated growing-farm visits. |
| Planting seed stock runs out | Existing crop or PNB blocks can replenish seeds; available stock lets unfinished planting resume. |
| No eligible crop, planting stock, or PNB blocks can provide work | Pauses with an error instead of endlessly repeating empty travel. |

For the tree-maturity wait, a farm is ready when its remaining matching growing trees have matured. The script uses planting times and growth duration, then confirms maturity after entering the farm. Harvested items already in its box or loose matching drops can also provide collection work before all current trees mature.

The list order is the planting order and resolves equal deadlines. Harvest scheduling can choose a later farm that matures sooner. A farm's replant takes priority after its harvest, before processing another farm. A completed rotation cycle counts the processed farm pass; it does not mean the PNB box was emptied.

### Example: two ripe farms, 5,000 seeds, and 11,000 PNB blocks

If both farms are full of ripe trees, the initial planting pass skips their occupied tiles. Rotation harvests the first ready farm, transfers its blocks/seeds, and replants it using PNB seed stock. It then processes the second ready farm the same way. Existing PNB stock is broken while the replanted farms grow.

Having 5,000 seeds does not make it plant over trees. Having 11,000 blocks does not make it finish all PNB work before a ready harvest. If those farms have empty supported spaces, those spaces can be planted during the initial pass before harvesting starts.

### What pausing PNB means

Rotation switches tasks between complete place/break/pickup iterations. It finishes the current block and its pickups, checks that requests have settled, and returns unused backpack blocks/seeds to their dedicated PNB boxes before leaving.

A slow current game request or pickup can delay that boundary. PNB also checks after refilling blocks so a slow withdrawal does not start another placement after harvest is due. It does not wait for the entire block box to be emptied.

## Routes, drops, and storage

The route starts at the **top-left supported row**, crosses right, descends to the next supported row, crosses left, and continues alternating. Each new farm starts from the left.

From v0.1.26, planting places seeds while walking along that row. It uses the native seed helper and confirms up to **eight seeds per batch** against server inventory and all planted tiles. It briefly stops for confirmation, row turns and obstacles, and eases movement if it would pass an empty tile before the next placement is allowed. Missed cells use precise movement as a fallback. **Settings → Delay after placement** controls planting timing: default 0.2 seconds, minimum 0.15. Existing profiles retain their saved delay; you can lower a slower value and save the profile. The same behavior applies to the initial planting pass and replanting after harvest.

Each attempted tile is saved before placement. After an interruption, rotation checks the saved batch against the live tiles and server seed count before continuing. Accepted seeds are counted once, empty unaccepted cells can be retried, and conflicting evidence pauses with a diagnostic. Older single-seed planting checkpoints remain supported. No new setup or toggle is required for moving planting.

For worlds with many scattered drops, enable **Settings → FPS booster: hide floating drops**. It hides loose block, seed and gem sprites and stops their bobbing/pop visuals while automation keeps using their pickup data. Display Boxes remain visible. You can toggle it during rotation; it saves to the session and matching task checkpoints without changing pending cargo or progress, and applies after supported world-change resumes. Save the named profile to retain it when loading that profile or exporting to another device. New drops are hidden on a periodic scan, roughly once per second. Normal Stop keeps the boost active; switching it Off or unloading restores surviving visuals. Harvest's collection scope stays selected blocks and matching seeds; PNB also collects nearby gems. Live FPS improvement depends on the device and native client workload.

- Planting skips rows without empty supported planting tiles.
- Harvesting skips rows without ripe selected trees or matching drops to collect.
- The next supported row may be more than one tile below the previous row.
- Keep edge platforms and routes clear so the script can reach each row.
- Occupied tiles, unsupported air, access-denied cells, and unreachable planting cells are skipped. A completed scan does not guarantee every dirt tile was planted; check skipped counts in Recent activity.

Harvesting breaks the selected ripe trees before the drop-collection pass. It collects matching **blocks and seeds** and puts them in that farm's Display Box. Unrelated drops are outside harvest collection.

| Storage | Contents | Purpose |
| --- | --- | --- |
| Farm harvest Display Box | Selected blocks and matching seeds together | Stages harvested items for transfer. |
| Left PNB Display Box | Matching seeds only | Supplies planting and stores harvested/PNB-produced seeds. |
| Right PNB Display Box | Selected blocks only | Supplies PNB and receives transported blocks. |

Mixed farm-box withdrawals can return seeds as well as blocks. Transfer keeps up to **200 matching seeds in inventory** during block trips, returns held seeds to the same farm box after its blocks are moved, and then transports farm seeds to the left PNB planting-stock box. PNB-produced seeds go there too.

The 200 amount is the held inventory stack, **not a limit on storage stock**. Thousands of stored items are processed through multiple trips. Keep inventory space available for the crop, seeds, and equipment.

**Respawn to Farm storage** is optional for harvest return travel. It uses the game's respawn action when available and appropriate; saving a box does not set the game's respawn destination to that box. Nearby returns use walking, and missing respawn hooks also use walking. Check harvest-return diagnostics and the route if respawn does not bring you near storage.

## World changes, automatic execution, and recovery

### Setup files and running checkpoints

| Saved data | Contents | Purpose |
| --- | --- | --- |
| Named profile | Crop/seed selection, worlds, boxes/standing positions, timing options, harvest method, and webhook settings | Reuse the setup for a fresh run. |
| Local session | Current configuration and profile name, including unsaved setting changes | Restore this account's settings after reload. |
| Rotation checkpoint | Configuration/profile, phase, farm, cycle, completed farms, deadlines, planting progress, transfer cargo, and pending storage actions | Resume interrupted work on this account/device. |

The checkpoint is `ClarisGrowblox/rotation-resume.json`. It saves before world changes and phase transitions, during planting/storage progress, and periodically while running. Deadlines use **server time**, so restarting executor uptime does not restart tree growth.

### Automatic loader execution

Use the project's GitHub **loader.lua**, shown above, so the script knows which loader to queue. When Delta provides `queue_on_teleport` or a supported equivalent, it queues that loader with automatic resume before moving worlds.

After a server change resets the script, the queued loader connects, restores the saved rotation's configuration/profile, and resumes its phase. This includes PNB during growth waits and unfinished replanting. Each fresh script registers execution again for the next world change. Rotation recovery takes priority over standalone PNB, Planting, and Moving Drops recovery.

You do not need to load a profile, resave boxes, or turn rotation On after every supported teleport. Coordinates stay attached to their saved worlds.

If teleport queuing is unavailable or execution fails, run the loader after arrival and press **Full Rotation → Resume saved rotation**. Resume restores the checkpoint's configuration. Use Resume for interrupted work; turning the main toggle On starts a fresh rotation instead.

Local config/checkpoint files must remain on the device. An app reset that deletes executor files cannot recover files that no longer exist.

### Stop, reload, and errors

- Intentional Stop or turning rotation Off clears its automatic-resume checkpoint. Items and saved settings remain; start a fresh rotation afterward.
- An unexpected reset or a task error can leave a checkpoint available.
- Read-only world/respawn interruptions can recover when **Rejoin world and return to PNB** is On. Genuine layout, access, or storage faults still need correction.
- A confirmed interrupted seed placement can be reconciled using the live tile and backpack, avoiding planting it twice.
- An ambiguous storage withdrawal/deposit is not automatically replayed. Inspect where the items ended up before clearing saved rotation and starting again.
- Checkpoints expire six hours after their last update. Active rotations refresh them; this is not a six-hour run limit.
- Checkpoints belong to their Roblox account. Export/import copies setup to another account, which must start a new run.

Session counters reset after reload. Growth timers, stored items, saved setup, and running progress are separate from those counters.

## Discord work reports and failure pings

1. In Discord channel settings, choose **Integrations → Webhooks**, create a webhook, and copy its URL.
2. In **Discord Webhook**, paste it into **Discord webhook URL**.
3. Set **Send every (minutes)**, for example `5`. The range is 1–1440 minutes, including decimals such as `1.5`.
4. Enable **Automatic webhook reports** for timed progress and completed-task/rotation-cycle reports.
5. Enable Discord **Developer Mode**, use **Copy User ID** on your profile, and paste it into **Discord user ID to ping on failure**. Use your 17–20 digit user ID, not a username, role ID, or channel ID. A copied user mention is also accepted.
6. Leave **Failure alerts** On. Failures ping the saved user even when Automatic webhook reports is Off. A blank ID gives alerts without a ping.
7. Press **Send stats now** and check the channel and **Webhook status**. This checks stats delivery without testing a failure ping.
8. Save the named profile while tasks are stopped, then start rotation.

Reports identify the Roblox player, world, profile, harvest method, current farm, phase, and cycle. Totals include trees harvested, blocks/seeds collected and stored, seeds planted, blocks moved/broken, gems collected, and completed rotations. Totals describe the loaded script session and reset after reload.

Timed/manual reports query level and gem balance when available. Failure/completion reports capture progress at the event and skip those game-stat queries, so a disconnected game cannot hold up an alert. Box counts use current client data; other-world boxes show unavailable, and reports do not travel to read them.

Only failures ping the saved user. Normal Stop, successful completion, growth waits, and successful recovery do not ping. Task, startup, and automatic-resume errors can send alerts.

Delivery does not stop farming. Alerts wait behind an outstanding Discord post, respect rate limits, and retry other delivery errors up to three times. A delayed successful reply is acknowledged without another ping. Check Webhook status for delivery errors and queued reports.

Changing webhook settings or loading/importing config clears old queued reports. Queued alerts do not survive reload or transfer through exports. The URL, Discord ID, interval, and toggles do transfer. Keep exported configs private because they contain the webhook URL.

## Export to another device

1. On the source emulator/device, use **Configurations → Export config**. Export includes current unsaved setting changes and works during a task.
2. Copy the complete text from the clipboard or **Configuration text** field to the cloud phone.
3. Run the current loader on the destination and stop active tasks. Use the current version on both devices for the same features.
4. Paste into **Configuration text**. Optionally set **Import as profile**; blank keeps the exported name.
5. Press **Import config**. Import applies and saves the profile and a session for the destination account. A same-name existing profile is backed up.
6. Check crop, seed source, PNB boxes, farm list, harvest boxes, and webhook settings. Start Continuous full rotation for a new run.

Export also writes `ClarisGrowblox/exports/<profile>.json` when file functions are available. For file transfer, copy it to the destination, enter its local path in **Configuration file path**, and press **Import config file**. Plain existing profile JSON files are supported too. If clipboard/file access fails, the export text remains in Configuration text.

Import keeps tasks Off and clears old local recovery checkpoints. It transfers setup, **not inventory, live cargo, queued alerts, counters, or running progress**. An unfinished emulator block trip cannot resume on a cloud phone using a config export. See the [configuration transfer instructions](README.md#export-from-an-emulator-and-import-on-a-cloud-phone) for more context.

## Multiple accounts

Another Roblox account can import a config, but the saved coordinates still point to the original tiles. Moving an account to a different PNB layout alone does not update coordinates.

For each account:

1. Import the shared setup or create a profile.
2. Save its own PNB spot and matching left/right boxes.
3. Select its crop and press Use PNB seeds for planting again.
4. Enter its assigned farm list.
5. Save a harvest box in each assigned farm.
6. Check webhook settings and save that account's named profile.
7. Start a fresh rotation.

Use separate farms and storage for simultaneous accounts. The script does not coordinate shared harvesting, planting, or withdrawals. Each account needs world access and its own tractor for Tractor mode. Update linked doors too if using standalone Moving Drops.

Accounts can use the same webhook and ping the same Discord user; reports identify the player/profile. Account-bound sessions/checkpoints remain separate from portable config. Another account's running checkpoint is rejected.

## Troubleshooting

| Symptom/message | What to check or do |
| --- | --- |
| Missing PNB spot or storage | Resave the middle spot and left/right boxes on Place & Break, all in the same world. |
| Layout error | Put boxes two tiles left/right of the PNB spot on the same row; clear the tile above the player. |
| Seed mismatch / use PNB seed storage | Select the correct block, save the left PNB box, and press Use PNB seeds for planting again. |
| Missing method 'Set' when using PNB seeds or loading config | Update to v0.1.25, push the rebuilt release, rerun the same GitHub loader, then retry. This fixes the dropdown refresh and resets the old UI lock. Check that the farm list and seed settings are displayed correctly. |
| Planting hook unavailable before starting | Farming hooks are deferred during the initial connection. They attach when Planting or Full Rotation starts. If task startup itself fails, copy diagnostics. |
| Game connection still takes time after a reload | v0.1.26 indexes game objects once and reduces forced frame waits. Push the complete rebuilt release and rerun the loader. Copy diagnostics shows discovery time/yields/checks; executor GC/debug calls and world loading still affect startup. |
| Planting pauses while crossing a row | Short batch-confirmation and timing pauses are expected. Check Delay after placement for a slow saved value. Obstacles or missed cells use precise movement. A failed batch confirmation pauses rather than continuing to spend seeds. |
| Floating blocks, seeds and gems are invisible | FPS booster hides their visuals. Automation can still collect them. Turn it Off in Settings for manual play; Display Box contents stay visible. |
| FPS remains low with many drops | Enable FPS booster and check Copy diagnostics for hidden sprite count/errors. Native drop processing and world loading still cost time; the booster does not remove server items. |
| Missing farm box | Visit the exact named farm and save its reachable harvest box. Check every listed world. |
| Full farm is not planting | Occupied tiles are intentionally skipped. Growing trees lead to PNB; ripe trees lead to harvest. |
| Some trees are ripe but the farm is still growing | The maturity wait accounts for remaining matching growing trees too. |
| Empty PNB storage while trees grow | Waits in the PNB world; harvest due or new blocks can provide the next work. |
| Empty seed box | Add matching seeds, wait for existing crop, or provide PNB blocks that produce seeds. No productive work causes a pause. |
| Tractor missing / another crop present | Supply the tractor and use a single-crop farm, or choose Fist. |
| Refused pickup, unreachable row, skipped planting cells | Check tile/box permissions, standing positions, platforms, obstacles, and inventory space; copy diagnostics. |
| Respawn does not reach the saved box | Saving the box does not change the game's respawn point. Check respawn destination, the route, and return diagnostics. |
| Game loads after world change but script does not | Check teleport-queue support; rerun the GitHub loader and use Resume saved rotation. |
| Config or run missing after reload | Check the account/device's local files. Import restores setup with tasks Off, not running progress. |
| Interrupted storage request / pending deposit | Review backpack, source/destination boxes, and pending requests before clearing saved rotation; do not blindly replay the transfer. |
| Checkpoint expired or belongs to another account | Use the correct account or import config and start fresh after checking items. |
| Discord report missing | Check URL, toggles, executor HTTP support, Webhook status, and rate limits; use Send stats now. |

For task errors, use **Settings → Copy diagnostics** and keep the exact error, world, profile, phase, and relevant box contents. After correcting a cause, resume an available checkpoint if it has no ambiguous storage action.

For ambiguous storage, inspect where items ended up before **Clear saved rotation** and a fresh start. Clearing progress does not move or restore inventory.

Offline checks cover scheduling and recovery logic. Live server acceptance, geometry/access, executor files, teleport execution, and Discord delivery still need device verification. Watch one complete cycle and a world change before an unattended run.

## Common questions

**Do I select Seed to plant on Planting?**

For rotation, select the block, save PNB, and press Full Rotation → Use PNB seeds for planting. That sets the matching seed and storage. Still enter the farm list on Planting.

**Do I need a seed box in each farm?**

No. Planting uses the left PNB seed box. Each farm needs its harvest box for matching blocks and seeds together.

**Do I save config after turning rotation On?**

Save the named setup while stopped, then turn rotation On. Starting creates the running checkpoint automatically; no additional profile save is needed.

**Do I turn rotation On in the breaking server?**

Use the Full Rotation tab. Starting in PNB is convenient, but rotation can travel from another accessible world. Leave standalone Place & Break Off.

**Does moving worlds erase my boxes/config?**

Saved setup remains in local files. The queued loader restores the rotation on supported teleports; otherwise rerun the loader and use Resume saved rotation.

**Will it keep planting a full farm because seeds remain?**

No. Occupied rows are skipped. Growing trees remain until ready to harvest.

**Will it finish all 11,000 PNB blocks before harvest?**

No. A ready farm interrupts PNB after the current block and pickups settle. The harvested farm is replanted before more breaking.

**Does empty seed storage stop rotation immediately?**

It stops that planting attempt. Existing crop or PNB blocks can replenish stock and let planting resume. No productive work causes a pause.

**Can a saved profile resume a stopped run?**

A profile restores setup for a fresh run. Intentional Stop clears running progress. Resume saved rotation uses a checkpoint left by an interruption/error.

**Can it run 24/7?**

It repeats until stopped or a terminal fault occurs, with anti-AFK and supported recovery available. Keep the device/executor active, world access valid, storage usable, and routes clear. Unresolved game/executor faults still require attention.

## Push this guide to GitHub

To commit and push this guide-only update from PowerShell:

```powershell
cd "F:\VSCode\Luau\Claris Growblox Autofarm\logic"
git add README-ROTATION.md
git commit -m "Expand full rotation setup and recovery guide"
git push origin HEAD
```

Future script changes need a rebuild and relevant checks before publishing. Push the updated loader, manifest, bundle, and new immutable release folder together. A guide-only edit does not need a rebuild. Keep using the same GitHub loader command after updates.

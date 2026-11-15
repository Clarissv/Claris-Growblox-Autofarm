# Full Rotation guide

For **Claris Growblox 0.1.43**. Full Rotation manages every world in your **Planting** farm list using your saved PNB setup and one harvest Display Box per farm.

For coordinated accounts on one cloudphone, use the separate **Botting** tab and [Botting guide](README-BOTTING.md). Its imported layout is shared, while each account chooses a private role and breaker spot. It supports BNS boxes in different positions, shared farm jobs and paired block/seed transfers. The steps below describe the existing Full Rotation mode.

The usual flow is **fill planting space → collect existing farm stock if needed → PNB while trees grow → harvest a ready farm → transfer its blocks and seeds → replant that farm → repeat**. Planting and ready harvests normally take priority over breaking. When the planting seed supply is exhausted, rotation finishes the full PNB block stock first. A full farm skips planting even when seed storage contains thousands of seeds.

## Contents

- [Requirements](#requirements)
- [Save the PNB layout](#save-the-pnb-layout)
- [Set the planting seed and farm list](#set-the-planting-seed-and-farm-list)
- [Save each farm's harvest box](#save-each-farms-harvest-box)
- [Choose Fist or Dear John Tractor](#choose-fist-or-dear-john-tractor)
- [Replant during harvest](#replant-during-harvest)
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

Rotation and standalone **Moving Drops** enter worlds directly by name; neither requires linked doors. Keep entrances, side platforms, and access to boxes clear. Standalone Moving Drops now needs only its Farm and destination Display Boxes, with a Blocks/Seeds choice. Full Rotation always transfers harvested blocks to its dedicated PNB block box and seeds to its PNB seed box, independently of the standalone choice or destination. See [Moving Drops setup](README.md#set-up-moving-drops) for manual transfers.

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

Different accounts can use different world geometry and PNB coordinates. Each world needs the five-tile station and a reachable route from its entrance to the player and both saved box standing positions. A raised room reached by jumping onto a side platform is supported. From v0.1.30, the planner handles the tight jump clearance when that platform sits just below a low ceiling. Closed access, blocked corridors and missing support can still prevent travel.

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

From v0.1.32, a tree-harvesting pass starts only when **every tree of the selected crop in that farm world is fully grown**. This automatic check applies to Fist and Tractor and includes trees outside the detected walking rows. One growing matching tree makes rotation wait for that world's latest maturity deadline, process other ready farms, and continue PNB while it waits. From v0.1.36, existing loose drops and stored farm harvest can be collected and transferred during this wait, with growing trees left untouched. Missing tree growth data pauses with diagnostics instead of assuming maturity.

Rotation checks again before starting a new harvest after a reload, world change or seed refill. Combined planting begins only after the farm passes this check. From v0.1.35, an already approved pass saves its tree-work or collection stage across retries and reloads. Its newly planted trees do not trigger another maturity wait before the remaining trees, Fist cleanup and loose-drop collection finish. Once that pass ends, the next harvest again requires the whole farm to mature. Standalone **Collect harvest** stops with a waiting status and leaves the trees and drops untouched if the world is immature; start it again when ready, or use Full Rotation for automatic waiting. **Copy diagnostics → Farm maturity check** shows the last checked world's ripe/growing counts; **Saved harvest pass** shows the current rotation harvest stage. No new toggle or configuration is required.

| Method | Behavior | Requirements |
| --- | --- | --- |
| **Fist** | Walks supported rows and hits ripe selected trees before collecting their drops. | Tile access and a reachable route. |
| **Dear John Tractor** | Drives each row once using native harvesting, collects nearby gems during the pass, then clears missed ripe trees with Fist from a reachable lower position. | Your own tractor available to equip, reachable rows, Fist hooks, and a farm containing only the selected crop. |

Tractor mode rejects a farm containing another seed type because the vehicle can harvest other crops it touches. Choose Fist if other crops are present; rotation still targets the selected crop.

From v0.1.31, the Tractor continues to the end of a row when it misses trees. On the next reachable lower row it briefly removes the Tractor and punches the missed trees above, then continues forward. An otherwise empty lower row can be visited for cleanup. If no lower position is reachable, it uses Fist on the original row with the Tractor off. Growing trees stay planted. This behavior applies to standalone harvesting and Full Rotation without another toggle.

The script removes the Tractor for Fist cleanup, travel, the later block/seed collection pass and standalone planting, and restores previous footwear when its equipment scope ends. Nearby gems are collected with the Tractor still equipped during harvesting. Refill trips and the return to an unfinished row use normal walking speed, including when a world load restores worn equipment. The Tractor equips only after reaching the harvesting row entry. Combined harvest planting keeps it equipped while planting behind it. Keep side platforms and row paths accessible.

## Replant during harvest

Enable **Full Rotation → Replant during harvest** while tasks are stopped, then **Configurations → Save profile / Save as**. Choose Fist or Dear John Tractor on Harvest Drops. This option defaults to Off for existing profiles and applies to Full Rotation; standalone harvesting still breaks trees before collecting blocks and seeds, with gems collected during the Tractor pass.

With this setting On:

1. Before a ready farm's harvest, rotation fills available backpack seed room from the saved left PNB seed box. If the box is empty, it uses any carried seeds and still completes harvesting.
2. The Tractor follows the same top-left zigzag pass and plants cleared supported tiles behind it while moving. It gives harvested tiles a short confirmation window and observes the placement delay. Growing trees are skipped by native Tractor harvesting.
3. Missed trees are punched from below where reachable. The script immediately plants that cleared upper tile from the same standing position if seeds are available and native placement allows it. It leaves a denied or unreachable placement for the later replant step. Fist mode also replants after each confirmed harvest.
4. Carried seeds running out ends combined planting for this pass. Harvesting continues forward, collecting nearby gems during the Tractor pass, and finishes its missed-tree cleanup before collecting blocks, seeds and remaining gems. It does not leave the row for a storage refill.
5. Collected blocks, seeds and any unused carried seeds go into the farm box. Rotation checkpoints the collection stage before storage travel, so movement retries or reloads resume the sweep with the Tractor off, even though replacement trees are growing. It finishes collecting and storing the selected drops before transferring blocks to PNB and returning seeds to PNB seed storage. Its normal replant step refills automatically and plants any remaining empty spaces, skipping trees already replanted during harvest.

For example, with 600 ripe trees and 200 carried seeds, up to 200 cleared positions can be replanted during harvesting. Rotation harvests the remaining trees, collects/transfers the drops, then refills and plants the remaining spaces automatically. With enough carried seeds to fill the farm, the later replant scan skips its occupied spaces.

This setting is saved in the profile, export/import and rotation checkpoint. Seed batches contain at most eight placements and are saved before each attempt. After an interruption, rotation reconciles the seed count and farm tiles before continuing. Ordinary unconfirmed seed placements are skipped and retried from below where reachable; an interrupted storage withdrawal, failed inventory request or seed count change outside the attempted batch still pauses with diagnostics. Live speed depends on the client, placement reach and game response time; batch confirmations, Fist cleanup and row turns can still require short stops.

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
| Full farms where every selected tree is ripe, with planting seeds available | Skips occupied tiles and processes ready harvests before breaking existing PNB stock. |
| A farm has both ripe and growing selected trees | Waits for every selected tree before breaking trees; can collect existing drops and transfer stored farm stock to PNB during that wait. |
| PNB is empty but farms still have loose drops or stored blocks/seeds | Checks waiting farms once, collects existing harvest with the Tractor off, transfers it to PNB, and resumes breaking while trees grow. Saved future growth timers do not hide this stock. |
| Empty supported planting spaces with seeds available | Fills them during the initial planting pass, before the harvest/wait flow. |
| A farm becomes ready during normal PNB | Finishes the current block and pickups, stores unused inventory, then leaves for harvest. |
| A farm has been harvested | Transfers its blocks/seeds and replants remaining empty spaces before more PNB. With Replant during harvest On, some or all tiles were already replanted during the harvest pass. |
| A later farm matures first | Uses maturity deadlines to choose it instead of waiting at an earlier growing farm. |
| PNB blocks run out while trees grow | Waits in the breaking world for harvest due or new blocks, without repeated growing-farm visits. |
| Planting backpack and seed storage run out | Enters `drainPNB`: breaks all remaining PNB blocks, stores produced seeds, then resumes planting/harvesting. Ripe farms wait during this drain. |
| Seed box refills while `drainPNB` is active | Continues draining PNB. New seeds do not interrupt it. |
| PNB drain finishes | Confirms no inventory/storage blocks or placed PNB block remain, settles pickups and stores seeds, then returns to normal farm scheduling. |
| No eligible crop, planting stock, or PNB blocks can provide work | Pauses with an error instead of endlessly repeating empty travel. |

For the tree-maturity wait, a farm is ready when its remaining matching growing trees have matured. The script uses planting times and growth duration, then confirms maturity after entering the farm. Harvested items already in its box or loose matching drops can provide collection/transfer work during the wait; this does not authorize breaking or replanting the growing trees.

From v0.1.36, when PNB has no blocks, rotation checks each unfinished waiting farm once for loose or stored harvest even if its saved maturity deadline is still in the future. Collection-only recovery keeps the Tractor off, collects blocks/seeds/gems, stores the crop, transfers blocks and seeds to PNB, and resumes the original maturity schedule. The farm remains unfinished until its actual harvest/replant completes. These supply checks and collection/transfer progress survive supported world-change reloads. If every farm has been checked and no stock exists, rotation waits in PNB instead of repeating empty drains or server changes. New PNB stock starts another supply cycle; mature-farm deadlines still interrupt breaking normally.

The list order is the planting order and resolves equal deadlines. Harvest scheduling can choose a later farm that matures sooner. A farm's replant normally takes priority after its harvest, before processing another farm. Seed exhaustion temporarily gives the full PNB drain priority. A completed rotation cycle counts the processed farm pass; it does not mean the PNB box was emptied.

### Example: two ripe farms, 5,000 seeds, and 11,000 PNB blocks

If both farms are full of ripe trees, the initial planting pass skips their occupied tiles. Rotation harvests the first ready farm, transfers its blocks/seeds, and replants it using PNB seed stock. It then processes the second ready farm the same way. Existing PNB stock is broken while the replanted farms grow.

Having 5,000 seeds does not make it plant over trees. Having 11,000 blocks does not make it finish all PNB work before a ready harvest. If those farms have empty supported spaces, those spaces can be planted during the initial pass before harvesting starts.

### When seed supply runs out

The trigger is an empty planting backpack **and** an empty left PNB seed box. Seeds already carried for planting can still be used. If the last seeds finish a farm exactly, rotation checks the box before scheduling another farm, so exhaustion is detected even without a failed refill. No new toggle is required.

For example, with no seeds left and 11,000 PNB blocks, rotation stays in PNB until all 11,000 blocks and returned blocks are consumed. It stores produced seeds without restarting planting after the first few seeds. Already-ripe farms also wait. After the drain, ready harvests and unfinished planting can resume using the accumulated stock. If PNB is already empty, it checks waiting farms for existing drops and stored harvest. Growing trees still wait for maturity, but their already harvested stock can refill PNB.

`checkSeeds` and `drainPNB` are saved phases. Reloading or a supported world teleport does not cancel an active drain when its seed box has refilled. Normal Stop still stops the task and clears its automatic-resume checkpoint. An interrupted storage request still pauses for inspection.

### What pausing PNB means

Rotation switches tasks between complete place/break/pickup iterations. It finishes the current block and its pickups, checks that requests have settled, and returns unused backpack blocks/seeds to their dedicated PNB boxes before leaving.

A slow current game request or pickup can delay that boundary. PNB also checks after refilling blocks so a slow withdrawal does not start another placement after harvest is due. During normal PNB it does not wait for the entire block box to be emptied. During the depleted-seed drain it finishes that box and all returned blocks before leaving.

## Routes, drops, and storage

The route starts at the **top-left supported row**, crosses right, descends to the next supported row, crosses left, and continues alternating. Each new farm starts from the left.

For drop collection, each occupied row goes in **one direction**: left → right, down to the next occupied row, right → left, and repeat. Empty rows are skipped without changing the side where the previous row finished. The script does not schedule a return sweep along a completed row. If a full backpack needs a storage trip, it resumes at the next remaining drop in that row's saved direction.

From v0.1.26, planting places seeds while walking along that row. It uses the native seed helper and confirms up to **eight seeds per batch** against server inventory and all planted tiles. It briefly stops for confirmation, row turns and obstacles, and eases movement if it would pass an empty tile before the next placement is allowed. Missed cells use precise movement as a fallback. **Settings → Delay after placement** controls planting timing: default 0.2 seconds, minimum 0.15. Existing profiles retain their saved delay; you can lower a slower value and save the profile. The same behavior applies to the initial planting pass and replanting after harvest.

Each attempted tile is saved before placement. After an interruption, rotation checks the saved batch against the live tiles and server seed count before continuing. Confirmed seeds are counted once. From v0.1.33, an ordinary rejected or unconfirmed tile is skipped for that row, allowing the rest of the farm to continue. Unexplained counts outside the attempted batch and failed inventory requests still pause with a diagnostic. Older single-seed planting checkpoints remain supported. No new setup or toggle is required for moving planting.

When filling the next reachable lower row, planting retries the missed upper tile from below once, without walking back to the upper row. An already full lower row can also provide this approach. Native reach, access and supported dirt checks still apply. A second refusal or inaccessible approach leaves that tile skipped for this farm pass; the next planting cycle can try it again. Retry positions are saved across seed refills and world-change checkpoints. Combined harvest planting can retry from a lower harvesting row; the normal replant phase fills other remaining spaces.

Full Rotation also retries transient walking failures such as **Returning to the saved position timed out**. It stops movement briefly and plans a fresh route from the current position, with up to three immediate attempts. If those attempts still time out, it saves the current phase, waits **five seconds**, and retries with rotation still On. A genuine missing route, unsettled requests or ambiguous planting/storage state remains a protected failure. **Copy diagnostics** includes Planting recovery and Navigation recovery; Recent activity shows skipped tiles and route retries. No toggle is required for these recoveries, and normal Stop still cancels them.

From v0.1.28, a refill or saved resume keeps moving planting on the unfinished row. When entry leaves the avatar below that row or past its next empty tile, it walks to the next planting position before continuing the saved zigzag direction. It does not replant occupied tiles or switch the remainder of that row to per-tile planting because it arrived through the other side. Navigation, batch confirmations and genuine obstacles can still require pauses. This applies to standalone Planting, the initial rotation pass and replanting after harvest.

For worlds with many scattered drops, enable **Settings → FPS booster: hide floating drops**. It hides loose block, seed and gem sprites and stops their bobbing/pop visuals while automation keeps using their pickup data. Display Boxes remain visible. You can toggle it during rotation; it saves to the session and matching task checkpoints without changing pending cargo or progress, and applies after supported world-change resumes. Save the named profile to retain it when loading that profile or exporting to another device. New drops are hidden on a periodic scan, roughly once per second. Normal Stop keeps the boost active; switching it Off or unloading restores surviving visuals. Harvest collects selected blocks, matching seeds and gems; PNB also collects nearby gems. Live FPS improvement depends on the device and native client workload.

For a plain grey map, also enable **Settings → FPS booster: Grey map**. It removes map and nearby tree textures, uses grey shapes, and temporarily enables native local low graphics to reduce distant tree rendering and cosmetic effects. Sky/background, avatar, controls, doors, locks, access areas, Display Boxes and their contents remain visible. Tree maturity, world collision, harvesting, planting and collection data stay intact. This toggle works independently of hiding drops and follows the same session, checkpoint, profile and export/import rules. Turn it Off, unload or reload to restore current surviving textures and the previous local graphics flag. Copy diagnostics shows the simplified sprite count and visual errors; visual failures retry without pausing rotation.

For a stronger rendering reduction, enable **Settings → FPS booster: Hide game world**. The game viewport disappears while the script menu and native farming data remain available. Local low graphics remains enabled, and per-tile grey repainting stops while the whole view is hidden. Turn it Off before saving positions or playing manually; the surviving view is restored on Off, unload, reload and reconnect. With Grey map On, revealing the view returns to grey map rendering. Save/export your profile to retain the preference.

- Planting skips rows without empty supported planting tiles.
- Harvesting skips rows without ripe selected trees or matching drops to collect.
- The next supported row may be more than one tile below the previous row.
- Keep edge platforms and routes clear so the script can reach each row.
- Occupied tiles, unsupported air, access-denied cells, and unreachable planting cells are skipped. A completed scan does not guarantee every dirt tile was planted; check skipped counts in Recent activity.

From v0.1.34, Tractor harvesting collects nearby **gems while driving through the trees**, including when replanting cleared tiles. It uses the native pickup reach and readiness checks, keeps at most eight requests in flight, and continues forward without turning back for refused or delayed gems. No new toggle is required. Blocks and seeds remain on the ground during tree work so pickup cannot change the seed counts used to confirm planting.

After selected ripe trees and missed-tree cleanup finish, the drop-collection pass picks up matching **blocks, seeds and any remaining gems while walking** the supported zigzag rows, including a single supported row. It skips empty rows and keeps at most eight pickup requests in flight, reserves inventory space across late replies, and confirms inventory in batches. Quick pickups keep moving. Slow replies, partial stacks and refusal cooldowns stop movement before the avatar leaves pickup reach; it resumes the same direction once they settle. It settles pickups before storage trips. Full backpacks, turns and obstacles can still cause stops. Fist harvesting uses this later pass for all three drop types.

From v0.1.37, a nearby drop can retry from the avatar's current grounded position if native pickup overlap is valid even though no supported tile center is in range. Full Rotation defers an isolated drop when there is no reachable pickup position, or after three settled server refusals, and continues collecting other drops. It deposits held blocks/seeds and finishes transferring the farm Display Box's blocks to PNB. A deferred drop stays on the ground and appears in **Harvest collection recovery** diagnostics. Its account-specific checkpoint survives world reloads; it becomes eligible on a later farm visit after **five minutes**, or sooner if the drop moves. Deferred drops alone do not trigger repeated collection visits during that cooldown. Missing storage access, unsettled requests and ambiguous inventory/storage operations remain protected failures. Standalone Harvest Drops still reports an inaccessible drop as a failure.

Blocks and seeds go together into that farm's Display Box. Gems are currency and update the gem balance; they are never deposited in the box. Session reports and the finished-harvest gem total include gems collected during the Tractor pass and afterward. Unrelated crop drops and Display Box contents remain outside harvest collection. PNB collection stays near the saved breaking spot so it can finish each block safely.

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

The checkpoint is `ClarisGrowblox/accounts/<RobloxUserId>/rotation-resume.json`. It saves before world changes and phase transitions, during planting/storage progress, and periodically while running. Deadlines use **server time**, so restarting executor uptime does not restart tree growth.

### Automatic loader execution

Use the project's GitHub **loader.lua**, shown above, so the script knows which loader to queue. When Delta provides `queue_on_teleport` or a supported equivalent, it queues that loader with automatic resume before moving worlds.

After a server change resets the script, the queued loader connects, restores the saved rotation's configuration/profile, and resumes its phase. This includes PNB during growth waits, depleted-seed PNB draining and unfinished replanting. The logged-in account selects its own checkpoint folder automatically. Each fresh script registers execution again for the next world change. Rotation recovery takes priority over standalone PNB, Planting, and Moving Drops recovery.

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

Export also writes `ClarisGrowblox/accounts/<RobloxUserId>/exports/<profile>.json` when file functions are available. For file transfer, copy it to the destination, enter its local path in **Configuration file path**, and press **Import config file**. Plain existing profile JSON files are supported too. If clipboard/file access fails, the export text remains in Configuration text.

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

Use separate farms and storage for simultaneous accounts. The script does not coordinate shared harvesting, planting, or withdrawals. Each account needs world access and its own tractor for Tractor mode. For standalone Moving Drops, save that account's Farm and destination Display Boxes and choose Blocks or Seeds.

From v0.1.29, sessions, named profiles, exports and all task checkpoints use **`ClarisGrowblox/accounts/<RobloxUserId>/`**. The user ID comes from the logged-in Roblox player, so no extra slot name or isolation setting is needed. Even identical profile names are separate. The loader's verified code cache remains shared. **Update both cloud-phone instances to v0.1.29 or newer.** In Settings > Copy diagnostics, compare Roblox account and Account data: the two IDs/folders must differ.

On first upgraded load, only legacy sessions/checkpoints carrying that account's user ID are copied. Shared legacy files remain intact. The active profile is recovered from its owned session snapshot, while other ownerless legacy profiles require explicit import from `ClarisGrowblox/profiles/<name>.json`. Migration runs once per account, so clearing saved work does not resurrect it from shared old files. A configuration already overwritten by the other account needs a known export/backup or fresh setup.

Accounts can use the same webhook and ping the same Discord user; reports identify the player/profile. Export/import copies setup into the destination account's folder with tasks Off. Checkpoints still validate ownership. Separate account data does not coordinate shared in-game storage or harvesting: keep each account's assigned farms and boxes separate.

## Troubleshooting

| Symptom/message | What to check or do |
| --- | --- |
| Missing PNB spot or storage | Resave the middle spot and left/right boxes on Place & Break, all in the same world. |
| Layout error | Put boxes two tiles left/right of the PNB spot on the same row; clear the tile above the player. |
| No walking/jumping route to a raised PNB room under a low roof | Update to v0.1.30. It fixes the ceiling collision simulation during platform jumps. Copy diagnostics now shows the world, start tile and target standing tile. Check whether this account can manually reach that exact spot. A failure during `plant` can be the seed-box refill route. |
| Seed mismatch / use PNB seed storage | Select the correct block, save the left PNB box, and press Use PNB seeds for planting again. |
| Missing method 'Set' when using PNB seeds or loading config | Update to v0.1.25, push the rebuilt release, rerun the same GitHub loader, then retry. This fixes the dropdown refresh and resets the old UI lock. Check that the farm list and seed settings are displayed correctly. |
| Planting hook unavailable before starting | Farming hooks are deferred during the initial connection. They attach when Planting or Full Rotation starts. If task startup itself fails, copy diagnostics. |
| Game connection still takes time after a reload | v0.1.26 indexes game objects once and reduces forced frame waits. Push the complete rebuilt release and rerun the loader. Copy diagnostics shows discovery time/yields/checks; executor GC/debug calls and world loading still affect startup. |
| Planting pauses while crossing a row | Short confirmations and timing pauses are expected. Unconfirmed tiles are skipped and retried once from below where reachable; rotation continues. Failed inventory reads or unexplained count changes still pause. Check Planting recovery in diagnostics. |
| Floating blocks, seeds and gems are invisible | FPS booster hides their visuals. Automation can still collect them. Turn it Off in Settings for manual play; Display Box contents stay visible. |
| FPS remains low with many drops | Enable FPS booster and check Copy diagnostics for hidden sprite count/errors. Native drop processing and world loading still cost time; the booster does not remove server items. |
| Want a grey map with the sky visible | Enable Settings → FPS booster: Grey map, optionally alongside hiding floating drops. Doors and storage markers stay visible. Turn it Off to restore textures; save the named profile to retain it when loading or exporting. |
| Missing farm box | Visit the exact named farm and save its reachable harvest box. Check every listed world. |
| Full farm is not planting | Occupied tiles are intentionally skipped. Growing trees lead to PNB; ripe trees lead to harvest. |
| Some trees are ripe but the farm is still growing | The maturity wait accounts for remaining matching growing trees too. |
| Empty PNB storage while trees grow | v0.1.36 checks each waiting farm once for loose/stored harvest and moves recovered stock to PNB. If no stock exists, it waits without repeating an empty drain. |
| Repeated “Seed supply exhausted” / “PNB block supply finished” with empty storage | Update to v0.1.36 and resume the saved rotation. It remembers that the drain finished, checks farm stock despite saved growth deadlines, and resumes PNB when stock arrives. |
| Empty seed box and planting backpack | Drains PNB fully before more planting/harvesting. Produced seeds do not interrupt an active drain. If no blocks remain, normal farm scheduling resumes. |
| Ripe farm waits during `drainPNB` | Expected after seed exhaustion. It resumes after all PNB inventory/storage blocks and pickups finish. |
| Two cloud-phone accounts mix configs or rotations | Update both to v0.1.29 or newer. Check different account IDs/data folders in diagnostics; restore any previously overwritten config from an export/backup or resave it. |
| Tractor missing / another crop present | Supply the tractor and use a single-crop farm, or choose Fist. |
| Tractor with Replant during harvest leaves blocks/seeds after a collection interruption | Update to v0.1.35, push the rebuilt release and reload. Approved harvests now retain their tree/collection stage across retries and reloads, so new growing trees cannot send rotation away before collection finishes. Check Saved harvest pass in diagnostics. Older checkpoints without this stage still use the maturity check until a new pass starts. |
| Refused pickup, unreachable row, skipped planting cells | Check tile/box permissions, standing positions, platforms, obstacles, and inventory space; copy diagnostics. |
| Collection crosses a row and returns for its drops | Update to v0.1.37, push the generated release and reload. Each occupied row keeps one direction; slow pickups settle before leaving reach, and skipped rows do not cause an entry pass across the next row. |
| “No reachable floor or platform” stops harvest with blocks still in the farm box | Update to v0.1.37 and use Resume saved rotation. It retries a nearby drop from the actual supported position when possible, defers isolated inaccessible drops, then transfers the stored blocks before PNB. Check Harvest collection recovery for deferred UIDs; no new toggle is required. |
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

During normal rotation, a ready farm interrupts PNB after the current block and pickups settle. If both planting inventory and seed storage run out, it finishes all remaining PNB blocks first. Ripe farms wait until that drain completes.

**Does empty seed storage stop rotation immediately?**

It stops that planting attempt once carried seeds are also used. Rotation then drains all remaining PNB blocks and stores the produced seeds before returning to planting or harvesting. An active drain continues even after seeds appear in storage. If PNB is already empty, normal farm scheduling resumes; with no productive crop, seeds or blocks, it pauses.

**Can a saved profile resume a stopped run?**

A profile restores setup for a fresh run. Intentional Stop clears running progress. Resume saved rotation uses a checkpoint left by an interruption/error.

**Can it run 24/7?**

It repeats until stopped or a terminal fault occurs, with anti-AFK and supported recovery available. Keep the device/executor active, world access valid, storage usable, and routes clear. Unresolved game/executor faults still require attention.

## Push this update to GitHub

To rebuild, check, commit and push the script and guide from PowerShell:

```powershell
cd "F:\VSCode\Luau\Claris Growblox Autofarm\logic"
npm.cmd run build
npm.cmd test
npm.cmd run test:lua
git add src/main.lua src/navigation.lua tests/runtime.lua package.json main.lua loader.lua release.json releases/ README.md README-ROTATION.md RESEARCH.md
git commit -m "Fix low-ceiling storage routes"
git push origin HEAD
```

Run the Git commands only after the checks pass. Push the updated loader, manifest, bundle, and new immutable release folder together. Keep using the same GitHub loader command after updates, and reload both accounts onto v0.1.30 or newer.

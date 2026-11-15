# Botting setup and operation

For **Claris Growblox 0.1.40**. Botting coordinates accounts on one cloudphone through a shared executor folder. Each account has its own role, breaker spot and recovery checkpoint. Export the emulator's layout once, import it into every account, then choose each account's role in **Botting**.

## 1. Prepare the world and accounts

- Use one BNS (Break & Storage) world with separate block and seed Display Boxes.
- Build a supported, walkable breaking lane. Each breaker stands on its own saved tile and places one block directly above itself.
- Put the collector near the middle of the lane. Three adjacent breaker columns suit the initial stationary pickup attempts.
- Boxes can be elsewhere in the lane or on a reachable upper platform. Botting does not require the old left-box/player/right-box PNB arrangement.
- Link the red shortcut door near the white entrance to your BNS area in the **same world** using the game's door settings.
- Give every account the world access it needs for its assigned work.
- Have at least one **level 10+ account owning a Dear John Tractor** for tree harvesting, and a level 10+ collector for farm drops and storage delivery.
- Select the block you want to farm. Keep some matching planting seeds in the BNS seed box and blocks in the BNS block box when available.

Botting checks the account's current level and whether its backpack contains the Tractor. Changing the role does not bypass these checks. Level 1–9 accounts can break in BNS and plant on farms; they are never assigned farm harvesting, drop collection or transfers.

## 2. Save the shared layout on your emulator

Keep tasks stopped while configuring locations. Disable **Hide game world** so you can see the targets.

1. On **Place & Break**, select the crop block using the existing block selector. You do not need to configure the old PNB layout for Botting.
2. On **Planting**, enter the complete farm world list, for example `FARM1, FARM2, FARM3`.
3. Visit the BNS world. In **Botting**, enter a team name, such as `BNS`, and leave **Shared team folder** at `ClarisGrowblox/teams` unless your executor uses another shared folder. Executor-supported Android locations such as `/sdcard/ClarisGrowblox/teams` or `/storage/emulated/0/ClarisGrowblox/teams` are accepted too.
4. Set **Expected team accounts** to `4` for your four instances. This value is included in the exported layout.
5. Stand beside the red entrance shortcut door and press **Save BNS shortcut door**. The saved target must lead into the BNS lane in this same world. If it cannot be used, the script records the reason and tries walking.
6. Stand beside the block box and press **Save BNS block Display Box**.
7. Stand beside the seed box and press **Save BNS seed Display Box**. For an upper box, stand on its nearby platform so that box is the closest one. Saving it also makes it the planting seed box and selects the matching seed when the block is already selected.
8. Stand at the first breaker circle and press **Add BNS breaker spot**. Repeat for each circle, preferably from left to right. Spots are numbered in the order you save them.
9. Stand at the collector position, preferably the middle circle, and press **Save BNS collector position**. If omitted, the middle saved breaker spot is used.
10. Visit every farm in the Planting list. Stand beside that farm's harvest Display Box and press **Save this farm's Botting harvest box**. Farm boxes can hold both selected blocks and matching seeds.
11. Choose **Harvest Drops → Harvest method → Dear John Tractor** if you want Tractor harvesting. Eligible accounts can instead use Fist; ownership of a Tractor is still required to receive a Botting harvest job. Missed Tractor trees use the existing Fist cleanup.
12. In **Configurations**, save your named profile and export it. Copy the exported JSON or export file into the other instances.

The export contains the BNS world, boxes, shortcut door, complete breaker-spot list, collector position, farm list, farm boxes, storage policy and FPS preferences. **It does not contain the account's Botting role or its live cargo/progress.**

## 3. Import and assign each account's role

On every instance, use **Configurations → Import config** or **Import config file**, then open **Botting**. Importing preserves that account's role preference and clears its old task checkpoints; review interrupted cargo before importing over active work.

Example for three breaker circles and four accounts:

| Account | Role | Local breaker spot | Notes |
| --- | --- | --- | --- |
| A | Breaker | 1 | Breaks on the left; helps farm jobs when storage is low. |
| B | Breaker | 3 | Breaks on the right; helps farm jobs when storage is low. |
| C | Collector | 2 | Collects at the saved middle position. Leave **Collector also breaks** Off initially. |
| D | Rotation | 2 | Handles farms; breaks on the middle spot when no farm job is due. |

Each account chooses **This account's role** and **This account's breaker spot** locally. Role changes are saved immediately in that account's folder and survive reloads and subsequent config imports.

The collector may stand at the same position as an idle rotation worker. A collector that also breaks reserves its selected breaker spot; another breaker choosing that spot waits instead of placing into the same tile. If you enable **Collector also breaks**, give other BNS workers different spots or let the rotation account wait while the lane is occupied.

Save the shared profile again if you change layout, world list, team name, expected team size or FPS settings and want future profile loads/exports to retain them. A role change does not require exporting the shared layout again.

## 4. Verify sharing and start

Being on the same cloudphone does not necessarily mean cloned apps share executor files.

1. Keep all four instances running and import the same layout into each.
2. Press **Botting → Connect team / refresh teammates** on every account.
3. Check **Team status**. All instances must report **Detected 4 accounts** with the same team folder and setup. Registered accounts can be detected before their Botting toggle is enabled; the active count rises as you start them.
4. If an instance only detects itself, its executor files are isolated. Point every instance at a folder actually shared by the executor/app setup, then reconnect. An Android shared-storage location works only when the executor and Android permissions allow all instances to read/write it. This build uses local shared files; it does not synchronize across isolated folders or separate devices.
5. Enable **Continuous Botting** on each account. Starting is blocked if fewer than the configured number of accounts are detected.
6. Watch one short breaking/collection cycle, a storage deposit and a farm handoff before leaving it unattended.

If a different layout is already active under the same team name, Botting reports a mismatch instead of overwriting that team's assignments. Import the same layout or choose a different team name for the separate operation.

## 5. How the roles work

### Breaker

The account repeatedly places and breaks the selected block directly above its saved spot. It does not wait for the collector's pickup replies. It refills from BNS block storage when its backpack runs out.

When an eligible BNS collector is active, native pickups on the breaker are suppressed so the collector owns the block, seed and gem pickups. If the collector is unavailable, the breaker can collect its own nearby returns and gems. A level 10+ breaker also collects and stores seeds; a level 1–9 breaker leaves seeds for an account that can store them.

At **6,000 stored blocks or below**, breakers help farm work: harvest if eligible and equipped, collect/transfer if level 10+, or plant if seeds and empty dirt are available. Above that threshold, breakers generally remain in BNS. An already assigned farm job finishes before the worker changes jobs.

### Collector

The collector first attempts nearby pickup requests while standing at the saved middle position. The existing direct pickup path searches the adjacent horizontal area. This can collect drops from neighboring columns when the server accepts them from that position.

Farther drops or repeated refusals trigger a short approach to a supported pickup position. The collector collects at that position before returning, rather than repeatedly walking out and back without taking the drop. Unsupported drops are deferred while other reachable drops continue.

Blocks, seeds and gems are collected in batches. At a full block stack or the configured seed threshold, the collector unloads blocks into the BNS block box and seeds into the BNS seed box, then returns. Gems belong to the account that picked them up.

**Collector also breaks** adds a placement/breaking step at its free selected spot. It reduces the time available for collection, so start with it Off and enable it after observing pickup throughput.

A sole collector stays in BNS while breaker accounts are producing drops. It can help farms when supply is low and no free breaker is currently producing work there.

### Rotation

The rotation account supplies the BNS boxes from the full Planting farm list. Its priorities are:

1. Collect existing farm drops and move stored farm harvest, including stock left by an earlier session.
2. Harvest a farm only when every selected tree is mature, using an eligible account that owns a Tractor.
3. Plant available dirt last, while existing harvest and transfer work proceeds where workers are available.
4. Break in its free BNS spot or wait for a spot while farms grow and no farm job is due.

Farm observations are shared. Idle farm inspections are scheduled when observations are missing or due, with maturity timers limiting repeat visits. An account already working in a farm updates its observed drops, empty dirt and tree readiness periodically. BNS storage reports are also refreshed after confirmed storage actions.

## 6. Shared harvesting, collecting and planting

Only one account receives a tree-harvest job for a farm. That account uses the existing top-to-bottom row traversal, harvests with the selected method, picks up gems during the tree pass and leaves block/seed drops for collectors.

Up to two farm collectors divide **supported farm row numbers** between them: one takes rows 1, 3, 5; the other takes rows 2, 4, 6. Each worker uses the existing row traversal and pickup settlement logic. The division works when physical row Y coordinates are 2, 4, 6, etc. A lone eligible collector alternates partitions so the other half does not remain uncollected.

Collected blocks and seeds are stored in the farm's mixed Display Box. Collectors then move both types together to BNS. A separate planter can fill harvested dirt while harvesting and collection continue; Botting uses independent planting assignments rather than **Replant during harvest**.

Unreachable farm drops are deferred for five minutes while reachable collection and storage transfers continue. The cooldown survives job changes and checkpoints; a moved drop becomes eligible immediately.

The first tree pass requires the farm to be fully mature. Once approved, its saved pass can finish while another account plants growing replacements. Those replacements are left growing; they do not cancel the unfinished pass.

## 7. Paired block and seed transfers

For a mixed farm box, Botting takes up to **200 blocks plus 200 matching seeds** in the same withdrawal, subject to backpack room and the actual server result. It travels to BNS once, deposits blocks into the block box and seeds into the seed box, then returns for the next batch.

If only one type remains, it moves that type. Each worker receives its own server-confirmed cargo; workers do not assume the box still has the count observed before another worker withdrew from it. Transfer trips continue until the farm box is empty.

The transfer phase and pending storage operation are saved privately before requests and world changes. If blocks were delivered but seeds are still held, resuming the delivery phase deposits the held seeds before taking another farm batch. An explicit server rejection can retry without repeating a deposit already confirmed.

An interrupted request whose outcome cannot be confirmed remains paused with its pending storage checkpoint. Check backpack and both relevant boxes before using **Clear saved Botting**. This preserves the evidence needed to avoid duplicate withdrawals or deposits.

## 8. Storage policy

| Condition | Result |
| --- | --- |
| Stored BNS blocks ≤ 6,000 | Breakers help eligible farm jobs. Rotation continues supplying BNS. |
| Stored BNS blocks between 6,000 and 36,000 | Breakers generally break; rotation supplies farms as needed. |
| Stored BNS blocks reach 36,000 | Enter draining mode. Stop assigning fresh harvest passes. Finish existing cleanup/transfers and fill available empty dirt, then focus on breaking. |
| Draining mode remains above 6,000 | Keep draining even if the count falls below 36,000. |
| Draining mode reaches 6,000 | Resume the normal supply/assist policy. |
| Farm is already full of growing trees | Skip planting; break or handle existing drops/box stock while waiting. |
| BNS seeds are exhausted with blocks remaining | Finish the remaining BNS block supply, including teammates' held stacks and placed breaker blocks, before fresh planting/harvest. Active cleanup still finishes. Seeds already being delivered prevent a false exhaustion trigger between paired deposits. |
| No stored blocks remain | Wait for farm supply or eligible farm work; do not pause just because storage is empty. |

The stock thresholds count the saved **BNS block Display Box**. They do not claim an exact combined count of every backpack or floating drop. Counts can change while workers finish their current actions, so the 36,000 threshold is a scheduling boundary, not an exact inventory cap.

## 9. Reloads, stopping and recovery

While Botting runs, it saves its account's config snapshot, assigned job, planting/harvesting state, transfer phase and pending storage evidence. Supported teleports queue the GitHub loader and automatically resume Botting for that account.

- Keep using the generated GitHub loader so the queued loader URL is available.
- If your executor cannot queue execution on teleport, configure its own auto-execute feature with that loader. The script cannot make an executor support automatic execution.
- A normal reload with a saved running Botting preference also resumes the saved account task.
- Turning **Continuous Botting** Off or unloading disables that account's automatic restart preference. Use **Resume saved Botting** to resume explicitly.
- **Clear saved Botting** clears that account's progress and automatic restart preference while keeping its layout and role.
- Importing a config clears old progress and disables its restart, while preserving the local role choice.

The lowest active account ID is the current file coordinator. Active workers publish heartbeats, and farm assignments stay with their owner while the job runs. Short file-write gaps use the last valid data rather than immediately replacing a worker. A worker missing for about **90 seconds** can lose its lease and have unfinished work reassigned. An account returning with held transfer cargo unloads that cargo before accepting a different assignment.

Routing and ordinary operation failures retry after five seconds. Storage or planting requests with an unconfirmed outcome retain their checkpoint for review. Check **Copy diagnostics** for the job, role, level, leader, teammate count and last error.

## 10. Stronger FPS mode

Enable **Settings → FPS booster: Hide game world** to hide the native game viewport, including its map, avatars, sky/weather and effects. The script menu remains usable. The native game state, pickup data, tree timers and movement hooks continue running; the game view's own visibility updates cannot reveal the hidden parent.

This mode temporarily enables the native local low graphics flag and avoids the per-tile grey repaint work while the whole view is hidden. Combine it with **FPS booster: hide floating drops** to also suppress loose-drop sprite rendering and bobbing.

Turn **Hide game world** Off before saving locations or playing manually. Off, unload, reload and reconnect restore the surviving viewport and prior local graphics flag. With **Grey map** also On, switching Hide game world Off returns to the grey map.

All FPS preferences save to the session and matching task checkpoints. Save/export the named profile to carry them into later profile loads or imports. The client still processes gameplay and server messages; actual FPS and multi-instance throughput require testing on your cloudphone.

## 11. Discord and diagnostics

Use the existing **Discord Webhook** tab for timed reports and failure pings. Botting completion/failure events include their job and world; the report identifies Botting and the current role/team state. Existing failure alerts can ping the Discord user ID you configured.

**Settings → Copy diagnostics** includes the account data folder, role, spot, detected/active count, coordinator, storage mode, current job, FPS states and errors. Do not clear an interrupted storage checkpoint until you have reviewed its inventory and boxes.

| Symptom | Check |
| --- | --- |
| Detected 1/4 accounts | Connect all instances and verify their executor folders are actually shared. Same cloudphone alone does not prove this. |
| Different layout under the same team name | Import the same complete setup into each participant, or use another team name. |
| No harvesting jobs | Check level 10+, Tractor in the backpack, full maturity, storage draining mode and seed-exhaustion mode. |
| A breaker waits for a spot | Choose a different local breaker spot or disable Collector also breaks on the account reserving it. |
| Collector sometimes walks | Neighboring pickup requests were refused or a drop was outside the stationary area. It uses a supported approach. |
| Rotation leaves planting for later | Existing drops/transfers take priority. Full farms and empty seed storage skip planting. |
| Pending storage operation | Review the backpack and source/destination boxes; the outcome was not confirmed. |
| Native game disappears | Hide game world is On. Turn it Off in Settings to see and configure the layout. |

The release is validated offline against mock game services, physics, storage and shared files. Those checks do not establish the live server's pickup acceptance for another account's drops, executor filesystem sharing, teleport execution, account permissions, FPS gain or Discord delivery.

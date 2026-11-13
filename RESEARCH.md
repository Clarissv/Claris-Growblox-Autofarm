# Growblox adapter evidence

Source boundary: 126 Lua dump files in `../[112863874972771] Growblox`, supplied by the user. The main client was decompiled with Delta and includes reconstructed control flow. These are static observations; no Roblox runtime or server source was available.

| Finding | Dump source and line | Implementation consequence |
| --- | --- | --- |
| Registry is `shared[ReplicatedStorage:GetAttribute("Qz")]` | `[nil] rpiyox2ca0N (1_666082).lua:1740` | Resolve ModuleScript references from the game registry. |
| Bootstrap publishes a proxy with the actual module map in its `__index` table | `[nil] TFM2nCP4e (1_666125).lua:192` | Resolve through `getrenv().shared`, the executor's shared table, or a matching GC module map. Executor and game environments may differ. |
| Main returns `true`; the active world is private | `rpiyox2ca0N:14935` | Discover the world table through `getgc(true)` and verify its function signatures. |
| Avatar state callback exposes 2D center/feet coordinates and velocities | `rpiyox2ca0N:10163` | Use the matching controller's `state()` for capture and movement feedback. |
| Main dynamically reads mounted touch controls | `rpiyox2ca0N:160`; `[nil] ZT0JhdkFNJaq (1_666093).lua:383` | Temporarily supply movement/jump input and restore the original functions on stop. |
| `setTile(layer,x,y,id,localOnly,flip)` sends and applies optimistic updates | `rpiyox2ca0N:2223` | Verify placement through a server inventory delta with pickups paused; an own-player tile echo is not required. |
| Placement invokes `setTile`, then removes one item locally | `rpiyox2ca0N:7992` | Mirror the existing client action and refresh authoritative inventory at cycle boundaries. |
| Private `hit` performs tile damage; newly placed blocks have a 0.3-second grace period | `rpiyox2ca0N:4150`, `:4224` | Use this handler, preserve the grace period, and pace repeated hits. |
| Packet `punch` takes a player ID | `[nil] mG2p24qorrZ9 (1_665958).lua:1688` | Do not use this packet to break tiles. |
| Tile change packets contain a world tag, layer, coordinates, ID, and flip | `mG2p24qorrZ9:1700`; `rpiyox2ca0N:10578` | Leave the existing game listener intact so it applies corrections. The eight-bit tag has possible collisions and no per-action sequence. |
| Display contents are rows `{itemId,count,offset}` | `rpiyox2ca0N:13164` | Count contents and reject mixed storage before withdrawal. |
| `DisplayItem` RPC maps deposit and withdrawal to the display packet | `mG2p24qorrZ9:2592`; `rpiyox2ca0N:13128`, `:13263` | Call synchronously, then refresh inventory. Avoid the game's optimistic async wrappers. |
| Automatic pickup calls `world.displayTake` when walking over storage | `rpiyox2ca0N:3629` | Suppress automatic box withdrawals during jobs so collection does not undo deposits. |
| Loose-drop pickup calls `world.takeDrop`, then updates local inventory | `rpiyox2ca0N:3677` | Keep ordinary pickup, but quiesce pending pickup callbacks before refreshing inventory. |
| Inventory synchronization reconciles non-tool counts | `rpiyox2ca0N:11998` | Reconcile server snapshots to the existing inventory instance, retaining tools. |
| `GetInventory` can wait indefinitely in the packet RPC layer | `mG2p24qorrZ9:3610` | Bound the external wait and prevent another task from starting while a request remains pending. |
| Stack limit is 200; room/count methods are on the inventory metatable | `[nil] aIqS5yr1D (1_665955).lua:192`, `:208` | Check capacity and discover the inventory through the `backpackNow` upvalue. |
| Blocks can share a `seedId` override | `[nil] m2h4Pb4MzeY (1_665948).lua:7099` | Resolve `seedId` first, otherwise validate `blockId + 1` as a seed. Sugar Cane is 954, seed 955. |
| `UseDoor` returns either `go` coordinates or an `enter` target | `rpiyox2ca0N:12448` | Preserve the server's target string, use the intended door teleport result, and verify the arrival world. |
| Entering can apply a local world snapshot or request a Roblox server teleport | `rpiyox2ca0N:10406`, `:10437` | Save the transfer phase and queue the GitHub loader before entering. |

Design choices: named profiles, screenshot-based 2 x 5 layout, dedicated storage boxes, natural walking with jumping and timeouts, serialized workflows, and explicit recovery for ambiguous storage requests. No automatic tree harvesting was added because the requested first version uses manual harvesting.

User runtime evidence: v0.1.1 attaches and places a block, then times out waiting for a tile echo. Restarting places the next block and repeats the timeout. This establishes that the required echo was unavailable in that session; it does not establish which server broadcast or executor-listener behavior caused it. Version 0.1.2 verifies consumption with GetInventory and uses the normal client hit lifecycle for breaking, without an echo dependency.

Remaining runtime questions: server rejection/correction behavior; traversability of the user's saved paths; account/world permissions; and teleport queue behavior in the installed Delta version. Offline tests do not establish those facts.

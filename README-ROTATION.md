# Full Rotation guide

For Claris Growblox 0.1.23. This runs **Planting → Harvesting → Place & Break → repeat** across every world in your Planting list.

Use a reachable Display Box in each farm and keep the side platforms clear. In the breaking world, keep the usual layout: **Seed box — Empty tile — PNB spot — Empty tile — Block box**. The Farm boxes hold matching blocks and seeds together; the two PNB boxes remain separate.

1. Save the PNB spot and its left seed / right block Display Boxes on **Place & Break**, and select the block to farm.
2. On **Planting**, enter the complete farm world list in order.
3. On **Full Rotation**, press **Use PNB seeds for planting**. This selects the matching seed and uses the saved left PNB box as planting stock. Seed storage must be outside the farm list. Put initial seeds in the backpack or this box.
4. Visit each listed farm world, stand beside its harvest Display Box, and press **Save this farm's harvest box**. The page lists saved and missing worlds. Existing **Save Farm storage** buttons remember each world too.
5. Choose **Fist** or **Dear John Tractor** on **Harvest Drops**. Keep the tractor in the backpack when using it and use a single-crop farm.
6. Configure Discord reports using the steps below, then use **Configurations → Save profile / Save as** to save the farm list, boxes, harvest method, and webhook settings. Stop the task before saving a named profile. The rotation toggle starts work; saved settings and rotation checkpoints let you resume it later.
7. Turn **Continuous full rotation** On in **Full Rotation**. It plants the full list first, then waits for growing trees without walking the rows, harvests each farm, transports its blocks to PNB, adds harvested seeds to planting stock, runs PNB, stores the remaining seeds, and starts another planting cycle. Rotation enters worlds by name; linked doors are used only by standalone Moving Drops.

The route starts from the top-left supported row, crosses right, descends to the next supported row, crosses left, and alternates down the farm. Planting skips full rows. Harvesting breaks ripe trees before collecting drops and skips rows without work. Each new farm restarts its row direction from the left.

If stock runs out partway through planting, the rotation processes existing partial farms to replenish seeds. With no eligible crop or stored items anywhere in the list, it pauses instead of repeating empty travel. Both planting and harvesting retain physical-row zigzag direction and skip rows without work.

Moving blocks from a mixed Farm box can also withdraw seeds. The script keeps up to 200 matching seeds during block trips, returns them to the Farm box once its blocks are moved, then transports the Farm seeds into the PNB planting-stock box. PNB-produced seeds are stored there too.

Rotation saves the current phase, farm, cycle, planting progress, transfer cargo, and pending storage requests before world changes. Delta's teleport queue resumes the rotation first when available; otherwise run the loader after arrival and press **Resume saved rotation**. Read-only world/respawn interruptions can recover when **Rejoin world and return to PNB** is On. An ambiguous storage request pauses for inventory/box review and **Clear saved rotation**. Normal Stop clears automatic resume while retaining items and settings. Test one complete rotation in your farm before leaving it running; live server reach, world access, and executor availability can still interrupt it.

If setup reports a missing farm box, visit that exact world and save its box. If it reports a seed mismatch, use **Use PNB seeds for planting** again after selecting the correct block. If the tractor is missing or another crop is planted in the farm, choose **Fist** or correct the farm/equipment setup. For refused pickups or unreachable rows, use **Settings ? Copy diagnostics**.

Saved checkpoints expire six hours after their last update. The script refreshes them while running, so this does not limit a rotation to six hours. Session counters reset when the script reloads.

To copy this setup from an emulator to a cloud phone, use **Configurations → Export config**, paste the exported text on the destination device, and press **Import config**. See the [configuration transfer instructions](README.md#export-from-an-emulator-and-import-on-a-cloud-phone) for the file option and profile naming. Import saves settings and keeps the task Off; running progress is not transferred.

For multiple accounts, import the setup and then save each account's own PNB spot and matching boxes. Press **Use PNB seeds for planting**, set that account's assigned farm list, and save its harvest boxes. Moving the account to a different layout alone does not change saved coordinates. Give simultaneous accounts separate farms and storage because the script does not coordinate shared work. Each account needs world access and its own tractor when using Tractor mode.

## Discord work reports and failure pings

1. In Discord, open the destination channel's settings, choose **Integrations → Webhooks**, create a webhook, and copy its URL.
2. Open the script's **Discord Webhook** tab and paste the URL into **Discord webhook URL**.
3. Set **Send every (minutes)** to your reporting interval, for example `5`. Enable **Automatic webhook reports** for timed progress and a work report after each completed rotation cycle.
4. Enable Discord **Developer Mode**, use **Copy User ID** on your profile, and paste it into **Discord user ID to ping on failure**. Use the numeric user ID, not your username. Leave it blank to receive alerts without a ping.
5. Leave **Failure alerts** On. This sends a failure report and pings the saved ID when the rotation pauses with an error. Failure alerts also work with **Automatic webhook reports** Off. Stop, completed cycles, and successful recovery do not ping.
6. Press **Send stats now**, then check the Discord channel and **Webhook status** to confirm delivery. This test sends stats without pinging your failure ID.
7. With the task stopped, use **Configurations → Save profile / Save as** to keep these settings, then start **Continuous full rotation** on **Full Rotation**.

Reports identify the Roblox player, world, profile, harvest method, current farm, phase, and cycle. Work totals include trees harvested, blocks and seeds collected/stored, seeds planted, blocks moved/broken, gems collected, and completed rotations. Session totals reset when the script reloads. Timed stats include player level and gem balance when available; failure and completion reports use the progress captured at the event without waiting for game-stat queries.

If an alert arrives, read the failure message, check the reported farm and phase, and use **Settings → Copy diagnostics** to investigate. Review inventory and storage before clearing a checkpoint for an ambiguous storage request. Discord delivery errors do not stop farming. Alerts wait behind an outstanding Discord post, respect rate limits, and retry other delivery errors up to three times; a delayed successful response does not trigger another ping. Webhook status shows pending reports and delivery errors.

The webhook URL, Discord ID, interval, and toggles transfer through config export/import. Several accounts can notify the same Discord user, with their own player and profile shown in each report. Queued alerts and running progress are not exported. Changing webhook settings or loading/importing a configuration clears old queued reports. Keep exported configurations private because they contain the webhook URL.

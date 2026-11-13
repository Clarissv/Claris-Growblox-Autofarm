# Claris Growblox Autofarm

WindUI script for Growblox, intended to run through Delta. Version 0.1.1.

Version 0.1.1 fixes startup when Delta's `shared` table differs from the game's `shared` table. It resolves the module map through the game's runtime environment or GC tables, loads the inventory independently of missing farming hooks, and retains the original connection error in diagnostics.

## Features

- **Place & Break:** choose a block from your inventory, fill the five columns and two rows above your saved PNB position, break those blocks, and collect loose gems, seeds, and returned blocks. Refill from the right Display Box when the backpack runs out. Put seeds in the left Display Box at the configured count, which defaults to 200. Stop when both backpack and block storage are empty.
- **Moving Drops:** take the selected blocks from a dedicated farm Display Box, use the linked door to the breaking world, deposit the trip's blocks in the PNB storage box, and return through the other linked door. Continue until stopped or the farm box is empty. Harvesting remains manual.
- **Named configurations:** Save, Load, New, and Delete multiple profiles containing the chosen block, every saved world and tile, the position from which to access each box/door, and timing settings.
- **Control and recovery:** one task runs at a time. Stop restores the game controls. Server confirmations, request timeouts, and transfer checkpoints prevent an unsuccessful action from silently advancing the loop.

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

## Set up Place & Break

1. Select the block on the **Place & Break** tab. Press **Refresh inventory choices** after obtaining a new block.
2. Arrange the storage row as `Seed box - Empty - Player - Empty - Block box`. Leave ten empty foreground tiles above the player: five across, two high.
3. Stand still on the middle platform and press **Save PNB spot and matching boxes**. This saves the two boxes automatically when the screenshot's layout matches. If needed, stand beside each box and save it separately.
4. Keep each Display Box dedicated to its corresponding item. Mixed boxes are rejected because Growblox's withdrawal action can take every item type in a box.
5. On **Configurations**, enter a name such as `Sugar Cane - Farm 1`, then press **Save profile / Save as**.
6. Press **Start Place & Break**. Press **Stop** to end it. The UI stays accessible through the floating Claris button.

The script walks to saved positions through the game's normal 2D controls. Keep paths reachable and avoid moving the player manually during a task. If a position times out, check the path and save it again.

## Set up Moving Drops

1. Select the block on **Place & Break**. This choice also applies to Moving Drops.
2. In the farm world, harvest manually and place the harvested blocks in the farm Display Box.
3. Stand beside that box and press **Save Farm storage** on **Moving Drops**. Stand beside the linked door and save **Farm door to breaking world**.
4. In the breaking world, save the destination Display Box using **Save block storage** on **Place & Break**. Stand beside the return door and save **Breaking door to farm world**.
5. Verify the doors link to the intended worlds and arrival doors. Save the named profile after recording both worlds.
6. Return to the farm world and press **Start Moving Drops**.

The script records only the newly withdrawn blocks as each trip's cargo. Blocks already in the backpack are retained. If the backpack has no room, free up space before starting.

When a linked door changes Roblox servers, Delta's teleport queue reloads the GitHub loader and resumes the saved transfer when that executor function is available. If Delta does not expose a teleport queue, execute the loader again after arrival and press **Configurations → Resume saved transfer**.

An interrupted storage request leaves a `pickupPending` or `depositPending` checkpoint. Check the backpack and both boxes before pressing **Clear saved transfer** and starting again. This avoids repeating a storage action whose result was lost. Normal Stop clears the automatic resume checkpoint; restarting starts a fresh task.

## Configuration files

Profiles are saved in Delta's local `ClarisGrowblox/profiles/<name>.json` files. Saving again under a different name creates another profile. Loading a profile changes the script's selected block, saved locations, and settings; it does not move the player.

Saved files are validated before loading. Profile names accept letters, numbers, spaces, underscores, and hyphens. Each save is checked by reading it back; an existing file is backed up as `.json.bak`. Transfer recovery uses `ClarisGrowblox/resume.json`, tied to the Roblox account and expiring after six hours.

## Development

Edit `src/main.lua` and `src/core.lua`, then run from this folder:

```powershell
npm run build
npm test
npm run test:lua
```

The build uses only Node's standard library and the supplied `../WindUI` checkout; no npm installation is required. `tests/run.ps1` uses the existing Lua library at `C:\Program Files\VideoLAN\VLC\plugins\lua\liblua_plugin.dll`. An alternate compatible DLL can be supplied with `-LuaLibrary`. The Lua test runner compiles the complete generated script and loader and executes the offline fixtures.

Push the rebuilt files, new `releases/<revision>` folder, and updated `loader.lua` together. Do not modify an existing release's files. Keep the same GitHub `loadstring` when updating the project.

## Sources and limitations

See `RESEARCH.md` for the client-dump evidence behind the game adapter. Runtime access requires Delta's `getgc` and debug upvalue/function-name APIs. Randomized module references are resolved through the game's own shared registry. A future game update can change those references or private handlers; the script stops with a diagnostic when it cannot identify them.

The original instructions and screenshot were read without modification.

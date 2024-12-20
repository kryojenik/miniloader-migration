[![shield](https://img.shields.io/badge/Ko--fi-Donate%20-hotpink?logo=kofi&logoColor=white)](https://ko-fi.com/M4M2LCWTH) [![shield](https://img.shields.io/badge/dynamic/json?color=orange&label=Factorio&query=downloads_count&suffix=%20downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fminiloader-migration)](https://mods.factorio.com/mod/miniloader-migration)

# Modernized miniloader migration

This mod will allow you to migrate the Miniloaders you used in Factorio 1.x to Loaders Modernized in Factorio 2.x.

## Features

Able to migrate most Miniloaders from your saves

- All Loaders Modernized support filters and circuit connections.  Filter Miniloaders are not a separarate item.
- Circuit connections, filters, whitelist / blacklist settings are maintained
- Split lane Miniloaders are migrated

## Usage

0. ***BACKUP YOUR SAVE FILE***
1. Install and enable both [Loaders Modernized](https://mods.factorio.com/md/loaders-modernized) and Modernized miniloader migration
2. On initial load you will be presented with a notice from Factorio that entities, items, recipes, etc have been migrated or removed.  Click Contiue.
3. A Pre-migration welcome message will apear.  After reading, Click Migrate!
4. After migrating Miniloaders you will be presented with a list of loaders that could not be migrated.
5. The next screen will list any split-lane miniloaders that could not have thier filters re-applied.
  Split-lane loders in Factorio 2.0 only allow 1 filter per lane.
6. As long as you keep Modernized miniloader migration installed and enabled you can return to the lists of unmigrated and altered filters by using the /mdrn-migrations console command.

## Feedback

Please let me know in the discussions if there are loaders that don't migrate properley, belt packs that need suport, etc...

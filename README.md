# Spell DPS Tooltips

A lightweight World of Warcraft Classic addon (developed for the 20th Anniversary) that calculates and displays the Damage Per Second (DPS) for both Direct Damage and Damage over Time (DoT) spells entirely through their in-game tooltips.

## Calculated Metrics

Depending on the type of spell, the addon will calculate and inject the following metrics:

- **Direct DPS:** Calculates the average DPS of a direct-damage spell. Uses the damage (or average of a damage range) divided by the cast time. For instant spells, it divides by the cooldown or a 1.5s GCD.
- **DoT DPS:** Parses DoT or channeled effects (e.g., "X damage over Y sec" or "X damage every 1 sec for 3 sec") and calculates the DPS.
- **Est. Total Damage:** For spells that have both an initial direct-damage hit *and* a DoT component, this line sums the maximum estimated damage for the entire cast.
- **Est. Cycle DPS:** For hybrid spells (Direct + DoT), this line shows the DPS over the entire lifecycle of the spell. It calculates this by dividing the *Est. Total Damage* by the combined duration of the Cast Time + DoT Duration.

## Installation

1. Download the latest release from the repository.
2. Extract the `SpellDPSTooltips` folder to your WoW directory: `_anniversary_\Interface\AddOns\SpellDPSTooltips` (or the appropriate version directory in `_classic_era_`).
3. Launch the game and enable "Spell DPS Tooltips" in your addons list.

## Usage

Simply hover over any spell in your spellbook or on your action bars that heals damage, deals direct damage, or applies a DoT effect. A new line will be added to the bottom of the tooltip displaying the calculated DPS.

![Preview](https://placeholder.com) <!-- Replace with screenshot later if desired -->

## Contributing

Pull requests and issues are welcome! If you find any spells whose tooltips use weird phrasing that isn't parsed correctly by the addon, feel free to open an issue or submit a fix for the regex pattern!

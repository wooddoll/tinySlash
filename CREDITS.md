# Credits

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1")
by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd.
The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International
License, available at https://creativecommons.org/licenses/by/4.0/legalcode.

Changes were made: rules were adapted for a grid-based, turn-based video game
(see `docs/rules.md`, entries marked [변경]).

This project is not affiliated with, endorsed by, or sponsored by Wizards of the Coast.

## 3D models

Mini Dungeon, Mini Characters, Modular Dungeon Kit, Modular Cave Kit, Survival Kit,
and Nature Kit by Kenney (www.kenney.nl),
licensed under Creative Commons Zero (CC0). Attribution is not required but appreciated.
Files are in `assets/kenney/<pack>/` with each pack's `License.txt`.

Dark Fantasy Knight, Witch and Goblin by Bento Pack (Pedro Bento), from Fab under the
Fab Standard License. Made by the author with generative AI tools. Reduced for this game
(about 22K triangles, 1024 px textures, a few animation clips) by `tools/bake_dark.gd`;
files are in `assets/dark/<name>/`. The original downloads stay outside the project and
must not be shared or uploaded publicly.

Stylized Dark Fantasy Zombie by Hotstrike Studio, from Fab (the listing showed a CC-BY
license; check the listing before any release). The goblin's animations were moved onto its
skeleton by `tools/retarget.gd` and baked into `assets/dark/zombie/zombie.scn` by
`tools/bake_zombie.gd`. Used for the zombie, ghoul and ghast.

Stylized Dark Fantasy Skeleton by Hotstrike Studio, from Fab, licensed under Creative Commons
Attribution (CC-BY). The knight's animations and longsword were moved onto it and baked into
`assets/dark/skeleton/skeleton.scn` by `tools/bake_undead.gd`. Used for the skeleton.

Dark Big Ghost (LITE) by SR Studios Kerala, from Fab under the Fab Standard License. Hat removed and
its two clips split into game animations by `tools/bake_undead.gd` (`assets/dark/ghost/`). Used for the
shadow and specter. The original downloads stay outside the project and must not be shared publicly.

The Eightfold Archive (Hadal: Drowned Bellwarden, Hadal Cantor, Ossuary Regent) by Bento Models,
from Fab (check the listing's license terms before any release). LOD2 meshes with 512 px textures and
renamed clips are baked into `assets/dark/<bellwarden|cantor|regent>/` by `tools/bake_boss.gd`.
The original downloads stay outside the project and must not be shared or uploaded publicly.

## Audio

Interface Sounds, Impact Sounds, RPG Audio, UI Audio, Voiceover Pack,
and Voiceover Pack: Fighter by Kenney (www.kenney.nl),
licensed under Creative Commons Zero (CC0). Attribution is not required but appreciated.
Files are in `assets/kenney/audio/<pack>/` with each pack's `License.txt`.
Voiceover Pack voices: Jeffrey M. Smith (male) and Giselle (female), see `voiceover-pack/Credits.txt`.

# Credits

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1")
by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd.
The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International
License, available at https://creativecommons.org/licenses/by/4.0/legalcode.

Changes were made: rules were adapted for a grid-based, turn-based video game
(see `docs/rules.md`, entries marked [변경]).

This project is not affiliated with, endorsed by, or sponsored by Wizards of the Coast.

## 3D models

The full table (source links, license, AI-generated flag, where each pack is used) is in
`docs/assets.md`. Packs marked "not used" below are no longer shown in the game.

Mini Dungeon, Mini Characters, Modular Dungeon Kit, Modular Cave Kit, Survival Kit,
and Nature Kit by Kenney (www.kenney.nl),
licensed under Creative Commons Zero (CC0). Attribution is not required but appreciated.
Files are in `assets/kenney/<pack>/` with each pack's `License.txt`.

Free Rigged Dark Fantasy Knight, Witch and Goblin by Bento Pack (Pedro Bento), from Fab under the
Fab Standard License. Made by the author with generative AI tools. Only the knight's animations and
longsword are still used (moved onto the skeleton); the witch and goblin are not used any more. Reduced for this game
(about 22K triangles, 1024 px textures, a few animation clips) by `tools/bake_dark.gd`;
files are in `assets/dark/<name>/`. The original downloads stay outside the project and
must not be shared or uploaded publicly.

Stylized Dark Fantasy Zombie by Hotstrike Studio, from Fab under the Fab Standard License
(made with generative AI tools). Not used any more. The goblin's animations were moved onto its
skeleton by `tools/retarget.gd` and baked into `assets/dark/zombie/zombie.scn` by
`tools/bake_zombie.gd`.

Stylized Dark Fantasy Skeleton by Hotstrike Studio, from Fab, licensed under Creative Commons
Attribution (CC-BY), made with generative AI tools. The knight's animations and longsword were moved onto it and baked into
`assets/dark/skeleton/skeleton.scn` by `tools/bake_undead.gd`. Used for the skeleton.

Dark Big Ghost (LITE) by SR Studios Kerala, from Fab under the Fab Standard License. Hat removed and
its two clips split into game animations by `tools/bake_undead.gd` (`assets/dark/ghost/`). Not used any more. The original downloads stay outside the project and must not be shared publicly.

Stylized Modular Medieval Dungeon Kit by AZ 3D studio, from Fab under the Fab Standard License.
Not used any more. The sword, shield and spear racks are picked out,
merged and darkened by `tools/bake_props.gd` into `assets/dark/props/`, and stand against dungeon walls.

Stylized Dungeon Props Pack by CobraGamesAssets, from the Unity Asset Store under the Standard Unity Asset
Store EULA (used outside Unity as embedded game content; the package must not be redistributed). Barrels,
crates, pots, a fire bin, bookshelves and chests are unpacked by `tools/unitypackage_extract.py` and baked
by `tools/bake_unity_props.gd` into `assets/dark/props/`. Not used any more.

Universal Animation Library (Standard) by Quaternius, CC0 1.0, from the Godot Asset Store. RPG Animations
GLB FREE by Explosive LLC, MIT License, from the Godot Asset Store. Selected clips (crouch, injured idle,
jump, and the zombie's injured walk, swipes, hit and death) are retargeted onto the dark fantasy
characters by `tools/bake_extra_anims.gd`.

Fantasy Props MegaKit (Standard) by Quaternius, CC0 1.0, from the Godot Asset Store. Baked by
`tools/bake_megakit.gd` into `assets/quaternius/props/` and used to furnish themed dungeon rooms
(library, smithy, alchemy room, storage, barracks, treasury).

Medieval Village MegaKit (Standard) by Quaternius, CC0 1.0, from the Godot Asset Store. Baked by
`tools/bake_village.gd` into `assets/quaternius/village/`: uneven brick walls, corner posts and the
dungeon floor (world-space triplanar, so cell borders do not show) replace the KayKit walls and floor tiles; its stone columns, stairs, fence and brick rubble, plus
Fantasy Props MegaKit crates, barrels, chests, torches, lanterns, banners and candles, replace the other KayKit room props.

Universal Base Characters and Modular Character Outfits - Fantasy (Standard) by Quaternius, CC0 1.0,
from itch.io (quaternius.itch.io). Baked by `tools/bake_heroes.gd` into `assets/quaternius/heroes/`:
the base body's head and hairstyles are put on the Ranger and Peasant outfits for the cleric, barbarian,
rogue, monk, ranger, bard, druid, fighter, paladin, wizard, sorcerer, warlock and villager models
(replacing the KayKit adventurers and the Bento hero models) and the zombie, ghoul, ghast, shadow,
specter and animated armor, animated with
the Universal Animation Library and Explosive RPG clips.

Bestiary - Dungeon Monsters Kit (Standard) by Quaternius, Quaternius Asset License (QAL) v1.0, from
itch.io. Puglin and Imp models (goblin minion/warrior/boss), baked by `tools/bake_heroes.gd`.
The assets may not be redistributed as assets, so they stay out of the public repository.

The Eightfold Archive by Bento Models, from Fab under the Fab Standard License (made with generative
AI tools). Five bosses are used: Drowned Bellwarden (Hadal) and Burr Wheel, Rain
Heron, Silk Grafter, Winter Scion (Glasshouse). The lightest LOD meshes with small
textures and renamed clips are baked into `assets/dark/<name>/` by `tools/bake_boss.gd`.
The original downloads stay outside the project and must not be shared or uploaded publicly.

Ultimate Monsters Bundle and Animated Animal Pack (wolf, fox, husky, bull) and Rat by Quaternius, CC0 1.0,
from poly.pizza. Files are in `assets/quaternius/monsters/` and `assets/quaternius/animals/` with a
`License.txt`. Used for the bat and insect swarms, wolves, rats and the aurochs boss (bull).

Characters - Fantasy Races Kit (Standard) by Quaternius, Quaternius Asset License (QAL) v1.0, from
itch.io. The orc and elf heads are put on the outfits by `tools/bake_heroes.gd` for the orc chief and
ossuary regent bosses. The assets may not be redistributed as assets.

KayKit Dungeon Remastered, Adventurers and Skeletons by Kay Lousberg (www.kaylousberg.com), CC0, from
itch.io. Files are in `assets/kaykit/` with each pack's license. Only the arrow and the fallback dungeon
pieces (used when the Quaternius pieces are not baked) are still used.

Stylized Nature MegaKit (Standard) by Quaternius, CC0 1.0, from the Godot Asset Store. Trees, grass,
flowers and rocks are baked by `tools/bake_nature.gd` into `assets/quaternius/nature/` for the outdoor
terrain prototype.

## Libraries and textures

Terrain3D by Tokisan Games (Cory Petkovsek), MIT License, https://github.com/TokisanGames/Terrain3D.
Installed into `addons/terrain_3d/` (with its `LICENSE.txt`) by `tools/install_terrain3d.sh`.

Ground037 and Rock023 textures by ambientCG (ambientcg.com), CC0 1.0, taken from the Terrain3D demo
into `assets/terrain/`.

EmacEArt Stylized Grass (grass shader with wind) by EmacEArt (https://emaceart.itch.io), free on the Godot
Asset Store under the EmacEArt Asset License (use in projects allowed, no redistribution of the assets).
Installed into `assets/emace_grass/` by `tools/install_emace_grass.sh`; used for the grass on the outdoor terrain and outdoor battle maps.

## Audio

Interface Sounds, Impact Sounds, RPG Audio, UI Audio, Voiceover Pack,
and Voiceover Pack: Fighter by Kenney (www.kenney.nl),
licensed under Creative Commons Zero (CC0). Attribution is not required but appreciated.
Files are in `assets/kenney/audio/<pack>/` with each pack's `License.txt`.
Voiceover Pack voices: Jeffrey M. Smith (male) and Giselle (female), see `voiceover-pack/Credits.txt`.

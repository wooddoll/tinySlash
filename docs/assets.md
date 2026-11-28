# 에셋 출처와 라이선스

게임에 들어간 외부 에셋을 팩마다 한 줄씩 적습니다. 새 에셋을 넣거나 빼면 이 표와 [CREDITS.md](../CREDITS.md)를 같이 고칩니다.
마지막 점검: 2026-11-28 (판매 페이지의 라이선스 칸을 직접 열어 확인함).

- **시제품**: "시제품"은 아직 게임에 연결하지 않고 따로 띄워 보는 것만 된다는 뜻입니다.
- **저장소**: `assets/kenney/`만 공개 저장소에 들어 있습니다. `assets/dark/`, `assets/kaykit/`, `assets/quaternius/`는 `.gitignore`로 빠져 있습니다. 변환 스크립트(`tools/`)만 올립니다.
- **원본**: 받은 원본은 프로젝트 밖 `F:/workspace/fab_downloads/`에 둡니다.
- **상태**: "씀"은 지금 게임 화면에 나온다는 뜻입니다. "대체용"은 구운 파일이 없을 때만 나온다는 뜻입니다. "안 씀"은 파일만 남아 있다는 뜻입니다.

## 표

| 에셋 | 만든 이 | 받은 곳 | 라이선스 | AI 생성 | 게임 폴더 · 변환 | 게임에서 | 상태 |
|---|---|---|---|---|---|---|---|
| SRD 5.2.1 (규칙 글) | Wizards of the Coast | [dndbeyond.com/srd](https://www.dndbeyond.com/srd) | CC-BY 4.0 | 아니요 | `rules/`, `docs/rules.md` | 전투 규칙 | 씀 |
| Fantasy Props MegaKit (Standard) | Quaternius | [Godot 에셋 스토어](https://store.godotengine.org/asset/quaternius/fantasy-props-megakit/) | CC0 | 아니요 | `assets/quaternius/props/` · `tools/bake_megakit.gd` | 방 가구·소품, 보물상자, 손에 든 무기 | 씀 |
| Medieval Village MegaKit (Standard) | Quaternius | [Godot 에셋 스토어](https://store.godotengine.org/asset/quaternius/medieval-village-megakit/) | CC0 | 아니요 | `assets/quaternius/village/` · `tools/bake_village.gd`, `assets/quaternius/town/` · `tools/bake_town.gd` | 던전 벽·바닥·기둥·계단·울타리·잔해, 마을 집(벽·창·문·지붕·굴뚝·수레·상자) | 씀 |
| Universal Animation Library (Standard) | Quaternius | [Godot 에셋 스토어](https://store.godotengine.org/asset/quaternius/universal-animation-library/) | CC0 | 아니요 | `tools/retarget.gd`로 각 캐릭터에 옮김 | 캐릭터 동작 대부분 | 씀 |
| Universal Base Characters (Standard) | Quaternius | [itch.io](https://quaternius.itch.io/universal-base-characters) | CC0 | 아니요 | `assets/quaternius/heroes/` · `tools/bake_heroes.gd` | 직업·마을 사람·언데드의 머리·머리카락 | 씀 |
| Modular Character Outfits - Fantasy (Standard) | Quaternius | [itch.io](https://quaternius.itch.io/modular-character-outfits-fantasy) | CC0 | 아니요 | 위와 같음 | 직업 12종, 마을 사람, 좀비·구울·가스트·섀도·스펙터·움직이는 갑옷 | 씀 |
| Bestiary - Dungeon Monsters Kit (Standard) | Quaternius | [itch.io](https://quaternius.itch.io/bestiary-dungeon-monsters-kit) | **QAL v1.0** | 아니요 | 위와 같음 | 고블린 졸개·전사(퍼글린), 고블린 대장(임프) | 씀 |
| Characters - Fantasy Races Kit (Standard) | Quaternius | [itch.io](https://quaternius.itch.io/characters-fantasy-races) | **QAL v1.0** | 아니요 | `assets/quaternius/heroes/` · `tools/bake_heroes.gd` | 보스 오크 족장(붉은 오크 머리), 납골 섭정(다크엘프 머리) | 씀 |
| Stylized Nature MegaKit (Standard) | Quaternius | [Godot 에셋 스토어](https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/) | CC0 | 아니요 | `assets/quaternius/nature/` · `tools/bake_nature.gd` | 첫 화면 야외 지형의 나무·풀·꽃·바위 | 씀 |
| Terrain3D (플러그인) | Tokisan Games | [Godot 에셋 스토어](https://store.godotengine.org/asset/tokisangames/terrain3d/) | **MIT** | 아니요 | `addons/terrain_3d/` · `tools/install_terrain3d.sh` | 첫 화면 야외 지형 (`scripts/outdoor_terrain.gd`) | 씀 |
| Ground037, Rock023 (지형 텍스처) | ambientCG | [ambientcg.com](https://ambientcg.com/view?id=Ground037) (Terrain3D 데모에 들어 있음) | CC0 | 아니요 | `assets/terrain/` · `tools/install_terrain3d.sh` | 야외 지형 풀밭·절벽 | 씀 |
| EmacEArt Stylized Grass (바람 풀 셰이더) | EmacEArt | [Godot 에셋 스토어](https://store.godotengine.org/asset/emace-art/godot-stylized-vegetation-wind-shader/) | EmacEArt Asset License (무료, 상업 사용 가능, 출처 표기 선택, **재배포 금지**) | 아니요 | `assets/emace_grass/` · `tools/install_emace_grass.sh` | 야외 지형과 바깥 풀밭 전투 바닥의 흔들리는 풀 (`scripts/outdoor_terrain.gd`, `scripts/battle.gd`) | 씀 |
| 배경 음악 3곡: Medieval: Minstrel Dance, Medieval: Exploration (RandomMind), Dungeon Ambience (yd) | RandomMind, yd | [OpenGameArt](https://opengameart.org/content/medieval-minstrel-dance) · [2](https://opengameart.org/content/medieval-exploration) · [3](https://opengameart.org/content/dungeon-ambience) | CC0 | 아니요 | `assets/music/` · `tools/install_music.sh` | 마을·바깥 들판·던전 배경 음악 (`scripts/music.gd`) | 씀 |
| Ultimate Monsters Bundle | Quaternius | [poly.pizza](https://poly.pizza/bundle/Ultimate-Monsters-Bundle-5oyGWAmOB6) | CC0 | 아니요 | `assets/quaternius/monsters/` (원본 glb) | 박쥐 떼(demon), 벌레 떼(armabee), 오크·좀비 등 옛 이름 | 씀 |
| Animated Animal Pack, Rat | Quaternius | [poly.pizza](https://poly.pizza/bundle/Animated-Animal-Pack-ILAPXeUYiS) | CC0 | 아니요 | `assets/quaternius/animals/` (원본 glb) | 늑대, 쥐 떼, 보스 접붙인 들소(황소) | 씀 |
| RPG Animations GLB FREE | Explosive LLC | [Godot 에셋 스토어](https://store.godotengine.org/asset/explosive-llc/rpg-character-animations-pack-free/) | **MIT** | 아니요 | `tools/retarget.gd`로 옮김 | 웅크리기·다친 대기·점프·구르기 등 | 씀 |
| Stylized Dark Fantasy Skeleton | Hotstrike Studio | [Fab](https://www.fab.com/listings/de87148f-4683-48bb-be42-e772a620fb35) | **CC-BY** | 예 | `assets/dark/skeleton/` · `tools/bake_undead.gd` | 스켈레톤 | 씀 |
| The Eightfold Archive (보스 8종) | Bento Models | [Fab](https://www.fab.com/listings/5311167e-f8c4-4f53-ab89-defee5d1a228) | Fab Standard | 예 | `assets/dark/<보스>/` · `tools/bake_boss.gd` (칸토르·섭정·들소는 안 씀) | 던전 보스: 종지기(Hadal), 버어휠·왜가리·실접목사·겨울 접순(Glasshouse) | 씀 |
| Free Rigged Dark Fantasy Knight | Bento Pack (Pedro Bento) | [Fab](https://www.fab.com/listings/04f3294d-4338-4458-a7a9-16f6fc11142c) | Fab Standard | 예 | `assets/dark/knight/` · `tools/bake_dark.gd` | 스켈레톤에 동작·롱소드를 옮길 때만 씀 (굽는 시점) | 간접 |
| Kenney 3D 키트: Mini Dungeon, Mini Characters, Survival Kit, Nature Kit, Modular Cave Kit | Kenney | [kenney.nl](https://kenney.nl/assets) | CC0 | 아니요 | `assets/kenney/<팩>/` (각 팩에 License.txt) | 야외 나무·풀(Terrain3D가 없을 때만), 텐트·모닥불·망치, 동굴 바위. 옛 조각·캐릭터 이름은 새 모델로 바꿔 이어 줌 | 씀 (일부) |
| Kenney 오디오: Interface, Impact, RPG, UI Audio, Voiceover Pack(+Fighter) | Kenney | [kenney.nl](https://kenney.nl/assets) | CC0 | 아니요 | `assets/kenney/audio/` | 효과음, 목소리 | 씀 |
| KayKit Dungeon Remastered | Kay Lousberg | [itch.io](https://kaylousberg.itch.io/kaykit-dungeon-remastered) | CC0 | 아니요 | `assets/kaykit/dungeon/` (원본 glb) | Quaternius 구운 파일이 없을 때 던전 조각 | 대체용 |
| KayKit Adventurers · Skeletons | Kay Lousberg | [itch.io](https://kaylousberg.itch.io/kaykit-adventurers) | CC0 | 아니요 | `assets/kaykit/characters/`, `assets/kaykit/items/` | 화살(`battle.gd`)만. 캐릭터 이름은 새 모델로 이어 줌 | 씀 (화살) |
| Stylized Dark Fantasy Zombie | Hotstrike Studio | [Fab](https://www.fab.com/listings/685ab2d1-8085-4a1a-95aa-10fde20ff772) | Fab Standard | 예 | `assets/dark/zombie/` · `tools/bake_zombie.gd` | — (좀비·구울·가스트는 Quaternius로 바뀜) | 안 씀 |
| Dark Big Ghost (LITE) | SR Studios Kerala | [Fab](https://www.fab.com/listings/794aff54-f020-4b52-a475-e342cb5ec735) | Fab Standard | 아니요 | `assets/dark/ghost/` · `tools/bake_undead.gd` | — (섀도·스펙터는 Quaternius로 바뀜) | 안 씀 |
| Free Rigged Dark Fantasy Witch | Bento Pack (Pedro Bento) | [Fab](https://www.fab.com/listings/5dd6bfd2-a5d2-41f4-aae0-017dbcfa9385) | Fab Standard | 예 | `assets/dark/witch/` · `tools/bake_dark.gd` | — (위저드 등은 Quaternius로 바뀜) | 안 씀 |
| Free Rigged Dark Fantasy Goblin | Bento Pack (Pedro Bento) | [Fab](https://www.fab.com/listings/741a4e6a-cb6e-4c45-a3ed-e1b3c184fafa) | Fab Standard | 예 | `assets/dark/goblin/` · `tools/bake_dark.gd` | — (고블린은 퍼글린·임프로 바뀜. 옛 좀비 동작의 원본) | 안 씀 |
| Stylized Modular Medieval Dungeon Kit | AZ 3D studio | [Fab](https://www.fab.com/listings/16aba7be-963c-4755-9cee-3585f4681e4e) | Fab Standard | 아니요 | `assets/dark/props/` · `tools/bake_props.gd` | — (무기 걸이는 MegaKit 소품으로 바뀜) | 안 씀 |
| Stylized Dungeon Props Pack | CobraGamesAssets | [Unity 에셋 스토어](https://assetstore.unity.com/packages/3d/environments/dungeons/stylized-dungeon-props-pack-310137) | Unity Asset Store EULA | 모름 | `assets/dark/props/` · `tools/bake_unity_props.gd` | — (MegaKit 소품으로 바뀜) | 안 씀 |
| Kenney Modular Dungeon Kit | Kenney | [kenney.nl](https://kenney.nl/assets) | CC0 | 아니요 | `assets/kenney/modular-dungeon-kit/` | 코드에서 부르는 곳 없음 | 안 씀 |

## 라이선스별로 지킬 것

- **CC0**: 아무 조건이 없습니다. 크레딧은 예의로 남깁니다.
- **CC-BY** (해골, SRD): 게임 안이나 함께 배포하는 크레딧에 만든 이, 작품 이름, 라이선스를 적어야 합니다. `CREDITS.md`에 있습니다.
- **MIT** (Terrain3D): 플러그인 폴더의 `LICENSE.txt`를 지우지 말고 배포본에 같이 넣습니다.
- **EmacEArt Asset License** (바람 풀): 게임에 넣어 배포하는 건 되지만 에셋 파일 자체를 따로 나누거나 팔면 안 됩니다. 저장소에는 넣지 않고 설치 스크립트만 둡니다.
- **MIT** (Explosive RPG 동작): 배포본에 저작권 문구와 MIT 허락 문구를 함께 넣어야 합니다. 원문은 받은 팩에 있으니, 출시 전에 `CREDITS.md` 아래에 붙입니다.
- **QAL v1.0** (Bestiary, Fantasy Races): 게임에 넣어 상업적으로 팔아도 되고 크레딧도 필요 없습니다. 대신 모델을 에셋 그 자체로 다시 나눠 주면 안 됩니다. 고쳐도 마찬가지입니다. 그래서 `assets/quaternius/`를 공개 저장소에 올리지 않습니다.
- **Fab Standard License**: 게임에 넣어 배포하는 것은 됩니다. 원본이나 고친 에셋 파일을 따로 나눠 주는 것은 안 됩니다. 개인·소규모와 큰 회사의 등급 구분이 있으니, 매출이 생기면 Fab 약관에서 등급을 다시 봅니다.
- **Unity Asset Store EULA**: 완성된 게임 안에 넣는 것은 되고, 패키지 파일을 다시 나눠 주는 것은 안 됩니다. 지금은 안 쓰므로 출시 전에 파일을 지우는 편이 깔끔합니다.

## 출시 전에 할 일

1. **안 쓰는 파일 정리**
   - 대상: `assets/dark/zombie|ghost|witch|goblin|props`, `assets/kenney/modular-dungeon-kit`.
   - Godot는 기본 설정으로 프로젝트 안 리소스를 모두 내보냅니다. 그래서 지우거나 내보내기 설정에서 빼야 쓰지 않는 Fab·Unity 파일이 배포본에 들어가지 않습니다.
   - `assets/dark/knight`는 스켈레톤을 다시 구울 때만 필요하니 내보내기에서 뺍니다.
2. **생성형 AI 표시**
   - "AI 생성: 예"인 에셋은 해골, 보스 5종, 옛 Bento 캐릭터입니다.
   - 일부 판매처(예: Steam)는 출시 때 AI 생성 콘텐츠를 밝히라고 요구합니다.
3. **MIT 문구**: Explosive RPG의 MIT 문구를 `CREDITS.md`에 붙입니다.
4. **KayKit 정리**: 화살과 대체용 던전 조각만 남았습니다. Quaternius로 바꾸면 KayKit을 통째로 뺄 수 있습니다.

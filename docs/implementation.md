# 구현

[rules.md](rules.md)의 규칙을 코드에서 어떻게 구현했는지, 지금 어디까지 됐는지 적습니다. 남은 일은 [todo.md](todo.md)에 있습니다.

## 1. 구조

| 위치 | 내용 |
|---|---|
| `rules/` | 규칙 엔진. 노드를 쓰지 않는 순수 GDScript(`RefCounted`, `Resource`)라서 화면 없이 테스트할 수 있습니다. |
| `scripts/`, `scenes/` | 화면. 규칙 엔진의 결과를 보여주고 입력을 받습니다. |
| `tests/` | 단위 테스트 |
| `docs/` | 규칙, 구현, TODO 문서 |

### 1.1 규칙 엔진 (`rules/`)
| 파일 | 클래스 | 내용 | 규칙 문서 |
|---|---|---|---|
| `rules.gd` | `Rules` | 능력 수정치, 숙련 보너스, 이점·불리점 상쇄, 내성 DC, XP → 레벨 | 1장 |
| `dice.gd` | `Dice` | 모든 주사위 굴림. 시드 고정, 테스트용 `forced` 값 | 1.3 |
| `weapon_data.gd` | `WeaponData` | 무기 데이터 (Resource) | 4.4 |
| `creature_stats.gd` | `CreatureStats` | 크리처 스탯 블록 (Resource). 화면용 `model`, `weapon_model`, `sprite_scale`(크기)도 여기 | 7, 8장 |
| `catalog.gd` | `Catalog` | 무기, SRD 12 클래스 레벨 1~5 (`CLASSES`, `pc(cls, level)`, 기술 숙련·Expertise 포함, 슬롯 표 `FULL_CASTER_SLOTS`·`HALF_CASTER_SLOTS`·`PACT_SLOTS`), 몬스터 데이터 | 4.4, 7, 8장 |
| `class_features.gd` | `ClassFeatures` | 클래스 기능을 한곳에: 자원(`init_resources`, `resource_labels`, 짧은 휴식 `after_short_rest`·`short_rest_extra`), 스킬 메뉴 행동(`actions`, `use`), 전투 훅(`attack_bonus`, `attack_mods`, `bonus_damage`, `save_adv`, `resists`, `on_hit_taken`, `after_hit`, `on_damaged`, `on_kill`, `on_creature_down`, `on_turn_start/end`, `on_incapacitated`), 반응 자동 사용(`try_shield`, `cutting_words`, `use_inspiration`), Wild Shape(`beast_form`, `wild_shape`, `revert`) | 7.3, 7.7~7.16 |
| `spells.gd` | `Spells` | 모든 클래스의 주문과 Channel Divinity, 자원 기능(level -3). 피해 주문은 `DMG` 표 하나로 (공격·자동·내성, 모양 single/sphere/cone/burst, 부가 효과 `_rider`, `area_targets`), 메타매직(Quickened·Careful), 표식 주문(`MARKS`: Hunter's Mark·Hex). 그 밖에 쓸 수 있는지(`why_not`, `target_error`), 시전(`cast(cb, c, id, t, slot)`), 슬롯 고르기(`slot_levels`, `pick_slot`, `upcast_text`), 집중, Spirit Guardians 범위(`on_step`, `on_turn_end`), 화면 설명 | 7.5, 7.6 |
| `level_up.gd` | `LevelUp` | 레벨업 고르기: 4레벨 능력치 향상(`apply_asi`, AC·HP·이니셔티브 맞춤, `DEFAULT_ASI`), 클래스 주문 목록(`SPELL_LISTS`)과 고를 수 있는 주문(`spell_pool`), 남은 고르기(`pending`). `Catalog.pc(cls, level, choices)`가 `Catalog.build`(빌더 그대로)에 이걸 더함 | 7.17 |
| `action_combat.gd` | `ActionCombat` | 실시간 액션 전투: `Actor`(위치, 상태 idle/windup/recover/dodge/stun/down/dead, AI 종류), `tick`, 공격 판정 `strike`(d20 vs AC, 막히면 파티 절반·몬스터 0), 구르기 무적, 투사체, 몬스터·동료 AI, 방 깨우기, XP 모으기, 쓰러진 파티 일으키기, 클래스 기술 `use_skill`, 물약 | 10 |
| `hero_state.gd` | `HeroState` | 던전 탐험 중 전투 사이에 이어지는 파티원 상태 (`cls`: 12 클래스 중 하나. `party_classes`로 파티 구성을 고름. 레벨업 때 고른 것 `choices`, `pending_choices`, `choose`) | 5.3, 9 |
| `creature.gd` | `Creature` | 전투 중 상태: HP, 상태, 일시 효과, 턴 자원, 주문 슬롯(`slot1`~), 집중(`concentration`, `conc_slot`), 영적 무기 칸(`spirit_cell`), Aid(`aid_bonus`) | 3.3, 6장 |
| `damage.gd` | `Damage` | 피해 수정, 임시 HP, 회복, 사망 내성, 즉사 | 4.2, 5장 |
| `combat_grid.gd` | `CombatGrid` | 높이, 벽, 험지, 점유, 이동 비용, 길찾기, 엄폐 | 2장 |
| `combat.gd` | `Combat` | 이니셔티브, 턴, 행동, 공격 판정, 기회 공격, 무기 숙달, 내성 굴림(`saving_throw`, Bless 포함) | 3, 4장 |
| `monster_ai.gd` | `MonsterAI` | 몬스터 행동 결정 (점수 방식: `target_value`, `priority`, `cover_value`) | 8.1 |
| `dungeon_params.gd` | `DungeonParams` | 던전 생성 파라미터 (Resource) | 9.2 |
| `dungeon_generator.gd` | `DungeonGenerator` | 던전 생성 | 9.2, 9.3 |
| `dungeon.gd` | `Dungeon` | 생성된 던전 데이터, 텍스트 지도, 전투용 지도 잘라내기 | |
| `scenario.gd` | `Scenario` | 시나리오 팩(폴더 + `scenario.json`) 찾기·읽기·합치기, 팩 몬스터, 실행: 층, 방, 문, 조사, 대화, 함정, 수색, 조우, 체크포인트. 결과를 `out` 큐로 내보냄 ([scenario.md](scenario.md)) | |

### 1.2 화면 (`scenes/`, `scripts/`)
| 장면 | 스크립트 | 조작 |
|---|---|---|
| `main.tscn` 탐험 | `main.gd`, `player.gd` | WASD 이동, Space 점프, Q/E 카메라 90° 회전, 휠 줌, B 전투, G 던전 생성기 |
| `battle.tscn` 전투 | `battle.gd`, `unit_view.gd` | 파티원 차례마다 그 캐릭터를 조종. 왼쪽 파티 창. 좌클릭 이동·공격, 1~3 무기, 스킬·주문·아이템 버튼 → 원형 메뉴(숫자 키로도 고름) → 대상 클릭(우클릭·Esc 취소), Enter 턴 종료, F1~F5 조우 바꾸기, R 다시, Esc 돌아가기 |
| `dungeon.tscn` 던전 생성기 | `dungeon_view.gd` | 왼쪽 패널 파라미터, 좌클릭 방 고르기, B 그 방에서 전투, Tab 탐험 모드, Esc 바깥으로 |
| `scenario.tscn` 시나리오 | `scenario_view.gd` | 메인에서 H (팩이 여럿이면 고르기 창). WASD 이동, F 상호작용, R 수색, J 일지, Esc 메인으로. 전투는 그 자리에서 액션 전투(ActionLayer) ([scenario.md](scenario.md)) |
| `dungeon.tscn` 탐험 모드 | `dungeon_view.gd`, `dungeon_explorer.gd` | WASD/왼쪽 스틱 이동, 실시간 액션 전투(rules 10장), Q/E 카메라 회전, 휠 줌, 모닥불 옆에서 Enter 짧은 휴식, 텐트·상인 옆에서 Enter 쉼터 창(긴 휴식, 물약 사기), 출구 계단에서 Enter 다음 층, Tab/Esc 생성기로 |

공통:
- `level_up_dialog.gd`: 레벨업 고르기 창. 던전 생성기·탐험과 시나리오 화면이 0.5초마다 고를 것이 남았는지 보고 띄웁니다(떠 있는 동안 이동 멈춤). 능력치 향상은 +2 하나 또는 +1 둘, 주문은 후보 목록에서 하나, 고르면 바뀌는 능력치·AC·최대 HP를 미리 보여 줌.
- `camera_rig.gd`: 아이소메트릭 카메라입니다. 직교 투영, 30° 내려다보기, 45° 회전이고, `isometric`을 끄면 원근 시점이 됩니다.
- `character_model.gd`: 3D 캐릭터 하나. 모델 경로는 "팩/이름"으로 `kaykit/…`(KayKit 캐릭터), `quaternius/…`(Quaternius 몬스터), `animals/…`(Quaternius 동물), 그 밖은 Kenney입니다. 끝에 `*3`처럼 수를 붙이면 작은 몸 여럿을 한 칸에 모아 세우는 떼가 됩니다(`animals/rat*3`). 몸마다 방향과 동작 빠르기가 조금씩 달라 함께 움직여도 똑같아 보이지 않습니다. 나는 떼(박쥐)는 몸마다 높이가 달라(`SWARM_LIFT`) 따로 출렁이고, 쓰러지면 모두 바닥으로 내려앉습니다. 옛 Kenney 캐릭터 이름(`mini-characters/character-knight` 등)은 `ALIASES`로 새 모델에 이어져 예전 시나리오 팩도 그대로 돕니다. 엔진은 `idle`, `walk`, `sprint`, `crouch`, `die`, `jump`, `hit`, `attack-melee-right`, `holding-right-shoot` 같은 이름으로 부르고, `ANIMS` 표가 팩마다 다른 실제 이름(`Walking_A`, `CharacterArmature|Walk`, `Fast_Flying` 등)으로 바꿉니다. KayKit은 쥔 무기에 따라 양손·맨손 공격, 쇠뇌, 주문 동작을 고릅니다. Kenney 아닌 모델은 보이는 메시 키를 재서 1.28 유닛에 맞추고, 잘못 재지는 모델만 `RAW_HEIGHT`에 키를 적습니다. 기본 동작은 반복하고, 공격·피격은 한 번 하고 돌아오며, 쓰러지면 die 자세로 멈춥니다. 맞으면 붉게 번쩍이고 `tint`로 몸 색을 곱합니다.
  - 무기: Kenney 모델은 `weapon_model` "팩/이름" 하나를 오른팔 뼈에 붙입니다. KayKit 모델은 "+"로 이은 장비 이름입니다. 모델 안에 든 장비(예: Knight의 `2H_Sword`, `Rectangle_Shield`)는 그것만 보이게 하고, 없는 것은 `assets/kaykit/items/<이름>.gltf`를 손 뼈(`handslot.r`, 방패는 `handslot.l`)에 쥐어 줍니다.
- 탐험 분위기 (`dungeon_view._set_mood`): 탐험 중에는 해를 달빛처럼 약하게(그림자 끔), 주변광·배경을 어둡게, 안개. 주인공이 등불(OmniLight, 그림자 없음)을 들고, 카메라 쪽 보조광이 캐릭터(렌더 층 2, `CharacterModel.CHAR_LAYER`)만 비춥니다. 생성기 화면은 원래 밝기.
- `tools/bake_dark.gd`: Fab 다크 판타지 캐릭터(기사, 마녀, 고블린)를 가볍게 굽는 도구. 원본(`F:/workspace/fab_downloads/src`)에서 텍스처를 1024(ORM 512)로 줄이고, Godot LOD 생성으로 삼각형을 약 1만 6천 개로 줄이고(무기는 그대로, weapon_r 뼈에 붙임), 동작 10개만 골라 루트 이동을 빼고 길이를 맞춰 `assets/dark/<이름>/<이름>.scn`으로 저장. `character_model.gd`에서 "dark/knight"처럼 씁니다. 파이터·팔라딘·움직이는 갑옷=기사, 위저드·소서러·워락=마녀, 고블린 셋=고블린.
- `tools/sim_action.gd`: 액션 전투 난이도 시뮬레이션. 실제 생성기 던전의 조우를 파티(플레이어 봇 + 동료 AI)가 싸워 보고, 구르기 실력(예고를 보고 구를 확률)별로 승률·시간·잃은 HP를 냅니다. `-- 던전수 fighter,cleric`. 2026-11-27 결과(Lv1~3, 파이터+클레릭, AI 개선 뒤): 안 구르면 싸움마다 HP 9~13%, 90% 구르면 4~8%, 한 싸움 3~4초. 몬스터 HP 1.5배 뒤: 안 구르면 HP 17~22%(Lv1~2에서 3% 짐), 90% 구르면 6~14%(모두 이김), 한 싸움 4~7.5초, 플레이어 휘두르기 5~7번. `-- 20 fighter,cleric boss`는 출구 보스 방만 Lv2~4로 싸움: 이김 85~95%, 잃은 HP 12~40%, 한 싸움 6.5~13초 (2026-11-27). 턴제 전투(단독 전투의 T 키, 던전 지도 화면의 방 전투)는 `rules/monster_ai.gd` 점수 AI, 액션 전투는 `action_combat.gd`의 실시간 AI(대상 점수, 동시 공격 2마리, 둘러싸기, 도망, 동료 구르기)를 씁니다.
- `tools/bake_boss.gd`: 보스 모델(Bento "The Eightfold Archive" Hadal 셋)을 LOD2 + 512px 텍스처 + 엔진 이름 동작으로 `assets/dark/<이름>/<이름>.scn`에 굽습니다. 원본은 프로젝트 밖 `F:/workspace/fab_downloads/bosses`.
- `tools/retarget.gd`: 쉬는 자세가 다른 뼈대로 동작을 옮기는 도구. 뼈마다 '자식 관절을 향하는 방향'을 원본과 같게 돌리고, 골반은 위·옆 방향으로 몸통 방향을 맞춥니다(좌우 회전은 뺌). 두 모델이 바라보는 방향이 달라도 align 회전으로 맞춥니다. 트리 밖 뼈대는 전역 자세가 갱신되지 않으므로 지역 자세로 직접 계산합니다.
- `tools/bake_zombie.gd`: `assets/dark/zombie/szombie.glb`(CC 뼈대, 동작 없음)에 고블린 동작을 옮겨 `zombie.scn`으로 굽습니다. 좀비·구울·가스트가 색만 바꿔 씁니다.
- `input_setup.gd`: 입력 맵을 코드로 등록합니다. 키보드와 Xbox 배치 게임패드(버튼, 왼쪽 스틱 데드존 0.2).
- `action_layer.gd`: 탐험 중 실시간 전투 화면. 입력을 카메라 기준으로 읽어 `ActionCombat`에 넘기고, 모델 위치·동작, HP 막대, 몬스터 준비 고리, 피해 숫자, 투사체, 효과음을 맞춥니다. 싸움이 끝나면 `fight_over(xp)`, 모두 쓰러지면 `defeated`.
- `party_panel.gd`: 화면 왼쪽 파티 창. 파티원마다 초상화, HP 바(숫자 `현재/최대`, 임시 HP), 버프·디버프 칩(초록 버프, 빨강 디버프, 회색 정보, 마우스를 올리면 설명). 지금 차례인 파티원은 금색 테두리, 쓰러지면 초상화가 어두워집니다.
  - 초상화는 파티원마다 작은 `SubViewport`(따로 쓰는 3D 월드)에 캐릭터 모델과 카메라를 놓고 그 텍스처를 씁니다. 그래서 대기 애니메이션이 움직입니다.
  - 전투에서는 `battle.gd`의 `effects_of(creature)`가 상태(의식 없음, 넘어짐, 사망 내성, 안정)와 효과(Bless, Shield of Faith, 회피, Vex, Guiding Bolt, Sap, Slow, Turn Undead, 집중)를 칩으로 만듭니다. 이벤트를 재생할 때마다 갱신합니다.
  - 던전 탐험 중에도 왼쪽에 뜹니다 (HP가 절반 이하면 "다침").
- 전투 화면의 주문 표시: 영적 무기는 클레릭의 무기 모델을 크게 띄워 빛나게 하고, 공격할 때 그 무기가 대상에게 날아듭니다. Spirit Guardians는 시전자 3칸 안의 칸마다 옅은 금색 판을 깝니다.
- `radial_menu.gd`: 원형 선택 메뉴. 항목을 원 위에 늘어놓고, 마우스를 올리면 옆에 설명(쓸 수 없으면 이유)을 보여줍니다. 바깥 클릭, 우클릭, Esc로 닫고 1~9로 고릅니다.
  - 전투 아래 줄: 무기 버튼(일반 공격) | 스킬 · 주문 · 아이템 | 턴 종료.
  - 스킬: 질주, 이탈, 회피, Second Wind, Action Surge, Channel Divinity. 주문: 소마법과 슬롯 주문 (영적 무기가 떠 있으면 "영적 무기 공격"도). 쓸 수 있는 슬롯 레벨이 여럿이면 슬롯 고르기 원형 메뉴가 한 번 더 열립니다. 아이템: 회복 물약. 해당 항목이 없는 분류 버튼은 숨깁니다.
- `kenney.gd`: `assets/kenney/`의 GLB 모델에서 메시를 꺼내 줍니다. 동굴 소품, 나무, 풀 목록과 칸 좌표로 변형을 고르는 `pick`도 있습니다. Nature Kit은 가져온 색이 한 번 더 밝아져 있어 sRGB→선형으로 되돌리고, 원래 청록색인 잎과 풀(`leafsGreen`, `leafsDark`, `grass`)은 녹색으로 바꿉니다 (`_recolor`).
  - Mini Dungeon 이름(`floor`, `column`, `table`, `chest`, `stairs`, `banner` …)은 `SWAP` 표를 따라 KayKit Dungeon Remastered 조각으로 바뀝니다. 크기와 원점을 메시에 구워 넣어(`_bake`, SurfaceTool) 부르는 쪽은 예전처럼 1x1 칸 기준으로 씁니다. 바닥 변형은 `FLOOR_DETAILS`(깨진 타일, 풀 난 타일). KayKit 상자는 애니메이션이 없어 뚜껑을 여는 "open" 동작을 만들어 붙입니다.
  - 방 던전 벽은 `_kaykit_walls`: 칸 모서리 가운데에 KayKit 벽판(1/4 크기, 높이 1)을 세우고 일곱에 하나쯤은 금 간 벽, 가로·세로 벽이 만나는 꼭짓점에는 가는 기둥을 세웁니다. 동굴 벽은 그대로 Modular Cave Kit이고, 동굴 바닥은 KayKit 흙바닥(`CAVE_FLOORS`, 풀 난 흙 섞음)입니다.
  - 꾸미기 `decorate`: 칸 좌표로 정해서 같은 맵은 늘 같은 모습입니다. 방 던전은 벽면에 횃불(주황 불빛 OmniLight3D, 범위 2.6, 불꽃 둘레에 늘 카메라를 보는 빛무리. `torch_flicker.gd` 노드 하나가 모든 횃불의 밝기와 빛무리를 사인파 몇 개로 흔듦), 깃발, 촛불 선반을 걸고, 벽 앞 바닥에 촛대·병·접시 같은 작은 잡동사니를 둡니다. 동굴은 버섯과 작은 돌만 둡니다. 문·표식·장애물·험지·물·보물·모닥불 칸은 비워 둡니다. 탐험(던전, 시나리오)과 던전 전투 모두 씁니다. 장식과 불빛도 전장의 안개를 따릅니다.
  - 시나리오의 닫힌 문은 KayKit 문틀(`wall_doorway`), 드러난 비밀문은 금 간 벽, 잠긴 문에는 금빛 손잡이를 붙입니다.
- 전투 연출 (`battle.gd`): 근접 공격은 앞으로 내딛고, 원거리 공격은 KayKit 화살이 낮은 포물선으로 날아갑니다 (빗나가면 대상 옆을 지나 떨어짐). 적에게 거는 주문은 빛을 내는 구슬이 날아가 터집니다. 쓰러지면 쓰러지는 동작을 마친 뒤 바닥으로 가라앉습니다. 전투 기록은 오른쪽 위 작은 창(스크롤로 지난 기록)입니다.
- 시나리오 글·대화 창은 화면 아래쪽에 띄워 가운데의 파티를 가리지 않습니다.
- `sfx.gd`: 효과음. 전투(휘두르기, 명중, 치명타, 빗나감, 쓰러짐, 회복, 발소리, 시작 "Fight", 승리·패배·레벨 업 음성), 탐험(발소리 0.6유닛마다, 상자와 금화, 몬스터 발견, 계단, 모닥불 휴식), 모든 버튼 클릭.
- `dungeon_explorer.gd`: 던전 안을 걷는 플레이어입니다. `actor`가 있으면(액션 전투) 입력 대신 그 Actor 위치를 따라가며 칸 이벤트만 냅니다. 물리 엔진 대신 던전 격자로 충돌을 봅니다. 반지름 0.28 원의 네 귀퉁이가 모두 서 있을 수 있는 칸이어야 하고, 축마다 따로 시험해서 벽을 따라 미끄러집니다. 높이는 지금 칸의 바닥 높이를 따라갑니다 (0.5, 1.0 단상도 걸어서 오름).

### 1.3 에셋 (모두 CC0)

캐릭터와 몬스터 (`assets/kaykit/`, `assets/quaternius/`):

| 팩 | 받은 곳 | 쓰는 곳 |
|---|---|---|
| KayKit Adventurers 1.0 (Kay Lousberg) | GitHub KayKit-Game-Assets | 파이터(`Knight`, `2H_Sword`), 클레릭(`Mage`, `2H_Staff`), 움직이는 갑옷(어둡게 칠한 `Knight`), NPC |
| KayKit Skeletons 1.0 | GitHub KayKit-Game-Assets | 스켈레톤(`Skeleton_Minion` + `Skeleton_Blade`), 좀비(초록으로 칠한 `Skeleton_Minion`, 맨손), 하르발(`Skeleton_Warrior`) |
| KayKit Dungeon Remastered 1.0 | GitHub KayKit-Game-Assets | 동굴 흙바닥, 벽 장식(횃불, 깃발, 촛불 선반), 바닥 잡동사니(촛대, 병, 접시), 방 던전의 바닥 타일, 벽, 벽 기둥, 문, 기둥(`pillar`), 가구(`table_small`, `barrel_small`, `chair`, `keg`, `box_large`), 잔해(`rubble_half` 납작하게), 상자(`chest`), 계단, 깃발, 함정 가시 (`kenney.gd`의 `SWAP`) |
| Quaternius Ultimate Monsters (45개) | poly.pizza 묶음 (glb) | (고블린·좀비·구울·가스트는 이제 dark 모델) 섀도(`ghost`), 스펙터(`ghost_skull`), 박쥐 떼(`demon*3`), 벌레 떼(`armabee*3`) |
| Quaternius Animated Animal Pack + Rat | poly.pizza (glb, CC0) | 늑대(`wolf`, 걷기·질주·물기·피격·쓰러짐), 쥐 떼(`rat*3`). 여우·허스키도 받아 둠 |

던전, 소품, 효과음 (`assets/kenney/`):

| 팩 | 크기 기준 | 쓰는 곳 |
|---|---|---|
| Mini Dungeon | 바닥 1×1 유닛, 격자 칸과 같음 | 이름만 씀: 모델은 KayKit 조각으로 바뀜 (`SWAP`에 없는 것만 Kenney 그대로) |
| Mini Characters | 키 약 0.8 유닛(1.6배로 키워 씀), 애니메이션 32종 | 예전 캐릭터 (지금은 `ALIASES`로 KayKit·Quaternius 모델로 바뀜). 영적 무기는 Survival Kit `tool-hammer` |
| Modular Cave Kit | 4 유닛 단위 큰 조각 | 동굴 던전의 벽을 1/4로 줄여 씀 |
| Survival Kit | 작은 소품 (모닥불 2.6배, 텐트 1.7배로 키워 씀) | 던전 모닥불(`campfire-pit`), 쉼터 텐트(`tent-canvas`) |
| Nature Kit | 작은 소품 (나무 2.0~2.8배, 전투 나무 1.5배) | 동굴의 기둥(`rock_tall*`, 세로 1.7배), 바위(`rock_large*`, 세로 2.6배), 잔해(`rock_small*`). 바깥 장면과 바깥 전투의 나무, 풀, 꽃, 그루터기·버섯·통나무 |

오디오 (`assets/kenney/audio/<팩>/`, OGG). `scripts/sfx.gd`가 그룹별로 파일 하나를 골라 음높이를 ±8% 바꿔 틉니다. 재생기는 트리 루트에 붙여서 장면이 바뀌어도 끝까지 들립니다.

| 팩 | 들어 있는 것 | 쓸 만한 곳 |
|---|---|---|
| Impact Sounds (130) | 발소리(카펫, 콘크리트, 풀, 눈, 나무), 금속·나무·유리·판금·주먹 충돌음 | 명중, 방어구에 막힘, 발소리 |
| RPG Audio (51) | 문 열기·닫기, 칼 뽑기·베기, 동전, 책, 천, 발소리 | 상자 열기, 금화, 무기 휘두르기, 문 |
| Interface Sounds (100) | 클릭, 확인, 오류, 열기·닫기, 스크롤, 토글 등 | 메뉴, 버튼, 휴식 창 |
| UI Audio (51) | 클릭, 마우스 오버, 스위치 | 버튼 |
| Voiceover Pack (남·여 각 46) | "ready", "go", "level up", "you win/lose", "game over", 숫자 등 | 레벨 업, 승리·패배 |
| Voiceover Pack: Fighter (46) | 대전 격투 아나운서 대사: "fight", "round 1", "flawless victory", "you win" 등 | 전투 시작, 승리. 캐릭터 기합 소리는 아님 |

**벽 그리는 방식**: 벽 칸을 상자로 채우지 않고, 바닥 칸과 벽 칸 사이 모서리마다 얇은 벽판을 세웁니다 (`kenney.gd`의 `build_edge_walls`). 바닥끼리 맞닿은 볼록한 모서리에는 모서리 조각을 놓습니다. 규칙상 벽 칸은 그대로 높이 3.0의 통과 불가 칸입니다.

팩마다 GLB 모델, `Textures/colormap.png`, `License.txt`, `Preview.png`만 넣었습니다 (FBX, OBJ는 뺌).

## 2. 설계

- **규칙과 화면 분리**: `Combat`은 `event` 시그널로 사전(dictionary)을 내보냅니다. 종류는 `log`, `turn_start`, `move`, `teleport`, `attack`, `cast`, `hp`, `condition`, `death`, `fled`, `end`입니다. `battle.gd`는 이벤트를 큐에 쌓아 두고 하나씩 트윈 애니메이션으로 재생합니다.
- **주사위**: 모든 굴림이 `Dice` 하나를 거칩니다. 시드를 고정하거나 `forced`에 값을 넣으면 결과가 정해지므로 테스트할 수 있습니다.
- **일시 효과**: `Creature.effects`에 `{type, owner, phase, skip, target}` 형태로 저장합니다. owner의 턴 시작이나 끝(phase)에 skip이 0이면 사라집니다. 회피, Sap, Slow, Vex가 이 방식입니다.
- **데이터**: `WeaponData`, `CreatureStats`는 `Resource`이지만, 지금은 `.tres` 파일 대신 `catalog.gd` 코드로 만듭니다.
- **격자**: `GridMap`이나 `AStarGrid2D` 대신 `CombatGrid`의 Dictionary(칸 → 높이·벽·험지·점유)를 씁니다. 길찾기는 높이·험지·적 칸 비용을 넣은 다익스트라입니다.

### 2.1 규칙 문서와 구현 방식이 다른 부분
| 규칙 | 구현 |
|---|---|
| 2.1 거리 | `max(dx, dy, ceil(dh - 0.001))`. 부동소수 오차 때문에 0.001을 뺍니다. |
| 2.1 높이차 | 한 걸음 높이차가 1.0을 넘으면 오르기와 내려가기 모두 막습니다 (낙하 미구현). 0.5 초과 1.0 이하 오르기는 2칸 비용입니다. |
| 2.4 엄폐 판정 | 공격자 눈높이(지면 +1.0)에서 대상 몸의 네 점(좌우 ±0.3, 높이 0.3과 1.1)으로 광선 4개를 쏩니다. 막힌 광선이 4개면 완전, 3개면 3/4, 1~2개면 절반입니다. 광선이 다른 크리처를 지나면 최소 절반입니다. 높이를 반영하려고 모서리 대신 몸의 점을 씁니다. |
| 3.5 플레이어 기회 공격 | 항상 자동입니다 ("매번 묻기" 옵션 없음). |
| 3.1 탐험에서 전투로 | 감지와 기습 없이, 던전 탐험 중 정리하지 않은 몬스터 방의 칸에 들어서면 바로 전투가 시작됩니다. 바깥 탐험 장면은 아직 B 키로 엽니다. |

## 3. 구현 현황

| 구현됨 |
|---|
| d20 판정, 이점·불리점 상쇄, 주사위 20/1, 치명타 |
| 격자 이동: 험지, 오르기, 벽 모서리, 적 칸 통과 규칙, 이동 경로의 기회 공격 칸 표시 |
| 엄폐 (광선 4개 방식), 사거리, 장거리·근접 불리점 |
| 기회 공격, 이탈, 질주, 회피, Second Wind, Action Surge, 물약 |
| 동료 클레릭: 주문 10종(2레벨 Aid, Spiritual Weapon, 3레벨 Spirit Guardians 포함), Channel Divinity 3종, 집중, Bless, 슬롯 주문 턴당 1개, 슬롯 고르기 |
| 무기 숙달: Graze, Sap, Slow, Vex, Topple, Push, Cleave |
| 저항·취약·면역, 임시 HP, 사망 내성, 즉사 |
| 몬스터 14종과 특성 (Pack Tactics, Redirect Attack, Nimble Escape 등), AI |
| 이니셔티브 동점 처리, 승리·패배, XP |
| 던전 생성기 (BSP / 흩뿌리기 / 동굴), SRD XP 예산 조우, 보물, 방에서 전투 시작 |
| 던전 탐험: 걸어 다니다 몬스터 방에 들어서면 전투, 보물 상자 열기, 출구 계단으로 다음 층 |
| 던전 탐험 중 전투 사이 상태 유지 (HP, 물약, Second Wind, Action Surge, XP)와 레벨업 |
| 히트 다이스, 모닥불 짧은 휴식 |
| 효과음 (Kenney 오디오) |
| 전장의 안개, 층이 깊을수록 조우 예산 증가 |
| 쉼터: 긴 휴식, 저장, 지면 마지막 저장으로 돌아가기 |
| 쉼터 상인: 금화로 회복 물약 사기 |
| 아이소메트릭 카메라, Kenney 3D 지형, KayKit·Quaternius 캐릭터 (애니메이션) |
| 시나리오 모드: JSON 모험 엔진과 오리지널 모험 「소금바람 저택」 |
| 언데드·스웜 몬스터 9종 (좀비, 구울, 가스트, 섀도, 스펙터, 움직이는 갑옷, 쥐·박쥐·벌레 떼): 마비, Undead Fortitude, STR 흡수, 스웜 |
| 기술 숙련과 패시브 Perception |

아직 안 된 것은 [todo.md](todo.md)를 보세요.

## 4. 던전 생성

같은 시드와 같은 파라미터를 넣으면 언제나 같은 던전이 나옵니다. 그래서 난수는 모두 생성기의 `rng`에서 꺼냅니다. 배열 섞기도 전역 난수를 쓰는 `Array.shuffle()` 대신 `_shuffle()`을 씁니다.

### 4.1 생성 순서
1. **방 배치**: 세 가지 방식 중 하나.
   - BSP: 가장 큰 구역부터 반씩 나눠 `room_count`개의 구역을 만들고, 구역마다 방 하나를 놓습니다.
   - 흩뿌리기: 방 사이에 벽 2칸 이상을 두고 무작위로 놓아 봅니다. 방 개수 × 60번까지 시도합니다.
   - 동굴: 셀룰러 오토마타(4-5 규칙, 5회)로 동굴을 만들고, 작은 웅덩이는 메웁니다. 떨어진 동굴은 목표 쪽으로 70% 확률로 다가가는 굴로 잇습니다. 바닥은 서로 먼 씨앗 칸을 골라 가까운 씨앗별로 구역(방)을 나눕니다.
2. **방 잇기** (BSP, 흩뿌리기):
   - 최소 신장 트리(Prim)로 모든 방을 잇습니다.
   - 각 방에서 가까운 방 2개 중 아직 안 이어진 쪽에 `loop_chance` 확률로 길을 더 놓습니다.
   - 복도는 ㄱ자입니다. 폭 1 복도가 방에 들어가는 칸은 문입니다 (보기용이고, 규칙상 바닥과 같음).
3. **시작과 출구**: 아무 방에서 가장 먼 방, 거기서 가장 먼 방을 고릅니다. 바닥 BFS 거리로 각 방의 깊이(0~1)를 기록합니다.
4. **지형**:
   - 기둥(높이 3.0)과 바위(높이 1.0)는 주변 8칸이 모두 같은 방 바닥이고 다른 장애물이 붙어 있지 않은 칸에만 놓습니다. 그래서 길이 막히지 않습니다. 방 중심, 시작, 출구 칸은 피합니다.
   - 단상: 0.5 높이이고, 넓으면 가운데를 1.0으로 올립니다. 동굴은 노이즈로 0 / 0.5 / 1.0 높이를 줍니다. 한 걸음 높이차가 1.0을 넘지 않습니다.
   - 잔해(험지)는 작은 덩어리로 흩뿌립니다.
5. **조우**: 규칙 문서 9.2. 몬스터는 문과 복도 바로 옆을 피해 한 기준 칸 주변에 뭉쳐 놓습니다.
6. **보물**: 규칙 문서 9.3. 벽에 많이 붙은 칸(구석)을 고릅니다.
7. **모닥불** (`campfire_count`, 기본 1): 몬스터 없는 보통 방을 깊이 순으로 늘어놓고 고르게 골라, 방 가운데에 가까운 빈 칸에 놓습니다. 그런 방이 없으면 몬스터 없는 아무 방(시작 방 포함)에 놓습니다. 난수를 쓰지 않아서 기존 던전 내용은 바뀌지 않습니다.

### 4.2 전투로 넘어가기
`Dungeon.battle_setup(room_id)`가 `battle.gd`의 `custom`에 넘길 사전을 만듭니다.
- 방 둘레 2칸까지 잘라서 전투 지도 문자열을 만듭니다. 던전 벽은 `X`, 기둥은 `P`이고, 둘 다 격자에서 높이 3.0 벽입니다. 화면에는 보기 편하게 낮은 벽으로 그립니다.
- 플레이어는 던전 시작 지점에서 방까지 걸어온 길이 지도 안으로 처음 들어오는 칸에 섭니다.
- 탐험 중에는 `battle_setup(room_id, entry)`로 플레이어가 방에 들어선 칸을 넘겨서 그 칸에서 전투를 시작합니다.
- 전투가 끝나면 `battle.gd`가 `custom["result"]`에 `win` 또는 `lose`를 남깁니다. 던전 화면으로 돌아오면 이긴 방을 "정리함"으로 표시합니다. 파라미터를 바꾸면 이 기록은 초기화됩니다.
- 탐험 중 전투에서 돌아오면:
  - 이김: 방에 들어선 칸에서 계속합니다.
  - 짐: 던전 시작 지점으로 돌아갑니다 (체크포인트 규칙 3.6 대신 임시).
  - Esc로 도망: 방에 들어서기 직전 칸으로 돌아갑니다. 다시 들어가면 같은 전투가 처음부터 시작됩니다.
- 파티 상태는 `rules/hero_state.gd`(`HeroState`)가 파티원마다 하나씩 들고 있습니다 (`dungeon_view.gd`의 `hero` 파이터, `ally` 클레릭, `party()`).
  - 전투 장면은 `custom["party"]`가 있으면 그걸로 PC들을 만들고(`make_creature`), 이기거나 도망치면 결과를 다시 담습니다(`absorb`). 없으면(단독 전투) 고른 파티를 1레벨로 싸웁니다. 단독 전투는 기본이 실시간 액션 전투(`battle.gd`의 `_start_action`: 같은 맵을 `Dungeon`으로 바꿔 `ActionLayer`를 얹음)이고, T 키로 턴제와 바꿉니다.
  - 첫 파티원은 들어선 칸에, 나머지는 그 근처 빈 칸 중 적에게서 먼 칸에 섭니다 (`_free_cell_near`).
  - XP는 파티 인원수로 나눠 각자 더합니다.
  - 이어지는 것: HP, 물약, Second Wind, Action Surge, 주문 슬롯, Channel Divinity, XP. 임시 HP, 상태 이상, 집중은 이어지지 않습니다.
  - 이겼는데 쓰러져(또는 죽어) 있었으면 HP 1로 일어납니다.
  - 이긴 전투는 R로 다시 할 수 없습니다 (XP가 두 번 쌓이지 않게). 진 전투는 R로 전투 시작 때 상태로 다시 할 수 있습니다.
  - 전투 중 Esc로 도망치면 그때 HP와 사용 횟수를 가져갑니다. 모두 쓰러진 채로 도망치면 패배입니다.
  - 지면 마지막 저장(쉼터)으로 돌아갑니다 (아래 "쉼터").
  - 레벨업: XP가 문턱을 넘으면 그 레벨의 스탯(`Catalog.pc(cls, level)`)으로 다시 만듭니다. 늘어난 최대 HP만큼 회복하고, 새로 생기거나 늘어난 사용 횟수(Action Surge, Second Wind, 주문 슬롯, Channel Divinity)를 더합니다. 5레벨까지입니다.
  - 다음 층으로 내려가면 생성기의 파티 레벨과 인원을 파티에 맞춰 몬스터 예산을 정합니다. 파티 인원 기본값은 2입니다.
  - 히트 다이스: `hit_dice_spent`만 저장하고 남은 수는 `레벨 - 쓴 수`입니다. 그래서 레벨이 오르면 1개 늘어납니다.
- 짧은 휴식: 켜진 모닥불 옆 칸(대각선 포함)에서 Enter를 누르면 휴식 창이 열립니다.
  - Enter로 히트 다이스를 1개씩 굴립니다 (`spend_hit_die`). 쓸 수 있는 파티원 중 HP 비율이 가장 낮은 사람이 굴립니다 (`_rest_target`).
  - Esc나 Tab으로 마치면 Second Wind 1회, Action Surge, Channel Divinity 1회가 돌아오고(`finish_short_rest`), 모닥불이 꺼집니다.
- 쉼터(세이브 지점): 1, 4, 7…층(`SAVE_EVERY = 3`) 시작 방에서 시작 칸에 가장 가까운 빈 칸에 텐트(Survival Kit `tent-canvas`)를 놓습니다 (`shelter_cell`).
  - 저장(`save`): 생성 파라미터(시드 포함), 층, 파티 상태(`hero`, `ally`), 금화, 긴 휴식 여부. 탐험을 시작할 때, 쉼터 층에 도착할 때, 긴 휴식을 할 때 씁니다.
  - 텐트 옆에 상인(Mini Characters `character-worker`)이 섭니다. 텐트와 상인 칸은 지나갈 수 없습니다 (`Explorer.blocked`).
  - 텐트나 상인 옆에서 Enter: 쉼터 창. 긴 휴식(`HeroState.long_rest`, 쉼터마다 한 번)과 물약 사기(50골드, 최대 5개, `HeroState.buy_potion`). 둘 다 하고 나면 저장합니다.
  - 지면(`_load_save`): 저장한 파라미터로 그 층을 다시 만들고, 정리한 방·연 상자·쓴 모닥불·본 칸을 지우고, 파이터 상태와 금화를 되돌립니다. 생성기 슬라이더도 그 값으로 바뀝니다.
- 전장의 안개: 탐험 중에는 본 칸만 그립니다.
  - 방에 들어서면 방 전체가, 통로에서는 바닥을 따라 3걸음 안의 칸이 보입니다 (`visible_from`).
  - 던전은 칸마다 무엇이 그려졌는지 기록해 둡니다 (`_fog_index`: MultiMesh 조각 번호 또는 노드). 안 본 칸의 MultiMesh 조각은 크기 0 변환으로, 노드는 `visible = false`로 숨깁니다. 그래서 던전을 다시 만들지 않고 칸 단위로 드러냅니다.
  - 벽판과 모서리 조각은 붙어 있는 바닥 칸에 속합니다. 생성기 화면에서는 전부 보입니다.
  - 본 칸은 static이라 전투에 다녀와도 남고, 새 층이나 파라미터를 바꾸면 지워집니다.
- 층 깊이: `DungeonParams.floor_depth`. 다음 층으로 내려갈 때 층 수와 파이터 레벨을 생성기 파라미터에 넣고 슬라이더도 맞춥니다.
- 동료 모델: 탐험 중 클레릭이 플레이어가 지나간 길을 0.9유닛 뒤에서 따라 걷습니다 (`_update_follower`). 충돌은 없고 화면에만 있습니다.
- 탐험 상태(위치, 정리한 방, 연 상자, 금화, 층, 파티 상태, 본 칸)는 `dungeon_view.gd`의 static 변수라서 장면을 오가도 남습니다. 상자는 옆 칸(대각선 포함)에 서면 열립니다. 출구 계단에서 Enter를 누르면 같은 파라미터에 새 시드로 다음 층을 만듭니다.

## 5. 테스트

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
```

- `tests/test_rules.gd`: 규칙 엔진 31개 (수정치, 치명타, 피해 순서, 엄폐, 기회 공격, 무기 숙달, AI 전투 등)
- `tests/test_crowwatch.gd`: 「꺼진 봉화」 진행 (대화로 푸는 길, 그락과 싸우는 길, 등잔 없이 봉화, 일찍 떠나는 결말, 우물 밧줄)
- `tests/test_scenario.gd`: 데이터 검사는 모든 팩에 돌림.  시나리오 엔진과 새 몬스터 규칙 (데이터 연결, 도달 가능, 문·함정·수색, 대화 판정, 전투 연결, 체크포인트, 처음부터 끝까지 진행, 마비·스웜·Undead Fortitude 등)
- `tests/test_dungeon.gd`: 던전 생성기와 탐험 27개 (같은 시드 재현, 모든 방 도달 가능, XP 예산, 높이차, 전투 지도, 들어선 칸에서 전투 시작, 탐험 충돌, 전투 사이 상태와 레벨업, 모닥불 배치, 짧은·긴 휴식, 효과음 파일 존재, 층 깊이 예산, 안개 시야, 쉼터 위치, 물약 사기 등)
- 실행기는 테스트 중 생긴 스크립트 오류도 실패로 셉니다.
- 새로 만든 `class_name`이 인식되지 않으면 먼저 `--headless --path . --import`를 한 번 실행합니다.

# 시나리오 모드

손으로 만든 모험(층 지도, 방, 문, 대화, 문서, 함정, 조우)을 JSON 파일로 적어 두면 그대로 플레이할 수 있게 하는 엔진입니다. 엔진(`rules/scenario.gd`, `scripts/scenario_view.gd`)에는 특정 모험의 내용이 없고, 모험은 **시나리오 팩**(폴더 하나)으로 따로 둡니다. 같이 들어 있는 팩은 오리지널 모험 둘입니다: 「소금바람 저택」(`scenarios/saltkeeper/`, 해안 저택과 바다 동굴의 언데드)과 「꺼진 봉화」(`scenarios/crowwatch/`, 고블린이 차지한 산길 봉화대와 그 아래 무덤). 몬스터는 SRD 몬스터와, 팩이 그것을 바탕으로 정의한 몬스터를 씁니다.

## 1. 플레이

메인 화면에서 **H**를 누르면 시작합니다. 팩이 하나뿐이면 바로 시작하고, 여럿이면 시나리오 고르기 창이 뜹니다. 진행 중에 Esc로 나갔다가 다시 H를 누르면 이어서 합니다 (끝까지 깨면 다음에는 다시 고름).

특정 팩을 바로 열려면 명령줄에 `-- --scenario=<팩 폴더 또는 scenario.json>`을 붙입니다 (절대 경로도 됨).

| 키 | 동작 |
|---|---|
| WASD | 이동 (동료 클레릭이 따라옵니다) |
| F | 앞에 있는 것과 상호작용: 문 열기·강제로 열기, 조사, 대화, 계단 |
| R | 방 수색. 방마다 한 번, 파티의 가장 높은 Perception 굴림 이하 DC의 숨은 것(비밀문, 함정, 물건, 숨은 적)을 찾습니다 |
| J | 일지 (읽은 문서, 얻은 단서) |
| Esc | 창 닫기 / 메인 화면으로 |

- 위에 "?"가 떠 있는 것은 아직 살펴보지 않은 것입니다.
- 적이 있는 방에 들어서면(또는 대화 결과로) 그 자리에서 실시간 액션 전투(rules.md 10장)가 벌어지고, 끝나면 그대로 탐험을 이어 갑니다.
- 층을 옮길 때와 정해진 지점에서 체크포인트를 저장합니다. 파티가 전멸하면 마지막 체크포인트, 처음부터, 그만두기 중에서 고릅니다.

## 2. 시나리오 팩

### 2.0 폴더와 목록 파일 (`scenario.json`)
엔진은 `res://scenarios/`와 `user://scenarios/`의 하위 폴더 중 `scenario.json`이 있는 것을 팩으로 찾습니다. 새 모험은 폴더를 하나 만들어 넣기만 하면 됩니다.

```
scenarios/saltkeeper/
  scenario.json        목록 파일 (아래)
  intro.json           시작할 때 실행할 행동 목록
  levels/f1.json ...   층 하나에 파일 하나 ("id" 필드가 층 id)
  encounters.json      {조우 id: 정의}
  dialogues/mira.json  {대화 id: 정의}
  monsters.json        {몬스터 id: 정의}
```

```json
{
  "format": 1,
  "id": "saltkeeper", "title": "소금바람 저택", "description": "...", "author": "...", "version": "1.0",
  "party": ["fighter", "cleric"], "start_level": 1,
  "start": {"level": "f1", "mark": "S"},
  "intro": "intro.json",
  "levels": ["levels/f1.json", "levels/f2.json", "levels/b1.json", "levels/b2.json"],
  "encounters": ["encounters.json"],
  "dialogues": ["dialogues/mira.json", "dialogues/aldous.json"],
  "monsters": ["monsters.json"]
}
```

- `levels`: 파일 이름 배열(각 파일에 `"id"`, 없으면 파일 이름이 id) 또는 `{층 id: 파일 이름 또는 층 정의}`.
- `encounters`, `dialogues`, `monsters`: 파일 이름 배열(각 파일이 `{id: 정의}`이고 합쳐짐) 또는 바로 쓴 사전. 같은 id가 두 번 나오면 문제로 기록합니다.
- 그 밖의 값이 `.json`으로 끝나는 문자열이면 그 파일 내용으로 바꿉니다 (예: `intro`).
- `party`는 클래스 이름 배열(`fighter`, `cleric`), `start_level`은 시작 레벨, `start_gold`는 시작 금화입니다.
- 파일 경로는 팩 폴더 기준입니다. 파일이 없거나 JSON 오류가 있으면 그 부분만 빼고 시작하고, 화면 로그에 문제를 보여 줍니다. 목록 파일 자체를 못 읽으면 고르기 창에 오류를 띄웁니다.

### 2.0.1 팩 몬스터 (`monsters`)
SRD 몬스터를 바탕(`base`)으로 바꿀 값만 적습니다. 바탕으로 다른 팩 몬스터를 써도 됩니다.

```json
{"aldous": {"base": "ghast", "name": "올더스 브레넌", "tint": [0.6, 0.62, 0.78]}}
```

바꿀 수 있는 값: `name`, `hp`, `ac`, `speed`, `xp`, `cr`, `initiative_bonus`, `multiattack`, `scores`(6개), `tint`([r, g, b]), `model`("팩/이름": `kaykit/Knight`, `quaternius/orc`, Kenney 경로), `scale`, `weapon_model`(Kenney는 "팩/이름", KayKit은 `Skeleton_Blade+Skeleton_Shield_Large_A`처럼 "+"로 이은 장비 이름), `weapons`(무기 id 배열), `features`(바꿈), `add_features`(더함), `resistances`, `immunities`, `vulnerabilities`, `condition_immunities`, `ai_style`. `foe` 표시의 `monster`에 이 id를 씁니다.

### 2.1 층 (`levels.<id>`)
| 필드 | 내용 |
|---|---|
| `name`, `style` | 화면 이름, 바닥·벽 모양 (`rooms` 석조 방, `cave` 동굴) |
| `map` | 문자열 배열. 한 글자가 한 칸 |
| `marks` | 지도 글자 → 표시 정의 |
| `on_enter` | 처음 들어올 때 실행할 행동 목록 |

지도 글자: `#` 벽, `.` 바닥, `,` 험지, `~` 물, `o` 가구(낮은 장애물), `O` 기둥, `-` 0.5 단상, `^` 1.0 단상. 그 밖의 글자는 모두 `marks`에 있어야 합니다.

### 2.2 표시 (`marks`)
모든 표시에 `type`이 있고, `if` 조건으로 보이거나 숨길 수 있습니다.

| type | 주요 필드 |
|---|---|
| `start` | 층에 들어올 때 서는 곳 |
| `room` | `name`, `text`(처음 들어설 때), `encounter`. 방은 이 칸에서 문·비밀문 표시로 막힌 곳까지 채워서 정합니다 |
| `door` | `locked`, `key`(아이템), `force_dc`, `force_skill`, `open_if`, `closed_if`, `locked_text` |
| `secret` | 비밀문. `dc_find` |
| `feature` | 조사할 것. `text`, `after_text`, `once`, `solid`, `model`, `hidden_dc`, `do`(행동), `verb`, `quiet` |
| `npc` | `name`, `dialogue`, `model` |
| `stairs` | `to_level`, `to_mark`, `use_if`, `if_not_text` |
| `exit` | 밖으로 나가는 곳. `do` |
| `trap` | `dc_find`, `save`, `dc`, `damage`, `dtype` |
| `foe` | `monster`, `group`(조우 이름), `hidden` |

### 2.3 조건
문자열 하나 또는 배열(모두 참이어야 함): `"flag"`, `"!flag"`, `"item:열쇠"`, `"cleared:조우"`, `"used:표시"`.

### 2.4 행동 (`do`, 대화 선택지의 `do`, `on_enter`)
`text`, `doc`(양피지 문서), `give`/`take`(아이템), `gold`, `potion`, `flag`, `reveal`(숨은 표시 드러내기), `open`(문), `battle`, `dialogue`, `check`(기술 판정, 성공·실패 행동), `damage`, `heal`, `short_rest`, `long_rest`, `xp`(파티원마다), `level_to`, `teleport`, `checkpoint`, `toast`, `end`(엔딩).

조건이 붙은 행동은 `{"if": ..., "do": [...], "else": [...]}`로 씁니다.

### 2.5 대화 (`dialogues`)
노드마다 `speaker`, `text`, `choices`. 선택지는 `text`, `next`, `if`, `do`, `check`(`skill`, `dc`, `pass`, `fail`)를 가집니다. `next`가 없으면 대화가 끝납니다.

### 2.6 조우 (`encounters`)
`label`, `trigger`(`enter`: 방에 들어서면 / `manual`: 행동으로만), `if`(조우 자체가 있는지. 거짓이면 적도 안 보임), `trigger_if`(적은 보이지만 이 조건일 때만 들어서면 전투. 예: 대화로 적대한 뒤 도망쳤다 돌아오면 다시 싸움), `surprised`(기습 당한 쪽), `after`(이긴 뒤 행동). 적은 같은 `group`의 `foe` 표시들이고, 전투는 그 층 지도 위에서 그대로 합니다 (`battle_setup`의 잘라 낸 지도는 턴제 전투용으로 남아 있음).

### 2.7 검사
`tests/test_scenario.gd`가 모든 표시·대화 노드·층 연결이 맞는지, 모든 방에 갈 수 있는지, 처음부터 끝까지 진행되는지 확인합니다. `test_list_and_load_other_pack`은 임시 팩을 만들어 찾기·읽기·없는 파일 보고를 확인합니다. 연결·대화 노드·도달 가능·방 크기 검사는 `res://scenarios`의 모든 팩에 돌아가므로, 새 팩을 넣으면 따로 손대지 않아도 검사됩니다. 진행 테스트는 팩마다 있습니다 (`tests/test_scenario.gd`의 「소금바람 저택」, `tests/test_crowwatch.gd`의 「꺼진 봉화」).

## 3. SRD와 다른 부분
| 규칙 | 구현 |
|---|---|
| Shadow의 Strength Drain | 감소한 STR은 전투가 끝나면 돌아옵니다 (SRD는 짧은·긴 휴식) |
| Ghast의 Stench | 실시간: 1.6유닛 안에 있으면 6초(1라운드)마다 CON DC 10, 실패하면 6초 중독 = 공격 불리점, 성공하면 그 가스트에 면역 |
| Ghoul의 마비 | 실시간: 1라운드 대신 2초 동안 못 움직임. 마비된 대상을 옆에서 맞히면 치명타 |
| Specter의 Life Drain | CON DC 10 실패 시 받은 피해만큼 최대 HP 감소, 긴 휴식으로 회복. 최대 HP가 0이면 죽음 |
| 비행 (박쥐 떼, 스펙터, 실시간) | 높이 1 이하 장애물(가구) 위로 지나감. 벽·높은 장애물·닫힌 문은 못 지남 |
| 비실체 이동 (스펙터, 실시간) | 벽·문을 지나 곧장 다가옴. 물체 속에서는 절반 속도 |
| 물러나기 (실시간) | 맞붙은 뒤 적 모두에게서 6칸 넘게 떨어져 적이 있던 방 밖으로 나가면 끝. 쓰러뜨린 적은 다시 안 나옴 |
| 비행 (턴제) | 바닥 험지·높이차 무시, 높이 1.0 이하 장애물(가구) 위를 넘어감. 그 위에서 멈출 수는 없음. 높이 3.0 벽은 못 넘음 |
| 비실체 이동 (스펙터, 턴제만) | 벽과 크리처를 험지처럼 통과. 벽 속에서 멈출 수 없으므로 1d10 역장 피해는 없음 |
| 스웜 | 다른 크리처와 칸을 나눠 쓰지 않음. 절반 HP 이하면 피해 주사위 절반 |
| 전투 밖 피해 (함정 등) | 0이 되면 1 HP로 남습니다 (파티 전원이 쓰러진 경우 제외) |
| 레벨 | XP 외에 이야기 지점에서 정해진 레벨로 올림 (`level_to`, 동굴 도착 시 3레벨) |
| 수색 | 방마다 한 번만 굴림. 패시브 Perception은 2칸 안의 숨은 것을 알아챔 |

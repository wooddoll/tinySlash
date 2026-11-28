## 평판과 조합 등급 (기획 12.3, M6). 화면과 상관없는 규칙 쪽입니다.
## 세력 둘: 모험가 조합(guild), 마을 사람들(village). 평판은 세력마다 −100~100.
## 의뢰를 끝내면 의뢰인 세력 +6, 실패하면 −4. 두 세력은 서로 우호라 절반이 같은 쪽으로 번짐(한 단계).
## 조합 등급: 0 비회원 → 회관에서 가입하면 1 견습 → 평판·레벨이 넘으면 의뢰 보상 때 바로 오름. 조합 평판이 음수면 쫓겨남(0).
## 등급 3(베테랑)이 되면 회관에서 마지막 의뢰를 줌. 그것을 끝내면 엔딩.
## 다른 스크립트는 const Reputation = preload("res://rules/reputation.gd") 로 씁니다.
extends RefCounted

const FACTIONS := {"guild": "모험가 조합", "village": "마을 사람들"}
## 세력 → 우호 세력 (평판의 절반이 번짐)
const ALLIES := {"guild": ["village"], "village": ["guild"]}
const SUCCESS := 6
const FAIL := -4
## 등급: [이름, 필요한 조합 평판, 필요한 주인공 레벨]
const RANKS := [["비회원", 0, 0], ["견습", 0, 1], ["정회원", 15, 2], ["베테랑", 35, 3]]
const TOP_RANK := 3
## 마지막 의뢰: 가장 먼 던전의 이 층 우두머리
const FINAL_FLOOR := 3


## 빈 평판표
static func fresh() -> Dictionary:
	return {"guild": 0, "village": 0}


## 의뢰인 이름 → 세력 (모험가 조합 의뢰만 조합, 나머지는 마을 사람들)
static func faction_of(giver: String) -> String:
	return "guild" if giver == FACTIONS.guild else "village"


## 평판을 바꾸고 우호 세력에 절반을 번지게 함. 바뀐 양 {세력: 양}을 돌려줌
static func change(rep: Dictionary, faction: String, amount: int) -> Dictionary:
	var out := {faction: amount}
	for a in ALLIES.get(faction, []):
		out[a] = int(amount / 2.0)
	for f in out:
		rep[f] = clampi(int(rep.get(f, 0)) + int(out[f]), -100, 100)
	return out


## 의뢰 하나가 끝남(성공/실패) → 평판 변화
static func on_quest(rep: Dictionary, q: Dictionary, success: bool) -> Dictionary:
	return change(rep, faction_of(str(q.get("giver", ""))), SUCCESS if success else FAIL)


## 지금 등급에서 오를 수 있는 등급 (가입 안 했으면 0 그대로, 조합 평판이 음수면 0으로 쫓겨남, 내려가지는 않음)
static func rank_for(rank: int, guild_rep: int, level: int) -> int:
	if rank <= 0:
		return 0
	if guild_rep < 0:
		return 0
	var r := rank
	for i in range(rank + 1, RANKS.size()):
		if guild_rep >= int(RANKS[i][1]) and level >= int(RANKS[i][2]):
			r = i
		else:
			break
	return r


static func rank_name(rank: int) -> String:
	return str(RANKS[clampi(rank, 0, RANKS.size() - 1)][0])


## 다음 등급까지 필요한 것 (꼭대기면 "")
static func next_need(rank: int) -> String:
	if rank <= 0:
		return "조합 회관에서 가입"
	if rank >= TOP_RANK:
		return ""
	var n: Array = RANKS[rank + 1]
	return "%s: 조합 평판 %d · %d레벨" % [n[0], n[1], n[2]]


## 가입할 수 있나 (조합 평판이 음수면 안 받아 줌)
static func can_join(rank: int, guild_rep: int) -> bool:
	return rank <= 0 and guild_rep >= 0


## 등급 혜택 ---------------------------------------------------------

## 의뢰판에 붙는 던전 의뢰의 가장 깊은 층: 비회원 1, 견습 2, 정회원 3, 베테랑 3
static func max_floor(rank: int) -> int:
	return clampi(1 + rank, 1, FINAL_FLOOR)


## 우두머리 의뢰는 조합 의뢰라 가입해야 붙음
static func allows(kind: String, rank: int) -> bool:
	return kind != "boss" or rank >= 1


## 여관 값: 마을 평판 15 이상 7골드, 35 이상 5골드
static func inn_price(base: int, village_rep: int) -> int:
	if village_rep >= 35:
		return base - 5
	if village_rep >= 15:
		return base - 3
	return base


## 조합 회관에서 공짜로 하룻밤 (정회원부터)
static func free_rest(rank: int) -> bool:
	return rank >= 2


## 평판 한 줄 ("모험가 조합 21 · 마을 사람들 10")
static func line(rep: Dictionary) -> String:
	var parts := PackedStringArray()
	for f in FACTIONS:
		parts.append("%s %d" % [FACTIONS[f], int(rep.get(f, 0))])
	return " · ".join(parts)

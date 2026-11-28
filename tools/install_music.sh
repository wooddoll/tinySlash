#!/bin/sh
# 배경 음악 (OpenGameArt, 모두 CC0 — 출처 표기 의무 없음, CREDITS.md에 적어 둠) 설치:
#   sh tools/install_music.sh
#   village.mp3  "Medieval: Minstrel Dance" — RandomMind  https://opengameart.org/content/medieval-minstrel-dance
#   field.mp3    "Medieval: Exploration"    — RandomMind  https://opengameart.org/content/medieval-exploration
#   dungeon.ogg  "Dungeon Ambience"         — yd          https://opengameart.org/content/dungeon-ambience
# 저장소에는 넣지 않습니다 (.gitignore: assets/music/). 설치 뒤 한 번 `godot --headless --path . --import`.
set -e
cd "$(dirname "$0")/.."
DST=assets/music
mkdir -p "$DST"
get() {
	echo "받는 중: $2"
	curl -sSfL -o "$DST/$1" "https://opengameart.org/sites/default/files/$2"
}
get village.mp3 Minstrel_Dance_0.mp3
get field.mp3 Exploration_0.mp3
get dungeon.ogg dungeon002_0.ogg
echo "설치됨: $DST"

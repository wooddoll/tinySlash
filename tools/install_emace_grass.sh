#!/bin/sh
# EmacEArt Stylized Grass (바람 풀 셰이더, 고도 에셋 스토어 무료) 설치: 풀밭 전투 바닥의 풀에 씁니다.
#   sh tools/install_emace_grass.sh
# 스토어에서 받으면 스토어 약관과 EmacEArt Asset License(사용 자유, 재배포 금지)에 동의하는 것입니다.
# 재배포 금지라 저장소에는 넣지 않습니다 (.gitignore: assets/emace_grass/).
# 셰이더·재질·메시·텍스처만 assets/emace_grass 에 풀고 res:// 경로를 고칩니다. 설치 뒤 한 번 `godot --headless --path . --import`.
set -e
URL="https://store.godotengine.org/asset/emace-art/godot-stylized-vegetation-wind-shader/download/5693/"
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "받는 중: $URL"
curl -sSL -o "$TMP/g.zip" "$URL"
unzip -q "$TMP/g.zip" -d "$TMP/x"
SRC="$TMP/x/EmacEArtStylizedGrass"
DST=assets/emace_grass
rm -rf "$DST"
mkdir -p "$DST"
for d in Shaders Materials Meshes Textures; do
	cp -r "$SRC/$d" "$DST/"
done
cp "$SRC/LICENSE.txt" "$DST/"
# 원본은 프로젝트 루트 기준 경로라 옮긴 자리로 바꿈
for f in "$DST"/Materials/*.tres "$DST"/Meshes/*.mesh; do
	sed -i 's#res://\(Shaders\|Materials\|Meshes\|Textures\)/#res://assets/emace_grass/\1/#g' "$f" 2>/dev/null || true
done
echo "설치됨: $DST"

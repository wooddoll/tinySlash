#!/bin/sh
# Terrain3D (Tokisan Games, MIT) 설치: 야외 지형 생성(scripts/outdoor_terrain.gd)에 씁니다.
#   sh tools/install_terrain3d.sh
# 릴리스 zip을 받아 addons/terrain_3d 와, 데모의 지형 텍스처(ambientCG, CC0)를 assets/terrain 에 풉니다.
# 둘 다 저장소에는 넣지 않습니다 (.gitignore). 설치 뒤 한 번 `godot --headless --path . --import`.
set -e
VER=v1.1.0-stable
URL="https://github.com/TokisanGames/Terrain3D/releases/download/$VER/Terrain3D_$VER.zip"
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "받는 중: $URL"
curl -sSL -o "$TMP/t3d.zip" "$URL"
unzip -q "$TMP/t3d.zip" -d "$TMP/x"
rm -rf addons/terrain_3d
mkdir -p addons assets/terrain
cp -r "$TMP/x/addons/terrain_3d" addons/
for f in ground037_alb_ht.png ground037_nrm_rgh.png rock023_alb_ht.png rock023_nrm_rgh.png asset_licenses.txt; do
	cp "$TMP/x/demo/assets/textures/$f" assets/terrain/
done
echo "설치됨: addons/terrain_3d, assets/terrain"

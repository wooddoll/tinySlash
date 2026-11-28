@echo off
rem tinySlash 실행
rem   run.bat          게임 실행 (시작 화면: 이어하기 / 새로 시작. 저장 파일: %APPDATA%\Godot\app_userdata\2.5D Starter\save1.dat)
rem   run.bat edit     Godot 편집기로 열기
rem   run.bat test     규칙 테스트
rem   run.bat import   에셋을 새로 설치한 뒤 한 번 (가져오기)
rem Godot 위치가 다르면 GODOT 환경 변수에 Godot_v4.7.2-stable_win64.exe 경로를 넣으세요.
chcp 65001 >nul
setlocal
cd /d "%~dp0"

if "%GODOT%"=="" set "GODOT=%~dp0..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
for %%F in ("%GODOT%") do set "GODOT_CON=%%~dpnF_console%%~xF"
if not exist "%GODOT%" (
	echo Godot를 찾지 못했어요: %GODOT%
	echo GODOT 환경 변수에 Godot 4.7.2 실행 파일 경로를 넣어 주세요.
	pause
	exit /b 1
)

rem 저장소에 없는 에셋 (설치 스크립트로 받음). 없어도 실행은 되지만 모습이 달라짐
if not exist "addons\terrain_3d" echo [알림] Terrain3D 없음: 야외 지형 대신 평평한 풀밭. sh tools/install_terrain3d.sh
if not exist "assets\emace_grass" echo [알림] 바람 풀 없음. sh tools/install_emace_grass.sh
if not exist "assets\quaternius\town" echo [알림] 마을 집 조각 없음: 상자 집으로 보임. Godot -s tools/bake_town.gd (docs/assets.md)
if not exist "assets\quaternius" echo [알림] Quaternius 모델 없음: docs/assets.md 참고

if /i "%1"=="edit" (
	start "" "%GODOT%" --path . -e
	exit /b 0
)
if /i "%1"=="test" (
	"%GODOT_CON%" --headless --path . -s tests/run_tests.gd
	pause
	exit /b %errorlevel%
)
if /i "%1"=="import" (
	"%GODOT_CON%" --headless --path . --import
	exit /b %errorlevel%
)
start "" "%GODOT%" --path .

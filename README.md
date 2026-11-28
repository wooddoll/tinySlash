# tinySlash

Godot 4.7로 만드는 2.5D 쿼터뷰 실시간 액션 어드벤처 프로토타입입니다. 규칙은 SRD 5.2.1(CC-BY-4.0)을 바탕으로 했습니다.

- `scenes/title.tscn` 시작 화면 (이어하기 / 새로 시작)
- `scenes/main.tscn` 바깥 지형 탐험. G: 던전 생성기
- `scenes/battle.tscn` 단독 전투 시험장 (B 키)
- `scenes/dungeon.tscn` 파라미터 기반 던전 생성기
- `rules/` 화면과 분리된 규칙 엔진
- 문서: [기획](docs/design.md) · [규칙](docs/rules.md) · [구현](docs/implementation.md) · [TODO](docs/todo.md)

실행 (Windows): `run.bat` 더블클릭. `run.bat edit` 편집기, `run.bat test` 테스트, `run.bat import` 에셋 새로 설치한 뒤 한 번.
Godot는 이 폴더 옆 `..\Godot_v4.7.2-stable_win64.exe\` 에 있다고 보고, 다르면 `GODOT` 환경 변수로 지정합니다.
저장소에 없는 에셋은 `tools/install_*.sh`로 설치합니다 ([docs/assets.md](docs/assets.md)).

테스트:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
```

출처 표기는 [CREDITS.md](CREDITS.md)를 보세요.

# tinySlash

Godot 4.7로 만드는 2.5D 아이소메트릭 턴제 전술 RPG 프로토타입입니다. 규칙은 SRD 5.2.1(CC-BY-4.0)을 바탕으로 했습니다.

- `scenes/main.tscn` 탐험 (8방향 스프라이트). B: 전투, G: 던전 생성기
- `scenes/battle.tscn` 격자 턴제 전투
- `scenes/dungeon.tscn` 파라미터 기반 던전 생성기
- `rules/` 화면과 분리된 규칙 엔진
- 문서: [규칙](docs/rules.md) · [구현](docs/implementation.md) · [TODO](docs/todo.md)

테스트:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
```

출처 표기는 [CREDITS.md](CREDITS.md)를 보세요.

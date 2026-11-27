"""Unity .unitypackage를 Unity 없이 풉니다.

  python -I tools/unitypackage_extract.py <패키지.unitypackage> <출력 폴더> [--list] [--only 확장자,...]

.unitypackage는 tar.gz이고, 안에 GUID 폴더마다 asset(본 파일)과 pathname(원래 경로)이 들어 있습니다.
pathname대로 출력 폴더 아래에 asset을 풀어 놓습니다. --list는 풀지 않고 경로와 크기만 보여 줍니다.
--only fbx,png 처럼 주면 그 확장자만 풉니다. 출력 폴더 바깥으로 나가는 경로는 건너뜁니다.
재질·프리팹이 GUID로 파일을 가리키므로 출력 폴더에 _guids.tsv(GUID → 경로)도 씁니다.
"""
import os
import sys
import tarfile


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    src, out = args[0], args[1]
    listing = "--list" in args
    only = None
    if "--only" in args:
        only = {"." + e.strip().lower().lstrip(".") for e in args[args.index("--only") + 1].split(",")}
    paths: dict[str, str] = {}
    sizes: dict[str, int] = {}
    # 1차: 경로 이름만 모음 (pathname이 asset보다 뒤에 올 수 있어서 두 번 읽음)
    with tarfile.open(src, "r:gz") as tar:
        for m in tar:
            parts = m.name.replace("\\", "/").strip("./").split("/")
            if len(parts) != 2 or not m.isfile():
                continue
            guid, kind = parts
            if kind == "pathname":
                paths[guid] = tar.extractfile(m).read().decode("utf-8").splitlines()[0].strip()
            elif kind == "asset":
                sizes[guid] = m.size
    if listing:
        for guid, p in sorted(paths.items(), key=lambda kv: kv[1]):
            if guid in sizes:
                print(f"{sizes[guid]:>12} {p}")
        return
    root = os.path.realpath(out)
    os.makedirs(root, exist_ok=True)
    # 재질(.mat)·프리팹은 텍스처·모델을 GUID로 가리키므로, GUID → 경로 표를 같이 남김
    with open(os.path.join(root, "_guids.tsv"), "w", encoding="utf-8", newline="\n") as g:
        for guid, p in sorted(paths.items()):
            g.write(f"{guid}\t{p}\n")
    n = 0
    with tarfile.open(src, "r:gz") as tar:
        for m in tar:
            parts = m.name.replace("\\", "/").strip("./").split("/")
            if len(parts) != 2 or parts[1] != "asset" or not m.isfile():
                continue
            rel = paths.get(parts[0])
            if not rel:
                continue
            if only and os.path.splitext(rel)[1].lower() not in only:
                continue
            dst = os.path.realpath(os.path.join(root, rel))
            if not dst.startswith(root + os.sep):
                print("건너뜀(바깥 경로):", rel)
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with tar.extractfile(m) as f, open(dst, "wb") as g:
                while chunk := f.read(1 << 20):
                    g.write(chunk)
            n += 1
    print("풀었음:", n)


if __name__ == "__main__":
    main()

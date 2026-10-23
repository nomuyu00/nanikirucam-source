#!/usr/bin/env python3
"""ios/Runner.xcodeproj/project.pbxproj の整合を機械的に確かめる（macOS の plutil / xcodebuild が無い環境用）。

    py -3.12 app/tool/check_pbxproj.py [project.pbxproj のパス]

確かめること:
  - OpenStep 形式として括弧・引用符が対応している（構文エラーなし）
  - objects のキー（24 桁の 16 進 ID）に重複がない
  - どこかが参照している ID（fileRef / files / children / buildPhases / buildConfigurations /
    buildConfigurationList / productRef / targets など）が、すべて objects に存在する
  - ビルドフェーズ（Sources / Resources / Frameworks）の PBXBuildFile が指す PBXFileReference が、
    いずれかの PBXGroup の children に入っている
  - PBXBuildFile が複数のフェーズから二重に使われていない
終了コードは問題があれば 1。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "ios" / "Runner.xcodeproj" / "project.pbxproj"
ID_RE = re.compile(r"^[0-9A-F]{24}$")


class Parser:
    """Xcode の project.pbxproj（OpenStep 風の plist）の最小パーサ。"""

    def __init__(self, text: str) -> None:
        self.text = text
        self.pos = 0

    def error(self, message: str) -> "ParseError":
        line = self.text.count("\n", 0, self.pos) + 1
        return ParseError(f"{message}（{line} 行目付近）")

    def skip(self) -> None:
        t = self.text
        while self.pos < len(t):
            if t[self.pos].isspace():
                self.pos += 1
            elif t.startswith("//", self.pos):
                self.pos = t.find("\n", self.pos)
                if self.pos < 0:
                    self.pos = len(t)
            elif t.startswith("/*", self.pos):
                end = t.find("*/", self.pos + 2)
                if end < 0:
                    raise self.error("コメントが閉じていません")
                self.pos = end + 2
            else:
                break

    def value(self):
        self.skip()
        t = self.text
        if self.pos >= len(t):
            raise self.error("値が途中で終わっています")
        c = t[self.pos]
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.quoted()
        return self.bare()

    def dict(self) -> dict:
        self.pos += 1
        result: dict = {}
        while True:
            self.skip()
            if self.pos >= len(self.text):
                raise self.error("辞書が閉じていません")
            if self.text[self.pos] == "}":
                self.pos += 1
                return result
            key = self.value()
            self.skip()
            if self.text[self.pos : self.pos + 1] != "=":
                raise self.error(f"'=' がありません（キー {key!r}）")
            self.pos += 1
            val = self.value()
            self.skip()
            if self.text[self.pos : self.pos + 1] != ";":
                raise self.error(f"';' がありません（キー {key!r}）")
            self.pos += 1
            if key in result:
                raise self.error(f"キーが重複しています: {key!r}")
            result[key] = val

    def array(self) -> list:
        self.pos += 1
        result: list = []
        while True:
            self.skip()
            if self.pos >= len(self.text):
                raise self.error("配列が閉じていません")
            if self.text[self.pos] == ")":
                self.pos += 1
                return result
            result.append(self.value())
            self.skip()
            if self.text[self.pos : self.pos + 1] == ",":
                self.pos += 1
            elif self.text[self.pos : self.pos + 1] != ")":
                raise self.error("配列の区切り ',' がありません")

    def quoted(self) -> str:
        self.pos += 1
        out = []
        t = self.text
        while self.pos < len(t):
            c = t[self.pos]
            if c == "\\":
                out.append(t[self.pos : self.pos + 2])
                self.pos += 2
            elif c == '"':
                self.pos += 1
                return "".join(out)
            else:
                out.append(c)
                self.pos += 1
        raise self.error("引用符が閉じていません")

    def bare(self) -> str:
        m = re.compile(r"[A-Za-z0-9_$./+\-*]+").match(self.text, self.pos)
        if not m:
            raise self.error(f"想定外の文字 {self.text[self.pos]!r}")
        self.pos = m.end()
        return m.group(0)


class ParseError(Exception):
    pass


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # Windows のコンソールでも文字化けしないように
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    text = path.read_text(encoding="utf-8")
    problems: list[str] = []

    first = text.lstrip().split("\n", 1)[0]
    if not first.startswith("// !$*UTF8*$!"):
        problems.append("先頭行が '// !$*UTF8*$!' ではありません")

    parser = Parser(text)
    try:
        root = parser.value()
        parser.skip()
        if parser.pos != len(text):
            raise parser.error("ルートの後ろに余計な文字があります")
    except ParseError as e:
        print("構文エラー:", e)
        return 1

    objects = root["objects"]
    for obj_id in objects:
        if not ID_RE.match(obj_id):
            problems.append(f"ID の形式が不正: {obj_id}")

    ids = set(objects)

    def ref(owner: str, what: str, target) -> None:
        if isinstance(target, str) and ID_RE.match(target) and target not in ids:
            problems.append(f"{owner} の {what} が存在しない ID を指している: {target}")

    for obj_id, obj in objects.items():
        if not isinstance(obj, dict):
            continue
        isa = obj.get("isa")
        owner = f"{obj_id}({isa})"
        for key in ("fileRef", "productRef", "buildConfigurationList", "productReference", "target", "targetProxy",
                    "baseConfigurationReference", "remoteGlobalIDString", "containerPortal"):
            if key in obj:
                ref(owner, key, obj[key])
        for key in ("files", "children", "buildPhases", "buildConfigurations", "targets", "dependencies",
                    "packageProductDependencies", "packageReferences", "buildRules"):
            for item in obj.get(key, []) or []:
                ref(owner, key, item)
    ref("root", "rootObject", root.get("rootObject"))
    for key in ("mainGroup", "productRefGroup"):
        ref("PBXProject", key, objects.get(root["rootObject"], {}).get(key))

    grouped: set[str] = set()
    for obj in objects.values():
        if isinstance(obj, dict) and obj.get("isa") in ("PBXGroup", "PBXVariantGroup"):
            grouped.update(obj.get("children", []))

    used_build_files: dict[str, str] = {}
    for obj_id, obj in objects.items():
        if not isinstance(obj, dict) or not obj.get("isa", "").endswith("BuildPhase"):
            continue
        for bf in obj.get("files", []):
            if bf in used_build_files:
                problems.append(f"PBXBuildFile {bf} が複数のフェーズで使われている（{used_build_files[bf]} と {obj_id}）")
            used_build_files[bf] = obj_id
            build_file = objects.get(bf, {})
            file_ref = build_file.get("fileRef")
            if file_ref and file_ref not in grouped and "productRef" not in build_file:
                problems.append(f"PBXBuildFile {bf} の fileRef {file_ref} がどの PBXGroup にも入っていない")

    for obj_id, obj in objects.items():
        if isinstance(obj, dict) and obj.get("isa") == "PBXBuildFile" and obj_id not in used_build_files:
            problems.append(f"PBXBuildFile {obj_id} がどのビルドフェーズにも入っていない")

    runner_sources = [
        objects.get(bf, {}).get("fileRef") for obj in objects.values()
        if isinstance(obj, dict) and obj.get("isa") == "PBXSourcesBuildPhase" for bf in obj.get("files", [])
    ]
    names = sorted(objects[r].get("path", "?") for r in runner_sources if r in objects)
    print(f"{path.name}: オブジェクト {len(objects)} 個、ソースにコンパイルされるファイル: {', '.join(names)}")

    if problems:
        print("問題あり:")
        for p in problems:
            print(" -", p)
        return 1
    print("OK: 構文・ID の重複・参照の解決・グループへの所属に問題なし")
    return 0


if __name__ == "__main__":
    sys.exit(main())

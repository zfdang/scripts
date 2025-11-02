#!/usr/bin/env python3
"""
列出目录里所有的文件，按中文拼音排序，并给每个文件名增加 3 位数字前缀。

用法:
    python3 pinyin_sort_prefix.py /path/to/dir [--dry-run]

选项:
    --dry-run, -n    仅打印要重命名的映射，不实际执行重命名
    --include-dirs    同时处理目录（默认只处理普通文件）
    --yes, -y         跳过确认直接重命名

注意:
    - 脚本在排序时会忽略已有的三位数字前缀（形如 001_foo.txt），以便重新编号。
    - 当目标文件名已存在时，会自动在基本名后添加一个序号以避免覆盖。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple

try:
    from pypinyin import lazy_pinyin
except Exception as e:
    print("Missing dependency 'pypinyin'. Install with: pip install -r requirements.txt")
    raise

PREFIX_RE = re.compile(r"^(\d{3}_) ")
PREFIX_RE = re.compile(r"^(\d{3}_)")


def strip_prefix(name: str) -> str:
    """去掉已有的三位数字前缀（例如 '001_foo.txt' -> 'foo.txt'）。"""
    return PREFIX_RE.sub("", name)


def sort_key(name: str) -> str:
    """为排序生成 key：把中文转换成拼音，其他字符小写保留。

    使用 pypinyin.lazy_pinyin 对整串转换，它会把中文转换为拼音，把英文/数字/符号按字符返回，最后 join 成字符串作为排序键。
    """
    # 使用 stripped name so existing numeric prefixes don't affect sorting
    s = strip_prefix(name)
    try:
        parts = lazy_pinyin(s)
        key = "".join(parts).lower()
    except Exception:
        key = s.lower()
    return key


def list_entries(directory: str, include_dirs: bool = False) -> List[str]:
    entries = os.listdir(directory)
    if include_dirs:
        # include files and directories
        return sorted(entries)
    else:
        return [e for e in entries if os.path.isfile(os.path.join(directory, e))]


def build_rename_plan(directory: str, entries: List[str]) -> List[Tuple[str, str]]:
    # sort by pinyin key
    sorted_entries = sorted(entries, key=lambda n: (sort_key(n), n))
    plan: List[Tuple[str, str]] = []

    for idx, name in enumerate(sorted_entries, start=1):
        prefix = f"{idx:03d}-"
        target_name = prefix + name
        src = os.path.join(directory, name)
        dst = os.path.join(directory, target_name)

        if os.path.exists(dst):
            # if dst is same as src (already prefixed and matches), skip
            if os.path.samefile(src, dst):
                continue
            # otherwise find a free name by appending _N before extension
            base, ext = os.path.splitext(name)
            j = 1
            while True:
                candidate = f"{prefix}{base}-{j}{ext}"
                candidate_path = os.path.join(directory, candidate)
                if not os.path.exists(candidate_path):
                    dst = candidate_path
                    break
                j += 1

        plan.append((src, dst))

    return plan


def confirm(prompt: str) -> bool:
    try:
        resp = input(prompt).strip().lower()
    except EOFError:
        return False
    return resp in ("y", "yes")


def main(argv=None):
    argv = argv or sys.argv[1:]
    parser = argparse.ArgumentParser(description="按中文拼音给目录下的文件按序号前缀排序重命名")
    parser.add_argument("directory", help="目标目录")
    parser.add_argument("--dry-run", "-n", action="store_true", help="仅打印计划，不实际重命名")
    parser.add_argument("--include-dirs", action="store_true", help="同时处理目录（默认仅处理文件）")
    parser.add_argument("--yes", "-y", action="store_true", help="跳过确认，直接执行")

    args = parser.parse_args(argv)

    directory = args.directory
    if not os.path.isdir(directory):
        print(f"错误：{directory} 不是一个目录")
        return 2

    entries = list_entries(directory, include_dirs=args.include_dirs)
    if not entries:
        print("目录中没有要处理的文件/条目")
        return 0

    plan = build_rename_plan(directory, entries)
    if not plan:
        print("没有需要重命名的文件（可能已经带有正确的前缀）")
        return 0

    print("将按以下顺序重命名（源 -> 目标）:")
    for src, dst in plan:
        print(f"{os.path.basename(src)} -> {os.path.basename(dst)}")

    if args.dry_run:
        print("\n干运行模式，未执行重命名。")
        return 0

    if not args.yes:
        ok = confirm("继续并执行重命名吗？ [y/N]: ")
        if not ok:
            print("已取消")
            return 0

    # perform renames
    for src, dst in plan:
        try:
            os.rename(src, dst)
        except Exception as e:
            print(f"重命名失败: {src} -> {dst}: {e}")

    print("重命名完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

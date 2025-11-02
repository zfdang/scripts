# pinyin_sort_prefix

这个小脚本用于：列出指定目录下的文件，按中文拼音对文件名排序，并为每个文件增加 3 位的数字前缀（例如 001_文件名）。

安装依赖：

```bash
python3 -m pip install -r requirements.txt
```

基本用法：

```bash
python3 pinyin_sort_prefix.py /path/to/dir
```

示例：先预览再执行：

```bash
python3 pinyin_sort_prefix.py /path/to/dir --dry-run
python3 pinyin_sort_prefix.py /path/to/dir
```

常见选项：

- `--dry-run, -n`：仅打印重命名计划，不实际修改文件。
- `--include-dirs`：同时对目录进行处理（默认仅处理普通文件）。
- `--yes, -y`：跳过确认，直接执行。

注意事项：

- 脚本在排序时会自动忽略已有的三位数字前缀（格式为 `NNN_`），以便重新编号。
- 如果目标名称已存在，脚本会在基本名后添加 `_1`, `_2` 等避免覆盖。
# scripts
collection of useful scripts

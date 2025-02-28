#!/usr/bin/env bash
# gitRemove.sh
# 从 Git 索引中移除常见系统/编辑器生成的临时文件（仅从索引移除，保留工作区文件）
#
# 特性（与当前脚本语法保持一致）：
# - 默认为 dry-run 模式，仅列出仓库中已被跟踪且匹配的文件。
# - 支持在仓库内指定目标路径（相对或绝对），限制扫描范围。
# - 支持选项：
#     --apply    实际对匹配到的已跟踪文件执行 `git rm --cached`（从索引移除，但保留工作树文件）。
#
# 使用示例：
#   ./gitRemove.sh                  # dry-run（默认，列出将被移除的已跟踪文件）
#   ./gitRemove.sh --apply          # 在整个仓库中实际移除匹配的文件
#   ./gitRemove.sh video            # dry-run：仅扫描并列出 `video` 目录下的已跟踪匹配文件
#   ./gitRemove.sh --apply video    # 在 `video` 目录下实际移除匹配的已跟踪文件

set -euo pipefail

DRY_RUN=1

if [[ ${1:-} == "--help" ]] || [[ ${1:-} == "-h" ]]; then
	cat <<EOF
Usage: $0 [--apply] [target_path]

--apply    Actually run git rm --cached on matched tracked files (default: dry-run)
target_path  Optional path (file or directory) inside the repository to limit the operation to.
EOF
	exit 0
fi

# parse flags: accept --apply in any order; remaining single arg is optional target path
POSITIONAL=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--apply)
			DRY_RUN=0; shift ;;
		-h|--help)
			cat <<EOF
		Usage: $0 [--apply] [target_path]

		--apply    Actually run git rm --cached on matched tracked files (default: dry-run)
		target_path  Optional path (file or directory) inside the repository to limit the operation to.
		EOF
			exit 0 ;;
		--)
			shift; break ;;
		-*|--*)
			echo "Unknown option $1"; exit 2 ;;
		*)
			POSITIONAL+=("$1"); shift ;;
	esac
done

# If positional argument present, use it as target path relative to repo root (or absolute)
TARGET_PATH="."
if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
	TARGET_PATH="${POSITIONAL[0]}"
fi

# --commit option removed: script will not perform commits automatically.

# 确保在 git 仓库内，并切换到仓库根
if ! GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
	echo "Error: not a git repository. 请在仓库中运行此脚本。" >&2
	exit 3
fi
cd "$GIT_ROOT"

echo "Repository root: $GIT_ROOT"

# 要匹配并移除的文件名（basename 匹配）和 glob
patterns=(
	".DS_Store"
	"DocumentRevisions-V100"
	"fseventsd"
	"Spotlight-V100"
	"Trashes"
	"TemporaryItems"
	".DS_Store?"
	"._*"
	"Thumbs.db"
	"ehthumbs.db"
	"Desktop.ini"
	"core.*"
)

declare -a matches

# 准备要列出的已跟踪文件（可限制到目标路径）
ls_args=( -z )
if [[ "$TARGET_PATH" == "." || -z "$TARGET_PATH" ]]; then
	ls_cmd=(git ls-files -z)
else
	# 如果提供了绝对路径，转换为相对仓库根
	if [[ "$TARGET_PATH" == /* ]]; then
		case "$TARGET_PATH" in
			"$GIT_ROOT") TARGET_PATH='.' ;;
			"$GIT_ROOT"/*) TARGET_PATH="${TARGET_PATH#$GIT_ROOT/}" ;;
			*) echo "Error: target path is outside repository"; exit 4 ;;
		esac
	fi
	# 确保目标路径存在
	if [[ ! -e "$GIT_ROOT/$TARGET_PATH" ]]; then
		echo "Error: target path '$TARGET_PATH' does not exist in repository"; exit 4
	fi
	ls_cmd=(git ls-files -z -- "$TARGET_PATH")
fi

# 遍历已跟踪文件并匹配
while IFS= read -r -d '' file; do
	base=$(basename -- "$file")
	for pat in "${patterns[@]}"; do
		# 使用 bash 模式匹配
		if [[ "$base" == $pat ]]; then
			matches+=("$file")
			break
		fi
		# 处理 patterns 中的通配符（如 ._* 或 core.*）
		case "$pat" in
			"._*")
				if [[ "$base" == ._* ]]; then matches+=("$file"); break; fi
				;;
			"core.*")
				if [[ "$base" == core.* ]]; then matches+=("$file"); break; fi
				;;
			".DS_Store?")
				# 匹配 .DS_Store 后带一个字符的情况
				if [[ "$base" == .DS_Store? ]]; then matches+=("$file"); break; fi
				;;
		esac
	done
done < <("${ls_cmd[@]}")

# 去重（避免使用关联数组以兼容 macOS 自带 bash）
if [[ ${#matches[@]} -eq 0 ]]; then
	echo "No tracked OS/editor artifact files found in git index."
	exit 0
fi
uniq_matches=()
contains() {
	local target="$1"; shift
	for item in "$@"; do
		if [[ "$item" == "$target" ]]; then
			return 0
		fi
	done
	return 1
}
for p in "${matches[@]}"; do
	if ! contains "$p" "${uniq_matches[@]:-}"; then
		uniq_matches+=("$p")
	fi
done

echo "Found ${#uniq_matches[@]} tracked file(s):"
for p in "${uniq_matches[@]}"; do
	printf "  %s\n" "$p"
done

if [[ $DRY_RUN -eq 1 ]]; then
	echo "\nDry-run: no changes made. Re-run with --apply to remove these from git index."
	exit 0
fi

echo "Removing files from git index..."
# 安全地传递文件名（NUL 分隔）
printf '%s\0' "${uniq_matches[@]}" | xargs -0 --no-run-if-empty git rm -r --cached --

echo "Finished git rm --cached."


echo "Files removed from index. 请检查 'git status'，并在确认后手动提交更改："
echo "  git add -A && git commit -m 'chore: remove tracked OS/editor artifacts'"
echo "（脚本已禁用自动提交以避免意外变更）"

exit 0
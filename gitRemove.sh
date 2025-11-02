#!/usr/bin/env bash

# gitRemove.sh - 移除Git仓库中匹配特定模式的已跟踪文件
# 用法:
#   ./gitRemove.sh              # 列出将被移除的文件
#   ./gitRemove.sh --apply      # 实际移除匹配的文件
#   ./gitRemove.sh video        # 扫描 video 目录，列出将被移除的文件
#   ./gitRemove.sh --apply video # 扫描 video 目录，实际移除匹配的文件

set -euo pipefail

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

apply_changes=false
target_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            apply_changes=true
            shift
            ;;
        -*)
            echo "错误: 未知选项 $1" >&2
            echo "用法: $0 [--apply] [目录]" >&2
            exit 1
            ;;
        *)
            target_dir="$1"
            shift
            ;;
    esac
done

work_dir="$PWD"
original_target="$target_dir"

if [[ -n "$target_dir" ]]; then
    if [[ -d "$target_dir" ]]; then
        abs_target=$(cd "$target_dir" && pwd)
        
        if (cd "$abs_target" && git rev-parse --git-dir > /dev/null 2>&1); then
            work_dir="$abs_target"
            scan_path="."
        else
            if ! git rev-parse --git-dir > /dev/null 2>&1; then
                echo "错误: 当前目录不是Git仓库，且目标目录 '$target_dir' 也不是Git仓库" >&2
                exit 1
            fi
            
            repo_root=$(git rev-parse --show-toplevel)
            
            if [[ ! "$abs_target" =~ ^"$repo_root" ]]; then
                echo "错误: 目录 '$target_dir' 不在当前 Git 仓库内" >&2
                exit 1
            fi
            
            if [[ "$abs_target" == "$repo_root" ]]; then
                scan_path="."
            else
                scan_path="${abs_target#$repo_root/}"
            fi
        fi
    else
        echo "错误: 目录 '$target_dir' 不存在" >&2
        exit 1
    fi
else
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "错误: 当前目录不是Git仓库" >&2
        exit 1
    fi
    scan_path="."
fi

cd "$work_dir"
repo_root=$(git rev-parse --show-toplevel)

echo "================================"
if $apply_changes; then
    echo "模式: 实际移除文件"
else
    echo "模式: 仅列出文件"
fi
echo "Git 仓库: $repo_root"
echo "扫描路径: $scan_path"
echo "================================"
echo ""

declare -a found_files=()

for pattern in "${patterns[@]}"; do
    while IFS= read -r file; do
        basename=$(basename "$file")
        
        matched=false
        case "$basename" in
            $pattern)
                matched=true
                ;;
        esac
        
        if $matched; then
            found_files+=("$file")
        fi
    done < <(git ls-files -- "$scan_path")
done

if [[ ${#found_files[@]} -gt 0 ]]; then
    IFS=$'\n' sorted_files=($(printf '%s\n' "${found_files[@]}" | sort -u))
    unset IFS
else
    sorted_files=()
fi

if [[ ${#sorted_files[@]} -eq 0 ]]; then
    echo "✓ 未找到匹配的已跟踪文件"
    exit 0
fi

echo "找到 ${#sorted_files[@]} 个匹配的已跟踪文件:"
echo ""

for file in "${sorted_files[@]}"; do
    echo "  - $file"
done

echo ""

if ! $apply_changes; then
    echo "================================"
    echo "要实际移除这些文件，请运行:"
    if [[ -n "$target_dir" ]]; then
        echo "  $0 --apply $target_dir"
    else
        echo "  $0 --apply"
    fi
    echo "================================"
    exit 0
fi

echo "================================"
echo "开始移除文件..."
echo "================================"
echo ""

removed_count=0
failed_count=0

for file in "${sorted_files[@]}"; do
    if git rm -f "$file" > /dev/null 2>&1; then
        echo "✓ 已移除: $file"
        ((removed_count++))
    else
        echo "✗ 失败: $file" >&2
        ((failed_count++))
    fi
done

echo ""
echo "================================"
echo "完成!"
echo "成功移除: $removed_count 个文件"
if [[ $failed_count -gt 0 ]]; then
    echo "失败: $failed_count 个文件"
fi
echo "================================"
echo ""
echo "注意: 这些文件已从Git索引中移除"
echo "请运行以下命令提交更改:"
echo "  git commit -m 'Remove system/temp files'"


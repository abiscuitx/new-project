#!/usr/bin/env bash

# gitRemove.sh - 移除Git仓库中匹配特定模式的已跟踪文件
# 用法:
#   ./gitRemove.sh "Directory path"                                # 扫描指定目录并列出匹配文件
#   ./gitRemove.sh --purge-history "Directory path"                # 扫描指定目录与Git 历史中匹配文件（需要安装 git-filter-repo，会重写历史）

#   ./gitRemove.sh --apply "Directory path"                        # 扫描并删除指定目录中匹配文件（仅从索引移除，保留工作区文件）
#   ./gitRemove.sh --apply --purge-history "Directory path"        # 扫描并删除指定目录与Git 历史中匹配文件（需要安装 git-filter-repo，会重写历史）

# 确保使用 bash 4.0+ 或使用兼容模式
if [[ -n "$BASH_VERSION" ]]; then
    bash_major_version="${BASH_VERSION%%.*}"
    if [[ "$bash_major_version" -lt 4 ]]; then
        USE_COMPAT_MODE=true
    else
        USE_COMPAT_MODE=false
    fi
fi

patterns=(
    # macOS 系统文件
    "^\\.DS_Store$"
    "/\\.DS_Store$"
    "^\\.DS_Store\\?$"
    "/\\.DS_Store\\?$"
    "^\\._"
    "/\\._"
    "^DocumentRevisions-V100/"
    "^fseventsd/"
    "^Spotlight-V100/"
    "^Trashes/"
    "^TemporaryItems/"
    
    # Windows 系统文件
    "^Thumbs\\.db$"
    "/Thumbs\\.db$"
    "^ehthumbs\\.db$"
    "/ehthumbs\\.db$"
    "^Desktop\\.ini$"
    "/Desktop\\.ini$"
    
    # 环境变量文件
    "^\\.env$"
    "/\\.env$"
    "^\\.env\\."
    "/\\.env\\."
    
    # 证书和密钥文件
    "\\.pem$"
    "\\.key$"
    "\\.crt$"
    "\\.cert$"
    "\\.private$"
    
    # Token 和凭证文件
    "\\.token$"
    "^secret-"
    "/secret-"
    "\\.secret$"
    "\\.credentials$"
    "\\.auth$"
    "\\.accesskey$"
    
    # SSH 密钥
    "^id_rsa$"
    "/id_rsa$"
    "^id_rsa\\.pub$"
    "/id_rsa\\.pub$"
    "^id_dsa$"
    "/id_dsa$"
    "^id_dsa\\.pub$"
    "/id_dsa\\.pub$"
    "^authorized_keys$"
    "/authorized_keys$"
    "^known_hosts$"
    "/known_hosts$"
    "^ssh_config$"
    "/ssh_config$"
    
    # 凭证配置文件
    "^credentials\\.json$"
    "/credentials\\.json$"
    "^credentials\\.ya?ml$"
    "/credentials\\.ya?ml$"
    "^client_secret\\.json$"
    "/client_secret\\.json$"
    
    # Apache 配置文件
    "^\\.htpasswd$"
    "/\\.htpasswd$"
    "^\\.htaccess$"
    "/\\.htaccess$"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 解析命令行参数
APPLY=false
PURGE_HISTORY=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --apply)
            APPLY=true
            shift
            ;;
        --purge-history)
            PURGE_HISTORY=true
            shift
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# 检查目录参数
if [[ -z "$TARGET_DIR" ]]; then
    echo -e "${RED}错误: 请提供目标目录路径${NC}"
    echo "用法示例:"
    echo "  $0 \"Directory path\"                      # 扫描并列出匹配文件"
    echo "  $0 --apply \"Directory path\"              # 从Git索引中移除匹配文件"
    echo "  $0 --purge-history \"Directory path\"      # 从Git历史中彻底删除匹配文件"
    echo "  $0 --apply --purge-history \"Directory path\" # 同时执行上述两个操作"
    exit 1
fi

# 检查目录是否存在
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}错误: 目录不存在: $TARGET_DIR${NC}"
    exit 1
fi

# 进入目标目录
cd "$TARGET_DIR" || exit 1

# 检查是否是Git仓库
if [[ ! -d .git ]]; then
    echo -e "${RED}错误: $TARGET_DIR 不是一个Git仓库${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Git 仓库清理工具${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "目标目录: ${GREEN}$TARGET_DIR${NC}"
echo -e "扫描模式: ${APPLY} 是否应用: $(if $APPLY; then echo -e "${GREEN}是${NC}"; else echo -e "${YELLOW}否(仅列出)${NC}"; fi)"
echo -e "清理历史: $(if $PURGE_HISTORY; then echo -e "${GREEN}是${NC}"; else echo -e "${YELLOW}否${NC}"; fi)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 扫描匹配的文件
echo -e "${YELLOW}正在扫描匹配的文件...${NC}"
matched_files=()

# 检查是否需要扫描历史
if [[ "$PURGE_HISTORY" == true ]]; then
    echo -e "${YELLOW}正在扫描 Git 历史中的文件...${NC}"
    # 获取历史中所有文件（包括已删除的）
    temp_all_files=$(mktemp)
    git log --all --pretty=format: --name-only --diff-filter=A | grep -v '^$' | sort -u > "$temp_all_files"
    
    for pattern in "${patterns[@]}"; do
        # 转换通配符模式为 grep 正则表达式（只转换 * 为 .*，保留原有的转义）
        regex_pattern=$(echo "$pattern" | sed 's/\*/.*/g')
        
        # 在历史文件中查找匹配
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                matched_files+=("$file")
            fi
        done < <(cat "$temp_all_files" | grep -E "$regex_pattern" 2>/dev/null || true)
    done
    
    rm -f "$temp_all_files"
else
    # 只扫描当前已跟踪的文件
    for pattern in "${patterns[@]}"; do
        # 转换通配符模式为 grep 正则表达式（只转换 * 为 .*，保留原有的转义）
        regex_pattern=$(echo "$pattern" | sed 's/\*/.*/g')
        
        # 使用 git ls-files 查找已跟踪的文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                matched_files+=("$file")
            fi
        done < <(git ls-files | grep -E "$regex_pattern" 2>/dev/null || true)
    done
fi

# 去重 - 兼容 macOS 的方式
if [[ ${#matched_files[@]} -gt 0 ]]; then
    temp_matched=$(mktemp)
    printf '%s\n' "${matched_files[@]}" | sort -u > "$temp_matched"
    matched_files=()
    while IFS= read -r line; do
        matched_files+=("$line")
    done < "$temp_matched"
    rm -f "$temp_matched"
fi

# 显示结果
if [[ ${#matched_files[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ 未找到匹配的文件${NC}"
    exit 0
fi

echo -e "${YELLOW}找到 ${#matched_files[@]} 个匹配的文件:${NC}"
echo ""
for file in "${matched_files[@]}"; do
    echo -e "  ${RED}✗${NC} $file"
done
echo ""

# 如果不是应用模式，退出
if [[ "$APPLY" != true ]]; then
    echo -e "${YELLOW}提示: 使用 --apply 参数来从Git索引中移除这些文件${NC}"
    exit 0
fi

# 确认操作
echo -e "${YELLOW}警告: 即将从Git中移除这些文件!${NC}"
if [[ "$PURGE_HISTORY" == true ]]; then
    echo -e "${RED}警告: 将从Git历史中彻底删除这些文件,这会重写历史!${NC}"
fi
read -p "是否继续? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

# 从Git索引中移除文件
echo -e "${YELLOW}正在从Git索引中移除文件...${NC}"
removed_count=0
for file in "${matched_files[@]}"; do
    if git rm --cached "$file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} 已移除: $file"
        ((removed_count++))
    else
        echo -e "  ${RED}✗${NC} 移除失败: $file"
    fi
done

echo ""
echo -e "${GREEN}成功从索引中移除 $removed_count 个文件${NC}"

# 如果需要清理历史
if [[ "$PURGE_HISTORY" == true ]]; then
    echo ""
    echo -e "${YELLOW}正在检查 git-filter-repo...${NC}"
    
    if ! command -v git-filter-repo &> /dev/null; then
        echo -e "${RED}错误: 未安装 git-filter-repo${NC}"
        echo -e "${YELLOW}请先安装 git-filter-repo:${NC}"
        echo "  brew install git-filter-repo"
        echo "或:"
        echo "  pip install git-filter-repo"
        exit 1
    fi
    
    echo -e "${GREEN}✓ git-filter-repo 已安装${NC}"
    echo ""
    echo -e "${RED}警告: 即将重写Git历史!${NC}"
    echo -e "${RED}这是一个危险操作,建议先备份仓库!${NC}"
    read -p "确认要继续吗? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}历史清理已取消${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}正在从Git历史中删除文件...${NC}"
    
    # 创建临时文件列表
    temp_file=$(mktemp)
    printf '%s\n' "${matched_files[@]}" > "$temp_file"
    
    # 使用 git-filter-repo 删除文件
    if git filter-repo --invert-paths --paths-from-file "$temp_file" --force; then
        echo -e "${GREEN}✓ 成功从历史中删除文件${NC}"
        rm "$temp_file"
    else
        echo -e "${RED}✗ 历史清理失败${NC}"
        rm "$temp_file"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}注意: Git历史已被重写!${NC}"
    echo -e "${YELLOW}如果已推送到远程仓库,需要强制推送:${NC}"
    echo -e "  ${BLUE}git push --force --all${NC}"
    echo -e "  ${BLUE}git push --force --tags${NC}"
fi

# 建议添加到 .gitignore
echo ""
echo -e "${YELLOW}建议: 将这些模式添加到 .gitignore 文件中以防止再次提交${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}完成!${NC}"
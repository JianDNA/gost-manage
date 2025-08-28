#!/bin/bash

# ========== 工具函数库 ========== #
# 通用工具函数，包括颜色输出、端口检测、YAML处理等

# ========== 配色定义 ========== #
COLOR_RESET=$(tput sgr0)
COLOR_RED=$(tput setaf 1)
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_BLUE=$(tput setaf 4)
COLOR_MAGENTA=$(tput setaf 5)
COLOR_CYAN=$(tput setaf 6)
COLOR_WHITE=$(tput setaf 7)

# ========== 输出函数 ========== #
print_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_RED}❌ $1${COLOR_RESET}"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠️  $1${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_BLUE}ℹ️  $1${COLOR_RESET}"
}

print_title() {
    echo -e "${COLOR_CYAN}========== $1 ==========${COLOR_RESET}"
}

print_separator() {
    echo -e "${COLOR_MAGENTA}----------------------------------------${COLOR_RESET}"
}

# ========== 缓存管理 ========== #
# 服务名称缓存
CACHED_SERVICE_NAMES=""
CACHED_SERVICE_NAMES_TIMESTAMP=0
CACHE_EXPIRY_SECONDS=5

# 获取带缓存的服务名称
get_cached_service_names() {
    local current_time=$(date +%s)
    local config_mtime=0
    
    # 获取配置文件修改时间
    if [[ -f "/etc/gost/config.yml" ]]; then
        config_mtime=$(stat -c %Y "/etc/gost/config.yml" 2>/dev/null || echo "0")
    fi
    
    # 检查缓存是否有效
    if [[ -n "$CACHED_SERVICE_NAMES" ]] && 
       [[ $((current_time - CACHED_SERVICE_NAMES_TIMESTAMP)) -lt $CACHE_EXPIRY_SECONDS ]] &&
       [[ $config_mtime -le $CACHED_SERVICE_NAMES_TIMESTAMP ]]; then
        echo "$CACHED_SERVICE_NAMES"
        return 0
    fi
    
    # 重新获取服务名称并缓存
    if command -v get_service_names >/dev/null 2>&1; then
        CACHED_SERVICE_NAMES=$(get_service_names)
        CACHED_SERVICE_NAMES_TIMESTAMP=$current_time
        echo "$CACHED_SERVICE_NAMES"
    fi
}

# 清理服务名称缓存
clear_service_names_cache() {
    CACHED_SERVICE_NAMES=""
    CACHED_SERVICE_NAMES_TIMESTAMP=0
}

# ========== 临时文件管理 ========== #
# 临时文件数组
declare -a TEMP_FILES_TO_CLEANUP=()

# 添加临时文件到清理列表
register_temp_file() {
    local temp_file="$1"
    TEMP_FILES_TO_CLEANUP+=("$temp_file")
}

# 清理所有临时文件
cleanup_temp_files_on_exit() {
    local file
    for file in "${TEMP_FILES_TO_CLEANUP[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" 2>/dev/null || true
        fi
    done
    TEMP_FILES_TO_CLEANUP=()
}

# 创建临时文件并自动注册清理
create_temp_file() {
    local temp_file
    temp_file=$(mktemp) || return 1
    register_temp_file "$temp_file"
    echo "$temp_file"
}

# 创建临时目录并自动注册清理
create_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d) || return 1
    register_temp_file "$temp_dir"
    echo "$temp_dir"
}

# ========== 端口检测函数 ========== #
PORT_RANGE_START=20250
PORT_RANGE_END=20300

# 检查端口是否被占用
is_port_in_use() {
    local port=$1
    ss -tuln | grep -q ":$port "
}

# 检查端口是否被gost使用
is_port_used_by_gost() {
    local port=$1
    local config_file="/etc/gost/config.yml"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    grep -q ":$port" "$config_file"
}

# 获取可用端口
get_available_port() {
    for ((port=$PORT_RANGE_START; port<=$PORT_RANGE_END; port++)); do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    # 如果预设范围内没有可用端口，随机选择一个
    local random_port=$((RANDOM % 10000 + 30000))
    while is_port_in_use "$random_port"; do
        random_port=$((RANDOM % 10000 + 30000))
    done
    echo "$random_port"
}

# 验证端口号格式
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# ========== YAML处理函数 ========== #
# 验证YAML语法
validate_yaml_syntax() {
    local file=$1
    
    # 使用Python验证YAML语法（如果可用）
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        yaml.safe_load(f)
    print('YAML语法正确')
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'YAML语法错误: {e}')
    sys.exit(1)
except Exception as e:
    print(f'文件读取错误: {e}')
    sys.exit(1)
" 2>/dev/null
        return $?
    fi
    
    # 基本的YAML格式检查
    if ! grep -q "^services:" "$file"; then
        print_error "配置文件缺少 'services:' 根节点"
        return 1
    fi
    
    return 0
}

# 备份配置文件
backup_config() {
    local config_file=$1
    local backup_file="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$backup_file"
        print_info "配置文件已备份到: $backup_file"
        return 0
    fi
    return 1
}

# ========== 输入验证函数 ========== #
# 验证IP地址格式
validate_ip() {
    local ip=$1
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ $ip =~ $regex ]]; then
        # 检查每个数字是否在0-255范围内
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 验证IPv6地址格式
validate_ipv6() {
    local ipv6=$1

    # 移除可能的方括号
    ipv6=${ipv6#[}
    ipv6=${ipv6%]}

    # 移除可能的接口标识符（如 %lo0）
    ipv6=${ipv6%\%*}

    # 空地址检查
    if [[ -z "$ipv6" ]]; then
        return 1
    fi

    # 检查是否包含冒号（IPv6的基本特征）
    if [[ "$ipv6" != *":"* ]]; then
        return 1
    fi

    # 检查是否有过多的连续冒号（除了::）
    if [[ "$ipv6" =~ :::+ ]]; then
        return 1
    fi

    # 检查双冒号是否只出现一次
    local double_colon_count=$(echo "$ipv6" | grep -o "::" | wc -l)
    if [[ $double_colon_count -gt 1 ]]; then
        return 1
    fi

    # 支持IPv4映射的IPv6地址（如 ::ffff:192.0.2.1）
    if [[ "$ipv6" =~ ::ffff:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local ipv4_part=${ipv6#*::ffff:}
        if validate_ip "$ipv4_part"; then
            return 0
        fi
    fi

    # 基本IPv6格式验证：只包含十六进制字符和冒号
    if [[ "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
        # 检查每个段是否不超过4个字符
        IFS=':' read -ra segments <<< "$ipv6"
        for segment in "${segments[@]}"; do
            if [[ ${#segment} -gt 4 ]]; then
                return 1
            fi
        done

        # 基本格式检查通过
        return 0
    fi

    return 1
}

# 验证域名格式
validate_domain() {
    local domain=$1
    local regex="^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$"

    [[ $domain =~ $regex ]]
}

# 验证目标地址格式 (IP:PORT, DOMAIN:PORT, 或 [IPv6]:PORT)
validate_target_address() {
    local address=$1

    # 处理IPv6地址格式 [IPv6]:PORT
    if [[ "$address" =~ ^\[([^\]]+)\]:([0-9]+)$ ]]; then
        local ipv6="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]}"

        # 验证端口
        if ! validate_port "$port"; then
            return 1
        fi

        # 验证IPv6地址
        if validate_ipv6 "$ipv6"; then
            return 0
        fi

        return 1
    fi

    # 处理IPv4地址或域名格式 HOST:PORT
    if [[ ! "$address" =~ ^.+:[0-9]+$ ]]; then
        return 1
    fi

    local host=$(echo "$address" | cut -d':' -f1)
    local port=$(echo "$address" | cut -d':' -f2)

    # 验证端口
    if ! validate_port "$port"; then
        return 1
    fi

    # 验证主机（IPv4、IPv6或域名）
    if validate_ip "$host" || validate_ipv6 "$host" || validate_domain "$host"; then
        return 0
    fi

    return 1
}

# ========== 系统信息函数 ========== #
# 获取系统信息
get_system_info() {
    echo "系统信息:"
    echo "  操作系统: $(uname -s)"
    echo "  内核版本: $(uname -r)"
    echo "  架构: $(uname -m)"
    if command -v lsb_release >/dev/null 2>&1; then
        echo "  发行版: $(lsb_release -d | cut -f2)"
    fi
}

# 检查必要的命令是否存在
check_dependencies() {
    local missing_deps=()
    
    local required_commands=("ss" "grep" "awk" "sed" "curl")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "缺少必要的命令: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# ========== 用户交互函数 ========== #
# 询问用户确认
ask_confirmation() {
    local message=$1
    local default=${2:-"n"}
    
    # 临时关闭set -e以避免交互式输入时退出
    local old_set_state=$-
    set +e
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n -e "${COLOR_YELLOW}$message [Y/n]: ${COLOR_RESET}"
        else
            echo -n -e "${COLOR_YELLOW}$message [y/N]: ${COLOR_RESET}"
        fi
        
        # 使用更安全的读取方式
        local response
        IFS= read -r response

        # 过滤掉ANSI转义序列和控制字符
        response=$(echo "$response" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\000-\037\177')
        
        # 如果用户直接回车，使用默认值
        if [[ -z "$response" ]]; then
            response=$default
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                # 恢复之前的set状态
                [[ $old_set_state =~ e ]] && set -e || true
                return 0
                ;;
            [Nn]|[Nn][Oo])
                # 恢复之前的set状态
                [[ $old_set_state =~ e ]] && set -e || true
                return 1
                ;;
            *)
                print_warning "请输入 y/yes 或 n/no"
                ;;
        esac
    done
}

# 增强的输入读取函数（支持方向键和历史记录）
enhanced_read() {
    local prompt=$1
    local var_name=$2
    local default_value=${3:-""}

    # 暂时禁用rlwrap，因为它在脚本中的集成有问题
    # 直接使用标准输入处理
    safe_read_fallback "$prompt" "$var_name" "$default_value"
}

# 安全读取用户输入（避免特殊字符问题）
safe_read() {
    local prompt=$1
    local var_name=$2
    local default_value=${3:-""}

    # 临时关闭set -e以避免交互式输入时退出
    local old_set_state=$-
    set +e
    
    # 尝试使用增强输入，如果失败则使用标准方法
    if ! enhanced_read "$prompt" "$var_name" "$default_value" 2>/dev/null; then
        safe_read_fallback "$prompt" "$var_name" "$default_value"
    fi
    
    # 恢复之前的set状态
    [[ $old_set_state =~ e ]] && set -e || true
}

# 标准输入读取（回退方案）
safe_read_fallback() {
    local prompt=$1
    local var_name=$2
    local default_value=${3:-""}

    while true; do
        if [[ -n "$default_value" ]]; then
            echo -n -e "${COLOR_YELLOW}$prompt [默认: $default_value]: ${COLOR_RESET}"
        else
            echo -n -e "${COLOR_YELLOW}$prompt: ${COLOR_RESET}"
        fi

        # 使用更安全的读取方式，过滤控制字符
        local input
        IFS= read -r input

        # 过滤掉ANSI转义序列和控制字符
        input=$(echo "$input" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\000-\037\177')

        # 如果用户直接回车且有默认值，使用默认值
        if [[ -z "$input" && -n "$default_value" ]]; then
            input=$default_value
        fi

        # 将输入赋值给指定变量
        printf -v "$var_name" '%s' "$input"
        break
    done
}

# ========== 日志函数 ========== #
# 记录操作日志
log_operation() {
    local operation=$1
    local details=$2
    local log_file="/var/log/gost-manage.log"
    
    # 确保日志目录存在
    mkdir -p "$(dirname "$log_file")"
    
    # 记录日志
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $operation: $details" >> "$log_file"
    
    # 设置适当的文件权限（仅root可写，root和root组可读）
    chmod 640 "$log_file" 2>/dev/null || true
    chown root:root "$log_file" 2>/dev/null || true
}

# 显示最近的操作日志
show_recent_logs() {
    local log_file="/var/log/gost-manage.log"
    local lines=${1:-10}
    
    if [[ -f "$log_file" ]]; then
        print_title "最近 $lines 条操作记录"
        tail -n "$lines" "$log_file"
    else
        print_info "暂无操作记录"
    fi
}

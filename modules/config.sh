#!/bin/bash

# ========== 配置管理模块 ========== #
# 负责YAML配置文件的读取、写入、验证和修复

# 配置文件路径
CONFIG_FILE="/etc/gost/config.yml"

# ========== 配置文件基础操作 ========== #

# 初始化配置文件
init_config_file() {
    local config_dir=$(dirname "$CONFIG_FILE")
    
    # 创建配置目录
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
        print_success "创建配置目录: $config_dir"
    fi
    
    # 创建初始配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
services:
EOF
        print_success "创建初始配置文件: $CONFIG_FILE"
        log_operation "INIT_CONFIG" "创建初始配置文件"
    fi
}

# 检查配置文件是否存在
check_config_file() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    return 0
}

# ========== 服务信息获取 ========== #

# 获取所有服务名称
get_service_names() {
    if ! check_config_file; then
        return 1
    fi

    # 检查配置文件是否可读
    if [[ ! -r "$CONFIG_FILE" ]]; then
        return 1
    fi

    # 只匹配顶级服务的name，不匹配forwarder.nodes下的name
    grep "^- name:" "$CONFIG_FILE" 2>/dev/null | sed 's/.*name: *\(.*\)/\1/' | sed 's/["\047]//g'
}

# 获取服务数量
get_service_count() {
    local names=$(get_service_names)
    if [[ -z "$names" ]]; then
        echo "0"
    else
        echo "$names" | wc -l
    fi
}

# 检查服务是否存在
service_exists() {
    local service_name=$1

    # 检查配置文件是否可读
    if [[ ! -r "$CONFIG_FILE" ]]; then
        print_warning "无法读取配置文件，请使用 sudo 运行脚本"
        return 1
    fi

    local names=$(get_service_names 2>/dev/null)

    if [[ -z "$names" ]]; then
        return 1
    fi

    echo "$names" | grep -q "^$service_name$"
}

# 获取服务详细信息
get_service_info() {
    local service_name=$1
    
    if ! service_exists "$service_name"; then
        return 1
    fi
    
    # 使用awk提取服务信息
    awk -v service="$service_name" '
    /^- name:/ {
        if ($0 ~ service) {
            in_service = 1
            print $0
            next
        } else {
            in_service = 0
        }
    }
    in_service && /^  / {
        print $0
    }
    in_service && /^- name:/ && $0 !~ service {
        exit
    }
    ' "$CONFIG_FILE"
}

# 获取服务监听端口
get_service_port() {
    local service_name=$1

    get_service_info "$service_name" | grep "addr:" | head -1 | sed 's/.*:\([0-9]*\).*/\1/'
}

# 获取服务目标地址
get_service_target() {
    local service_name=$1

    get_service_info "$service_name" | grep -A3 "nodes:" | grep "addr:" | sed 's/.*addr: *\(.*\)/\1/' | tr -d '"'"'"
}

# 获取服务协议类型
get_service_protocol() {
    local service_name=$1
    
    get_service_info "$service_name" | grep "type:" | head -1 | sed 's/.*type: *\(.*\)/\1/' | tr -d '"'"'"
}

# ========== 服务配置操作 ========== #

# 添加新服务
add_service_to_config() {
    local service_name=$1
    local listen_addr=$2
    local listen_port=$3
    local protocol=$4
    local target_addr=$5
    
    # 检查服务是否已存在
    if service_exists "$service_name"; then
        print_error "服务 '$service_name' 已存在"
        return 1
    fi
    
    # 备份配置文件
    backup_config "$CONFIG_FILE"
    
    # 构建完整的监听地址
    local full_addr="${listen_addr}:${listen_port}"
    if [[ -z "$listen_addr" ]]; then
        full_addr=":${listen_port}"
    fi
    
    # 处理IPv6地址的引号问题
    local quoted_target_addr="$target_addr"
    if [[ "$target_addr" =~ ^\[.*\]: ]]; then
        quoted_target_addr="\"$target_addr\""
    fi

    # 添加服务配置
    cat >> "$CONFIG_FILE" <<EOF
- name: $service_name
  addr: $full_addr
  handler:
    type: $protocol
  listener:
    type: $protocol
  forwarder:
    nodes:
    - name: $service_name
      addr: $quoted_target_addr
EOF
    
    print_success "服务 '$service_name' 添加成功"
    log_operation "ADD_SERVICE" "添加服务: $service_name ($full_addr -> $target_addr)"
    return 0
}

# 删除服务
delete_service_from_config() {
    local service_name=$1
    
    if ! service_exists "$service_name"; then
        print_error "服务 '$service_name' 不存在"
        return 1
    fi
    
    # 备份配置文件
    backup_config "$CONFIG_FILE"
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 使用更简单的方法：逐行处理，跟踪服务状态
    local in_target_service=false
    local temp_file2=$(mktemp)

    while IFS= read -r line; do
        # 检查是否是目标服务的开始
        if [[ "$line" =~ ^-\ name:.*"$service_name"$ ]] || [[ "$line" == "- name: $service_name" ]]; then
            in_target_service=true
            continue
        fi

        # 检查是否是其他服务的开始
        if [[ "$line" =~ ^-\ name: ]] && [[ ! "$line" =~ ^-\ name:.*"$service_name"$ ]] && [[ "$line" != "- name: $service_name" ]]; then
            in_target_service=false
            echo "$line" >> "$temp_file2"
            continue
        fi

        # 如果不在目标服务内部，保留这行
        if [[ "$in_target_service" == false ]]; then
            echo "$line" >> "$temp_file2"
        fi

    done < "$CONFIG_FILE"

    mv "$temp_file2" "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$CONFIG_FILE"
    
    print_success "服务 '$service_name' 删除成功"
    log_operation "DELETE_SERVICE" "删除服务: $service_name"
    return 0
}

# 更新服务配置
update_service_in_config() {
    local service_name=$1
    local new_service_name=$2
    local new_listen_addr=$3
    local new_listen_port=$4
    local new_protocol=$5
    local new_target_addr=$6

    if ! service_exists "$service_name"; then
        print_error "服务 '$service_name' 不存在"
        return 1
    fi

    # 如果新服务名称与原名称不同，检查新名称是否已存在
    if [[ "$service_name" != "$new_service_name" ]] && service_exists "$new_service_name"; then
        print_error "服务名称 '$new_service_name' 已存在"
        return 1
    fi

    # 先删除旧配置，再添加新配置
    delete_service_from_config "$service_name"
    add_service_to_config "$new_service_name" "$new_listen_addr" "$new_listen_port" "$new_protocol" "$new_target_addr"

    if [[ "$service_name" != "$new_service_name" ]]; then
        log_operation "UPDATE_SERVICE" "更新服务: $service_name → $new_service_name"
    else
        log_operation "UPDATE_SERVICE" "更新服务: $service_name"
    fi
    return 0
}

# ========== 配置文件验证和修复 ========== #

# 验证配置文件
validate_config_file() {
    if ! check_config_file; then
        return 1
    fi
    
    print_info "正在验证配置文件..."
    
    # 检查基本格式
    if ! grep -q "^services:" "$CONFIG_FILE"; then
        print_error "配置文件缺少 'services:' 根节点"
        return 1
    fi
    
    # 验证YAML语法
    if ! validate_yaml_syntax "$CONFIG_FILE"; then
        print_error "YAML语法验证失败"
        return 1
    fi
    
    # 检查服务配置完整性
    local services=$(get_service_names)
    local error_count=0
    
    if [[ -n "$services" ]]; then
        while IFS= read -r service; do
            print_info "检查服务: $service"
            
            # 检查必要字段
            local service_info=$(get_service_info "$service")
            
            if ! echo "$service_info" | grep -q "addr:"; then
                print_error "服务 '$service' 缺少 addr 字段"
                ((error_count++))
            fi
            
            if ! echo "$service_info" | grep -q "handler:"; then
                print_error "服务 '$service' 缺少 handler 字段"
                ((error_count++))
            fi
            
            if ! echo "$service_info" | grep -q "listener:"; then
                print_error "服务 '$service' 缺少 listener 字段"
                ((error_count++))
            fi
            
            if ! echo "$service_info" | grep -q "forwarder:"; then
                print_error "服务 '$service' 缺少 forwarder 字段"
                ((error_count++))
            fi
            
            # 检查端口占用
            local port=$(get_service_port "$service")
            if [[ -n "$port" ]] && is_port_in_use "$port" && ! is_port_used_by_gost "$port"; then
                print_warning "端口 $port 被其他程序占用"
            fi
            
        done <<< "$services"
    fi
    
    if [[ $error_count -eq 0 ]]; then
        print_success "配置文件验证通过"
        return 0
    else
        print_error "发现 $error_count 个配置错误"
        return 1
    fi
}

# 标准化配置文件格式（处理Windows/Linux兼容性问题）
normalize_config_format() {
    if ! check_config_file; then
        return 1
    fi

    print_info "正在标准化配置文件格式..."

    # 备份原文件
    backup_config "$CONFIG_FILE"

    local temp_file=$(mktemp)
    local fixed=false

    # 第一步：处理文件编码和行结束符问题
    # 转换Windows行结束符(\r\n)为Linux格式(\n)
    if grep -q $'\r' "$CONFIG_FILE"; then
        tr -d '\r' < "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        print_success "修复Windows行结束符"
        fixed=true
    fi

    # 移除BOM标记（如果存在）
    if [[ $(head -c 3 "$CONFIG_FILE" | od -t x1 -N 3 | head -1 | awk '{print $2$3$4}') == "efbbbf" ]]; then
        tail -c +4 "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        print_success "移除BOM标记"
        fixed=true
    fi

    # 第二步：使用Python进行YAML标准化（如果可用）
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml" 2>/dev/null; then
            if normalize_yaml_with_python; then
                print_success "使用Python标准化YAML格式"
                fixed=true
            fi
        fi
    fi

    # 第三步：基础格式修复
    fix_common_format_issues

    # 第三步：修复常见格式问题
    fix_common_format_issues

    if $fixed; then
        print_success "配置文件格式标准化完成"
        log_operation "NORMALIZE_CONFIG" "标准化配置文件格式"
    else
        print_info "配置文件格式已是标准格式"
    fi

    return 0
}

# 使用Python标准化YAML格式
normalize_yaml_with_python() {
    local temp_file=$(mktemp)

    python3 << EOF
import yaml
import sys
import re

try:
    # 读取配置文件
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        content = f.read()

    # 预处理：修复常见的格式问题
    # 修复 type:tcp 这样的问题（缺少空格）
    content = re.sub(r'type:(\w+)', r'type: \1', content)

    # 解析YAML
    data = yaml.safe_load(content)

    # 确保有services根节点
    if not isinstance(data, dict) or 'services' not in data:
        data = {'services': []}

    # 标准化服务结构
    if 'services' in data and isinstance(data['services'], list):
        for service in data['services']:
            if isinstance(service, dict):
                # 确保handler和listener是字典结构
                if 'handler' in service and isinstance(service['handler'], str):
                    if service['handler'].startswith('type:'):
                        service['handler'] = {'type': service['handler'][5:].strip()}
                if 'listener' in service and isinstance(service['listener'], str):
                    if service['listener'].startswith('type:'):
                        service['listener'] = {'type': service['listener'][5:].strip()}

    # 标准化输出
    with open('$temp_file', 'w', encoding='utf-8') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)

    sys.exit(0)
except Exception as e:
    print(f"Python YAML处理失败: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    if [[ $? -eq 0 ]] && [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$CONFIG_FILE"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# 修复常见格式问题
fix_common_format_issues() {
    local temp_file=$(mktemp)
    local fixed=false

    # 修复 services: [] 格式
    if grep -q "services: \[\]" "$CONFIG_FILE"; then
        sed 's/services: \[\]/services:/' "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        print_success "修复 services: [] 格式"
        fixed=true
    fi

    # 确保有services根节点
    if ! grep -q "^services:" "$CONFIG_FILE"; then
        print_warning "配置文件缺少 services: 根节点，正在修复..."

        temp_file=$(mktemp)
        echo "services:" > "$temp_file"

        # 如果原文件有服务配置，添加到新文件中
        if grep -q "^ *- name:" "$CONFIG_FILE"; then
            cat "$CONFIG_FILE" >> "$temp_file"
        fi

        mv "$temp_file" "$CONFIG_FILE"
        print_success "已添加 services: 根节点"
        fixed=true
    fi

    # 移除多余的空行
    sed '/^[[:space:]]*$/N;/^\n$/d' "$CONFIG_FILE" > "$temp_file"
    if ! cmp -s "$CONFIG_FILE" "$temp_file"; then
        mv "$temp_file" "$CONFIG_FILE"
        print_success "清理多余空行"
        fixed=true
    else
        rm -f "$temp_file"
    fi

    return 0
}

# 兼容性函数：保持旧的函数名
fix_config_format() {
    normalize_config_format
}

# ========== 配置文件显示 ========== #

# 显示配置文件内容
show_config() {
    if ! check_config_file; then
        return 1
    fi
    
    print_title "当前配置文件内容"
    cat -n "$CONFIG_FILE"
    echo
}

# 显示服务列表
list_services() {
    local services=$(get_service_names)
    local count=$(get_service_count)
    
    print_title "当前转发规则 (共 $count 个)"
    
    if [[ $count -eq 0 ]]; then
        print_info "暂无转发规则"
        return 0
    fi
    
    local index=1
    while IFS= read -r service; do
        local port=$(get_service_port "$service")
        local target=$(get_service_target "$service")
        local protocol=$(get_service_protocol "$service")
        
        echo -e "${COLOR_CYAN}[$index]${COLOR_RESET} ${COLOR_WHITE}$service${COLOR_RESET}"
        echo -e "    监听端口: ${COLOR_GREEN}$port${COLOR_RESET}"
        echo -e "    协议类型: ${COLOR_YELLOW}$protocol${COLOR_RESET}"
        echo -e "    目标地址: ${COLOR_BLUE}$target${COLOR_RESET}"
        echo
        
        ((index++))
    done <<< "$services"
}

# 获取服务选择
select_service() {
    local services=$(get_service_names)
    local count=$(get_service_count)

    if [[ $count -eq 0 ]]; then
        print_error "没有可用的服务"
        return 1
    fi

    list_services

    while true; do
        echo -n -e "${COLOR_YELLOW}请选择服务序号 (1-$count): ${COLOR_RESET}"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            echo "$services" | sed -n "${choice}p"
            return 0
        else
            print_warning "无效输入，请输入 1-$count 之间的数字"
        fi
    done
}

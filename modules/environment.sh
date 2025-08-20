#!/bin/bash

# ========== 环境准备模块 ========== #
# 负责Gost安装、系统服务配置、依赖检查等

# ========== Gost安装管理 ========== #

# 检查Gost是否已安装
check_gost_installed() {
    if command -v gost >/dev/null 2>&1; then
        local version=$(gost -V 2>/dev/null | head -1)
        print_success "Gost 已安装: $version"
        return 0
    else
        print_warning "Gost 未安装"
        return 1
    fi
}

# 安装Gost
install_gost() {
    print_info "正在安装 Gost..."
    
    # 检查网络连接
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null; then
        print_error "网络连接失败，无法下载 Gost"
        return 1
    fi
    
    # 使用官方安装脚本
    if bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install; then
        print_success "Gost 安装成功"
        log_operation "INSTALL_GOST" "成功安装 Gost"
        return 0
    else
        print_error "Gost 安装失败"
        log_operation "INSTALL_GOST" "Gost 安装失败"
        return 1
    fi
}

# 更新Gost
update_gost() {
    print_info "正在更新 Gost..."
    
    if install_gost; then
        print_success "Gost 更新成功"
        log_operation "UPDATE_GOST" "成功更新 Gost"
        return 0
    else
        print_error "Gost 更新失败"
        return 1
    fi
}

# 卸载Gost
uninstall_gost() {
    if ask_confirmation "确定要卸载 Gost 吗？这将删除 /usr/local/bin/gost"; then
        # 停止服务
        systemctl stop gost 2>/dev/null
        systemctl disable gost 2>/dev/null
        
        # 删除二进制文件
        rm -f /usr/local/bin/gost
        
        # 删除服务文件
        rm -f /etc/systemd/system/gost.service
        systemctl daemon-reload
        
        print_success "Gost 卸载完成"
        log_operation "UNINSTALL_GOST" "卸载 Gost"
        return 0
    else
        print_info "取消卸载操作"
        return 1
    fi
}

# ========== 系统服务管理 ========== #

# 创建systemd服务文件
create_systemd_service() {
    local service_file="/etc/systemd/system/gost.service"
    
    print_info "正在创建 systemd 服务..."
    
    cat > "$service_file" <<EOF
[Unit]
Description=Gost Forward Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/gost
ExecStart=/usr/local/bin/gost -C /etc/gost/config.yml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable gost
    
    print_success "systemd 服务创建成功"
    log_operation "CREATE_SERVICE" "创建 systemd 服务"
    return 0
}

# 检查服务状态
check_service_status() {
    print_title "Gost 服务状态"
    
    if systemctl is-active --quiet gost; then
        print_success "服务正在运行"
        echo
        systemctl status gost --no-pager -l
    else
        print_warning "服务未运行"
        echo
        systemctl status gost --no-pager -l
    fi
}

# 启动服务
start_service() {
    print_info "正在启动 Gost 服务..."
    
    if systemctl start gost; then
        print_success "服务启动成功"
        log_operation "START_SERVICE" "启动 Gost 服务"
        return 0
    else
        print_error "服务启动失败"
        print_info "查看详细错误信息:"
        journalctl -u gost --no-pager -l -n 10
        return 1
    fi
}

# 停止服务
stop_service() {
    print_info "正在停止 Gost 服务..."
    
    if systemctl stop gost; then
        print_success "服务停止成功"
        log_operation "STOP_SERVICE" "停止 Gost 服务"
        return 0
    else
        print_error "服务停止失败"
        return 1
    fi
}

# 重启服务
restart_service() {
    print_info "正在重启 Gost 服务..."
    
    if systemctl restart gost; then
        print_success "服务重启成功"
        log_operation "RESTART_SERVICE" "重启 Gost 服务"
        return 0
    else
        print_error "服务重启失败"
        print_info "查看详细错误信息:"
        journalctl -u gost --no-pager -l -n 10
        return 1
    fi
}

# 重新加载配置
reload_service() {
    print_info "正在重新加载 Gost 配置..."
    
    if systemctl reload gost 2>/dev/null; then
        print_success "配置重新加载成功"
        log_operation "RELOAD_SERVICE" "重新加载 Gost 配置"
        return 0
    else
        # 如果reload不支持，则使用restart
        print_info "reload 不支持，使用 restart 代替..."
        restart_service
    fi
}

# ========== 依赖检查和安装 ========== #

# 检查Python3和PyYAML
check_python_yaml() {
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml" 2>/dev/null; then
            print_success "Python3 和 PyYAML 已安装"
            return 0
        else
            print_warning "Python3 已安装，但缺少 PyYAML 模块"
            return 1
        fi
    else
        print_warning "Python3 未安装"
        return 1
    fi
}

# 安装Python依赖
install_python_dependencies() {
    print_info "正在安装 Python 依赖..."
    
    # 检测系统包管理器并安装Python3
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y python3 python3-pip python3-yaml
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum install -y python3 python3-pip python3-pyyaml
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        dnf install -y python3 python3-pip python3-pyyaml
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -S --noconfirm python python-pip python-yaml
    else
        print_warning "未识别的包管理器，尝试使用 pip 安装 PyYAML..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install PyYAML
        else
            print_error "无法安装 Python 依赖"
            return 1
        fi
    fi
    
    if check_python_yaml; then
        print_success "Python 依赖安装成功"
        log_operation "INSTALL_PYTHON_DEPS" "安装 Python 依赖"
        return 0
    else
        print_error "Python 依赖安装失败"
        return 1
    fi
}

# ========== 环境初始化 ========== #

# 设置终端环境
setup_terminal_environment() {
    # 设置终端属性以更好地处理输入
    if command -v stty >/dev/null 2>&1; then
        # 启用原始模式的某些特性，但保持基本功能
        stty -echo 2>/dev/null || true
        stty echo 2>/dev/null || true

        # 设置合理的终端属性
        stty sane 2>/dev/null || true
    fi

    # 检查rlwrap状态（暂时不推荐安装，因为集成有问题）
    if command -v rlwrap >/dev/null 2>&1; then
        print_info "检测到 rlwrap 已安装，但当前版本暂时禁用了集成"
        print_info "如果遇到输入问题，脚本会自动使用标准输入处理"
    else
        print_info "提示：如果看到方向键字符（如 ^[[C），这是正常的"
        print_info "脚本会自动过滤这些字符，不影响功能使用"
    fi
}

# 安装rlwrap以改善输入体验
install_rlwrap() {
    print_info "正在安装 rlwrap..."

    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update && apt-get install -y rlwrap; then
            print_success "rlwrap 安装成功"
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y rlwrap; then
            print_success "rlwrap 安装成功"
            return 0
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y rlwrap; then
            print_success "rlwrap 安装成功"
            return 0
        fi
    elif command -v pacman >/dev/null 2>&1; then
        if pacman -S --noconfirm rlwrap; then
            print_success "rlwrap 安装成功"
            return 0
        fi
    else
        print_warning "未检测到支持的包管理器"
        print_info "请手动安装 rlwrap 包"
        return 1
    fi

    print_error "rlwrap 安装失败"
    return 1
}

# 完整的环境准备
prepare_environment() {
    print_title "环境准备"

    # 设置终端环境
    setup_terminal_environment

    # 检查系统依赖
    print_info "检查系统依赖..."
    if ! check_dependencies; then
        print_error "系统依赖检查失败"
        return 1
    fi
    
    # 检查并安装Gost
    if ! check_gost_installed; then
        if ask_confirmation "是否安装 Gost？" "y"; then
            if ! install_gost; then
                return 1
            fi
        else
            print_error "Gost 未安装，无法继续"
            return 1
        fi
    fi
    
    # 初始化配置文件
    init_config_file
    
    # 检查和修复配置文件
    if [[ -f "/etc/gost/config.yml" ]]; then
        if grep -q "^services: null$" "/etc/gost/config.yml" || ! grep -q "^services:" "/etc/gost/config.yml"; then
            print_warning "检测到配置文件问题，正在自动修复..."
            if fix_config_file; then
                print_success "配置文件已修复"
            fi
        fi
    fi
    
    # 创建systemd服务
    if [[ ! -f "/etc/systemd/system/gost.service" ]]; then
        create_systemd_service
    else
        print_info "systemd 服务已存在"
    fi
    
    # 检查Python依赖（可选）
    if ! check_python_yaml; then
        if ask_confirmation "是否安装 Python3 和 PyYAML 以支持高级 YAML 验证？" "y"; then
            install_python_dependencies
        else
            print_info "跳过 Python 依赖安装，将使用基础 YAML 验证"
        fi
    fi
    
    # 修复可能存在的配置文件问题
    fix_config_format
    
    print_success "环境准备完成"
    log_operation "PREPARE_ENV" "完成环境准备"
    return 0
}

# 显示环境信息
show_environment_info() {
    print_title "环境信息"
    
    # 系统信息
    get_system_info
    echo
    
    # Gost信息
    if check_gost_installed; then
        echo "Gost 路径: $(which gost)"
    fi
    echo
    
    # 服务状态
    check_service_status
    echo
    
    # 配置文件信息
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "配置文件: $CONFIG_FILE"
        echo "配置文件大小: $(du -h "$CONFIG_FILE" | cut -f1)"
        echo "服务数量: $(get_service_count)"
    else
        echo "配置文件: 不存在"
    fi
    echo
    
    # Python依赖
    if check_python_yaml; then
        echo "Python YAML 支持: 可用"
    else
        echo "Python YAML 支持: 不可用"
    fi
}

# ========== 系统维护 ========== #

# 清理临时文件
cleanup_temp_files() {
    print_info "清理临时文件..."
    
    # 清理备份文件（保留最近5个）
    local backup_dir=$(dirname "$CONFIG_FILE")
    local backup_count=$(ls -1 "$backup_dir"/*.bak.* 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt 5 ]]; then
        ls -1t "$backup_dir"/*.bak.* | tail -n +6 | xargs rm -f
        print_success "清理了 $((backup_count - 5)) 个旧备份文件"
    fi
    
    # 清理日志文件（保留最近1000行）
    local log_file="/var/log/gost-manage.log"
    if [[ -f "$log_file" ]]; then
        local line_count=$(wc -l < "$log_file")
        if [[ $line_count -gt 1000 ]]; then
            tail -n 1000 "$log_file" > "$log_file.tmp"
            mv "$log_file.tmp" "$log_file"
            print_success "清理了日志文件，保留最近1000行"
        fi
    fi
    
    log_operation "CLEANUP" "清理临时文件"
}

# 检查系统健康状态
check_system_health() {
    print_title "系统健康检查"
    
    local issues=0
    
    # 检查Gost是否正常
    if ! check_gost_installed; then
        print_error "Gost 未安装"
        ((issues++))
    fi
    
    # 检查配置文件
    if ! validate_config_file; then
        print_error "配置文件有问题"
        ((issues++))
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet gost; then
        print_warning "Gost 服务未运行"
        ((issues++))
    fi
    
    # 检查端口占用
    local services=$(get_service_names)
    if [[ -n "$services" ]]; then
        while IFS= read -r service; do
            local port=$(get_service_port "$service")
            if [[ -n "$port" ]] && is_port_in_use "$port" && ! is_port_used_by_gost "$port"; then
                print_warning "服务 '$service' 的端口 $port 被其他程序占用"
                ((issues++))
            fi
        done <<< "$services"
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_success "系统健康状态良好"
    else
        print_warning "发现 $issues 个潜在问题"
    fi
    
    return $issues
}

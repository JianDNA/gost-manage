#!/bin/bash

# ========== Gost 转发规则管理脚本 ========== #
# 版本: 2.0.0
# 作者: JianDNA
# 描述: 模块化的 Gost 代理服务器端口转发规则管理工具
# 项目地址: https://github.com/JianDNA/gost-manage

# 设置错误处理，但允许交互式操作
set -e

# ========== 全局变量 ========== #
# 获取脚本目录的更健壮方式
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    # 处理符号链接
    while [[ -L "$source" ]]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" 2>/dev/null && pwd || {
        # 如果 pwd 失败，尝试使用绝对路径
        local dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")"
        [[ -d "$dir" ]] && echo "$dir" || echo "/opt/gost-manage"
    }
}

SCRIPT_DIR="$(get_script_dir)"
VERSION="2.0.0"

# ========== 模块加载 ========== #

# 加载工具函数库
if [[ -f "$SCRIPT_DIR/lib/utils.sh" ]]; then
    source "$SCRIPT_DIR/lib/utils.sh"
else
    echo "错误: 无法找到工具函数库 lib/utils.sh"
    exit 1
fi

# 加载配置管理模块
if [[ -f "$SCRIPT_DIR/modules/config.sh" ]]; then
    source "$SCRIPT_DIR/modules/config.sh"
else
    print_error "无法找到配置管理模块 modules/config.sh"
    exit 1
fi

# 加载环境准备模块
if [[ -f "$SCRIPT_DIR/modules/environment.sh" ]]; then
    source "$SCRIPT_DIR/modules/environment.sh"
else
    print_error "无法找到环境准备模块 modules/environment.sh"
    exit 1
fi

# 加载服务管理模块
if [[ -f "$SCRIPT_DIR/modules/service.sh" ]]; then
    source "$SCRIPT_DIR/modules/service.sh"
else
    print_error "无法找到服务管理模块 modules/service.sh"
    exit 1
fi

# ========== 权限检查 ========== #
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        print_info ""
        print_info "需要 root 权限的原因："
        print_info "• 读写 /etc/gost/config.yml 配置文件"
        print_info "• 管理 systemd 服务"
        print_info "• 安装和配置 Gost"
        exit 1
    fi
}

# ========== 主菜单 ========== #
show_main_menu() {
    clear
    print_title "Gost 转发规则管理 v$VERSION"
    echo
    echo "1) 新增转发规则"
    echo "2) 修改转发规则"
    echo "3) 删除转发规则"
    echo "4) 查看当前配置"
    echo "5) 校验配置文件"
    echo "6) 服务管理"
    echo "7) 系统管理"
    echo "8) 高级功能"
    echo "0) 退出"
    echo
    echo -n -e "${COLOR_YELLOW}请选择操作 (0-8): ${COLOR_RESET}"
}

# 服务管理菜单
show_service_menu() {
    clear
    print_title "服务管理"
    echo
    echo "1) 查看服务状态"
    echo "2) 启动服务"
    echo "3) 停止服务"
    echo "4) 重启服务"
    echo "5) 重新加载配置"
    echo "6) 查看服务日志"
    echo "0) 返回主菜单"
    echo
    echo -n -e "${COLOR_YELLOW}请选择操作 (0-6): ${COLOR_RESET}"
}

# 系统管理菜单
show_system_menu() {
    clear
    print_title "系统管理"
    echo
    echo "1) 环境信息"
    echo "2) 健康检查"
    echo "3) 更新 Gost"
    echo "4) 卸载 Gost"
    echo "5) 清理临时文件"
    echo "6) 查看操作日志"
    echo "0) 返回主菜单"
    echo
    echo -n -e "${COLOR_YELLOW}请选择操作 (0-6): ${COLOR_RESET}"
}

# 高级功能菜单
show_advanced_menu() {
    clear
    print_title "高级功能"
    echo
    echo "1) 批量导入规则"
    echo "2) 导出规则配置"
    echo "3) 备份配置文件"
    echo "4) 恢复配置文件"
    echo "5) 重置所有配置"
    echo "0) 返回主菜单"
    echo
    echo -n -e "${COLOR_YELLOW}请选择操作 (0-5): ${COLOR_RESET}"
}

# ========== 菜单处理函数 ========== #

# 处理主菜单选择
handle_main_menu() {
    local choice
    read -r choice
    
    case "$choice" in
        1) add_service ;;
        2) modify_service ;;
        3) delete_service ;;
        4) 
            clear
            show_config
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        5) 
            clear
            validate_config_file
            echo
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        6) handle_service_menu ;;
        7) handle_system_menu ;;
        8) handle_advanced_menu ;;
        0) 
            print_info "感谢使用 Gost 管理脚本！"
            exit 0
            ;;
        *) 
            print_warning "无效输入，请输入 0-8 之间的数字"
            sleep 1
            ;;
    esac
}

# 处理服务管理菜单
handle_service_menu() {
    while true; do
        show_service_menu
        local choice
        read -r choice
        
        case "$choice" in
            1) 
                clear
                check_service_status
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            2) 
                clear
                start_service
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3) 
                clear
                stop_service
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            4) 
                clear
                restart_service
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            5) 
                clear
                reload_service
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            6) 
                clear
                print_title "Gost 服务日志 (最近50行)"
                journalctl -u gost --no-pager -l -n 50
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0) return ;;
            *) 
                print_warning "无效输入，请输入 0-6 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# 处理系统管理菜单
handle_system_menu() {
    while true; do
        show_system_menu
        local choice
        read -r choice
        
        case "$choice" in
            1) 
                clear
                show_environment_info
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            2) 
                clear
                check_system_health
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3) 
                clear
                update_gost
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            4) 
                clear
                uninstall_gost
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            5) 
                clear
                cleanup_temp_files
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            6) 
                clear
                show_recent_logs 20
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0) return ;;
            *) 
                print_warning "无效输入，请输入 0-6 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# 处理高级功能菜单
handle_advanced_menu() {
    while true; do
        show_advanced_menu
        local choice
        read -r choice
        
        case "$choice" in
            1) import_services ;;
            2) export_services ;;
            3) 
                clear
                backup_config "$CONFIG_FILE"
                echo
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            4) restore_config ;;
            5) reset_config ;;
            0) return ;;
            *) 
                print_warning "无效输入，请输入 0-5 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# ========== 高级功能实现 ========== #

# 恢复配置文件
restore_config() {
    clear
    print_title "恢复配置文件"
    
    local backup_dir=$(dirname "$CONFIG_FILE")
    local backup_files=($(ls -1t "$backup_dir"/*.bak.* 2>/dev/null || true))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        print_error "没有找到备份文件"
        echo
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    print_info "可用的备份文件:"
    for i in "${!backup_files[@]}"; do
        local backup_file="${backup_files[$i]}"
        local backup_time=$(echo "$backup_file" | grep -o '[0-9]\{8\}_[0-9]\{6\}' || echo "未知时间")
        echo "  $((i+1))) $(basename "$backup_file") ($backup_time)"
    done
    
    echo
    echo -n -e "${COLOR_YELLOW}请选择要恢复的备份 (1-${#backup_files[@]}): ${COLOR_RESET}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#backup_files[@]}" ]; then
        local selected_backup="${backup_files[$((choice-1))]}"
        
        if ask_confirmation "确认恢复备份文件 $(basename "$selected_backup")？"; then
            cp "$selected_backup" "$CONFIG_FILE"
            print_success "配置文件恢复成功"
            log_operation "RESTORE_CONFIG" "恢复配置文件: $(basename "$selected_backup")"
            
            if ask_confirmation "是否立即重启 Gost 服务？" "y"; then
                restart_service
            fi
        else
            print_info "取消恢复操作"
        fi
    else
        print_warning "无效选择"
    fi
    
    echo
    read -n 1 -s -r -p "按任意键继续..."
}

# 重置所有配置
reset_config() {
    clear
    print_title "重置所有配置"
    
    print_warning "此操作将删除所有转发规则，恢复到初始状态"
    print_warning "建议在操作前先备份当前配置"
    
    if ask_confirmation "确认重置所有配置？此操作不可恢复！"; then
        # 备份当前配置
        backup_config "$CONFIG_FILE"
        
        # 重置配置文件
        cat > "$CONFIG_FILE" <<EOF
services:
EOF
        
        print_success "配置已重置到初始状态"
        log_operation "RESET_CONFIG" "重置所有配置"
        
        if ask_confirmation "是否立即重启 Gost 服务？" "y"; then
            restart_service
        fi
    else
        print_info "取消重置操作"
    fi
    
    echo
    read -n 1 -s -r -p "按任意键继续..."
}

# ========== 主程序入口 ========== #
main() {
    # 检查 root 权限
    check_root_privileges
    
    # 环境准备
    if ! prepare_environment; then
        print_error "环境准备失败"
        exit 1
    fi
    
    # 主循环
    while true; do
        show_main_menu
        handle_main_menu
    done
}

# ========== 信号处理 ========== #
cleanup_on_exit() {
    print_info "正在清理..."
    exit 0
}

trap cleanup_on_exit SIGINT SIGTERM

# ========== 启动程序 ========== #
main "$@"

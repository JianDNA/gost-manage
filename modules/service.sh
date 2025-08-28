#!/bin/bash

# ========== 服务管理模块 ========== #
# 负责转发规则的增删改查操作

# ========== 服务添加 ========== #

# 添加新的转发服务
add_service() {
    print_title "新增转发规则"
    
    local service_name listen_addr listen_port protocol target_addr
    
    # 获取服务名称
    while true; do
        safe_read "请输入服务名称" service_name ""
        
        if [[ -z "$service_name" ]]; then
            print_warning "服务名称不能为空"
            continue
        fi
        
        # 检查服务名称是否已存在
        if service_exists "$service_name"; then
            print_error "服务名称 '$service_name' 已存在"
            continue
        fi
        
        # 检查服务名称格式（只允许字母、数字、下划线、连字符）
        if [[ ! "$service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            print_warning "服务名称只能包含字母、数字、下划线和连字符"
            continue
        fi
        
        break
    done
    
    # 获取监听地址
    safe_read "请输入监听地址 [默认本机]" listen_addr ""
    
    # 获取监听端口
    while true; do
        local default_port=$(get_available_port)
        safe_read "请输入监听端口 [默认自动分配: $default_port]" listen_port "$default_port"
        
        if ! validate_port "$listen_port"; then
            print_warning "端口号格式错误，请输入 1-65535 之间的数字"
            continue
        fi
        
        # 检查端口是否被占用
        if is_port_in_use "$listen_port"; then
            if is_port_used_by_gost "$listen_port"; then
                print_warning "端口 $listen_port 已被其他 Gost 服务使用"
            else
                print_warning "端口 $listen_port 已被其他程序占用"
            fi
            
            if ask_confirmation "是否使用其他端口？"; then
                continue
            fi
        fi
        
        break
    done
    
    # 获取协议类型
    while true; do
        safe_read "协议类型 [tcp/udp，默认tcp]" protocol "tcp"
        
        if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
            print_warning "协议类型只能是 tcp 或 udp"
            continue
        fi
        
        break
    done
    
    # 获取目标地址
    while true; do
        safe_read "请输入目标地址（IPv4:PORT、[IPv6]:PORT 或 DOMAIN:PORT）" target_addr ""

        if [[ -z "$target_addr" ]]; then
            print_warning "目标地址不能为空"
            continue
        fi

        if ! validate_target_address "$target_addr"; then
            print_warning "目标地址格式错误，请使用以下格式之一："
            print_warning "  IPv4: 192.168.1.100:80"
            print_warning "  IPv6: [2001:db8::1]:80"
            print_warning "  域名: example.com:80"
            continue
        fi

        break
    done
    
    # 显示配置摘要
    print_separator
    print_info "配置摘要:"
    echo "  服务名称: $service_name"
    echo "  监听地址: ${listen_addr:-"所有接口"}"
    echo "  监听端口: $listen_port"
    echo "  协议类型: $protocol"
    echo "  目标地址: $target_addr"
    print_separator
    
    # 确认添加
    if ask_confirmation "确认添加此转发规则？" "y"; then
        if add_service_to_config "$service_name" "$listen_addr" "$listen_port" "$protocol" "$target_addr"; then
            print_success "转发规则添加成功"
            
            # 询问是否重启服务
            if ask_confirmation "是否立即重启 Gost 服务以应用配置？" "y"; then
                restart_service
            fi
        else
            print_error "转发规则添加失败"
        fi
    else
        print_info "取消添加操作"
    fi
    
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# ========== 服务修改 ========== #

modify_service() {
    print_title "修改转发规则"

    local count=$(get_service_count)
    if [[ $count -eq 0 ]]; then
        print_error "没有可修改的转发规则"
        echo
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi

    # 显示服务列表
    list_services

    # 使用缓存获取服务名称以提高性能
    local services
    if command -v get_cached_service_names >/dev/null 2>&1; then
        services=$(get_cached_service_names)
    else
        services=$(get_service_names)
    fi
    local service_name
    while true; do
        echo -n -e "${COLOR_YELLOW}请选择服务序号 (1-$count): ${COLOR_RESET}"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            service_name=$(echo "$services" | sed -n "${choice}p")
            break
        else
            print_warning "无效输入，请输入 1-$count 之间的数字"
        fi
    done

    if [[ -z "$service_name" ]]; then
        return
    fi
    
    print_separator
    print_info "当前服务配置:"
    
    # 获取当前配置
    local current_port=$(get_service_port "$service_name")
    local current_target=$(get_service_target "$service_name")
    local current_protocol=$(get_service_protocol "$service_name")
    
    echo "  服务名称: $service_name"
    echo "  监听端口: $current_port"
    echo "  协议类型: $current_protocol"
    echo "  目标地址: $current_target"
    print_separator
    
    # 获取新配置
    local new_service_name new_listen_addr new_listen_port new_protocol new_target_addr

    # 服务名称
    while true; do
        safe_read "请输入新的服务名称 [当前: $service_name]" new_service_name "$service_name"

        if [[ -z "$new_service_name" ]]; then
            print_warning "服务名称不能为空"
            continue
        fi

        # 检查服务名称格式（只允许字母、数字、下划线、连字符）
        if [[ ! "$new_service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            print_warning "服务名称只能包含字母、数字、下划线和连字符"
            continue
        fi

        # 如果服务名称没有变化，跳过重复检查
        if [[ "$new_service_name" != "$service_name" ]]; then
            # 检查新服务名称是否已存在
            if service_exists "$new_service_name"; then
                print_error "服务名称 '$new_service_name' 已存在"
                continue
            fi
        fi

        break
    done

    # 监听地址（从当前配置中提取）
    safe_read "请输入新的监听地址 [默认本机]" new_listen_addr ""
    
    # 监听端口
    while true; do
        safe_read "请输入新的监听端口 [当前: $current_port]" new_listen_port "$current_port"
        
        if ! validate_port "$new_listen_port"; then
            print_warning "端口号格式错误，请输入 1-65535 之间的数字"
            continue
        fi
        
        # 如果端口没有变化，跳过占用检查
        if [[ "$new_listen_port" != "$current_port" ]]; then
            if is_port_in_use "$new_listen_port"; then
                if is_port_used_by_gost "$new_listen_port"; then
                    print_warning "端口 $new_listen_port 已被其他 Gost 服务使用"
                else
                    print_warning "端口 $new_listen_port 已被其他程序占用"
                fi
                
                if ! ask_confirmation "是否继续使用此端口？"; then
                    continue
                fi
            fi
        fi
        
        break
    done
    
    # 协议类型
    while true; do
        safe_read "协议类型 [tcp/udp，当前: $current_protocol]" new_protocol "$current_protocol"
        
        if [[ "$new_protocol" != "tcp" && "$new_protocol" != "udp" ]]; then
            print_warning "协议类型只能是 tcp 或 udp"
            continue
        fi
        
        break
    done
    
    # 目标地址
    while true; do
        safe_read "请输入新的目标地址 [当前: $current_target]" new_target_addr "$current_target"

        if [[ -z "$new_target_addr" ]]; then
            print_warning "目标地址不能为空"
            continue
        fi

        if ! validate_target_address "$new_target_addr"; then
            print_warning "目标地址格式错误，请使用以下格式之一："
            print_warning "  IPv4: 192.168.1.100:80"
            print_warning "  IPv6: [2001:db8::1]:80"
            print_warning "  域名: example.com:80"
            continue
        fi

        break
    done
    
    # 显示修改摘要
    print_separator
    print_info "修改摘要:"
    if [[ "$service_name" != "$new_service_name" ]]; then
        echo "  服务名称: $service_name → $new_service_name"
    else
        echo "  服务名称: $service_name"
    fi
    echo "  监听地址: ${new_listen_addr:-"所有接口"}"
    echo "  监听端口: $current_port → $new_listen_port"
    echo "  协议类型: $current_protocol → $new_protocol"
    echo "  目标地址: $current_target → $new_target_addr"
    print_separator
    
    # 确认修改
    if ask_confirmation "确认修改此转发规则？" "y"; then
        if update_service_in_config "$service_name" "$new_service_name" "$new_listen_addr" "$new_listen_port" "$new_protocol" "$new_target_addr"; then
            print_success "转发规则修改成功"

            # 询问是否重启服务
            if ask_confirmation "是否立即重启 Gost 服务以应用配置？" "y"; then
                restart_service
            fi
        else
            print_error "转发规则修改失败"
        fi
    else
        print_info "取消修改操作"
    fi
    
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# ========== 服务删除 ========== #

# 删除转发服务
delete_service() {
    print_title "删除转发规则"

    local count=$(get_service_count)
    if [[ $count -eq 0 ]]; then
        print_error "没有可删除的转发规则"
        echo
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi

    # 显示服务列表
    list_services

    # 使用缓存获取服务名称以提高性能
    local services
    if command -v get_cached_service_names >/dev/null 2>&1; then
        services=$(get_cached_service_names)
    else
        services=$(get_service_names)
    fi
    local service_name
    while true; do
        echo -n -e "${COLOR_YELLOW}请选择服务序号 (1-$count): ${COLOR_RESET}"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            service_name=$(echo "$services" | sed -n "${choice}p")
            break
        else
            print_warning "无效输入，请输入 1-$count 之间的数字"
        fi
    done

    if [[ -z "$service_name" ]]; then
        return
    fi
    
    print_separator
    print_info "将要删除的服务配置:"
    
    # 显示服务详细信息
    local port=$(get_service_port "$service_name")
    local target=$(get_service_target "$service_name")
    local protocol=$(get_service_protocol "$service_name")
    
    echo "  服务名称: $service_name"
    echo "  监听端口: $port"
    echo "  协议类型: $protocol"
    echo "  目标地址: $target"
    print_separator
    
    # 确认删除
    if ask_confirmation "确认删除此转发规则？此操作不可恢复！"; then
        if delete_service_from_config "$service_name"; then
            print_success "转发规则删除成功"
            
            # 询问是否重启服务
            if ask_confirmation "是否立即重启 Gost 服务以应用配置？" "y"; then
                restart_service
            fi
        else
            print_error "转发规则删除失败"
        fi
    else
        print_info "取消删除操作"
    fi
    
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# ========== 批量操作 ========== #

# 批量添加服务（从文件导入）
import_services() {
    print_title "批量导入转发规则"
    
    local import_file
    safe_read "请输入导入文件路径" import_file ""
    
    if [[ ! -f "$import_file" ]]; then
        print_error "文件不存在: $import_file"
        return 1
    fi
    
    print_info "正在解析导入文件..."
    
    local line_num=0
    local success_count=0
    local error_count=0
    
    while IFS=',' read -r service_name listen_addr listen_port protocol target_addr; do
        ((line_num++))
        
        # 跳过空行和注释行
        if [[ -z "$service_name" || "$service_name" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 去除前后空格
        service_name=$(echo "$service_name" | xargs)
        listen_addr=$(echo "$listen_addr" | xargs)
        listen_port=$(echo "$listen_port" | xargs)
        protocol=$(echo "$protocol" | xargs)
        target_addr=$(echo "$target_addr" | xargs)
        
        print_info "处理第 $line_num 行: $service_name"
        
        # 验证数据
        if [[ -z "$service_name" || -z "$listen_port" || -z "$protocol" || -z "$target_addr" ]]; then
            print_error "第 $line_num 行数据不完整"
            ((error_count++))
            continue
        fi
        
        if service_exists "$service_name"; then
            print_warning "服务 '$service_name' 已存在，跳过"
            continue
        fi
        
        if ! validate_port "$listen_port"; then
            print_error "第 $line_num 行端口格式错误: $listen_port"
            ((error_count++))
            continue
        fi
        
        if ! validate_target_address "$target_addr"; then
            print_error "第 $line_num 行目标地址格式错误: $target_addr"
            ((error_count++))
            continue
        fi
        
        # 添加服务
        if add_service_to_config "$service_name" "$listen_addr" "$listen_port" "$protocol" "$target_addr"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        
    done < "$import_file"
    
    print_separator
    print_info "导入完成:"
    echo "  成功: $success_count 个"
    echo "  失败: $error_count 个"
    
    if [[ $success_count -gt 0 ]]; then
        if ask_confirmation "是否立即重启 Gost 服务以应用配置？" "y"; then
            restart_service
        fi
    fi
    
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 导出服务配置
export_services() {
    print_title "导出转发规则"
    
    local count=$(get_service_count)
    if [[ $count -eq 0 ]]; then
        print_error "没有可导出的转发规则"
        echo
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi
    
    local export_file
    safe_read "请输入导出文件路径 [默认: gost-rules.csv]" export_file "gost-rules.csv"
    
    # 创建CSV文件
    echo "# Gost转发规则导出文件" > "$export_file"
    echo "# 格式: 服务名称,监听地址,监听端口,协议类型,目标地址" >> "$export_file"
    echo "# 目标地址支持: IPv4:PORT、[IPv6]:PORT、DOMAIN:PORT" >> "$export_file"
    echo "# 导出时间: $(date)" >> "$export_file"
    
    local services=$(get_service_names)
    while IFS= read -r service; do
        local port=$(get_service_port "$service")
        local target=$(get_service_target "$service")
        local protocol=$(get_service_protocol "$service")
        
        echo "$service,,${port},$protocol,$target" >> "$export_file"
    done <<< "$services"
    
    print_success "转发规则已导出到: $export_file"
    print_info "共导出 $count 个规则"
    
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
}

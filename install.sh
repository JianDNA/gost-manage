#!/bin/bash

# ========== Gost 管理脚本安装器 ========== #
# 版本: 2.0.0
# 描述: 下载并安装模块化的 Gost 管理脚本

set -euo pipefail

# ========== 配置变量 ========== #
GITHUB_REPO="JianDNA/gost-manage"
GITHUB_BRANCH="main"
INSTALL_DIR="/opt/gost-manage"
SCRIPT_NAME="gost-manage"

# ========== 颜色定义 ========== #
COLOR_RESET=$(tput sgr0)
COLOR_RED=$(tput setaf 1)
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_BLUE=$(tput setaf 4)
COLOR_CYAN=$(tput setaf 6)

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

# ========== 权限检查 ========== #
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此安装脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# ========== 依赖检查 ========== #
check_dependencies() {
    local missing_deps=()

    local required_commands=("curl" "tar" "chmod")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "缺少必要的命令: ${missing_deps[*]}"
        print_info "请先安装这些依赖项"
        exit 1
    fi
}

# ========== 网络检查 ========== #
check_network() {
    print_info "检查网络连接..."
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null; then
        print_error "无法连接到 GitHub，请检查网络连接"
        exit 1
    fi
    print_success "网络连接正常"
}

# ========== 下载和安装 ========== #
download_and_install() {
    print_info "正在下载 Gost 管理脚本..."

    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # 下载项目文件
    local download_url="https://github.com/${GITHUB_REPO}/archive/${GITHUB_BRANCH}.tar.gz"

    if ! curl -sSL "$download_url" -o gost-manage.tar.gz; then
        print_error "下载失败"
        rm -rf "$temp_dir"
        exit 1
    fi

    print_success "下载完成"

    # 解压文件
    print_info "正在解压文件..."
    tar -xzf gost-manage.tar.gz

    # 查找解压后的目录
    local extracted_dir=$(find . -maxdepth 1 -type d -name "gost-manage-*" | head -1)
    if [[ -z "$extracted_dir" ]]; then
        print_error "解压失败，找不到项目目录"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 创建安装目录
    print_info "正在安装到 $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    # 复制文件
    cp -r "$extracted_dir"/* "$INSTALL_DIR/"

    # 设置执行权限
    chmod +x "$INSTALL_DIR/gost-manage.sh"
    chmod +x "$INSTALL_DIR/lib/utils.sh"
    chmod +x "$INSTALL_DIR/modules/"*.sh

    # 创建系统链接
    ln -sf "$INSTALL_DIR/gost-manage.sh" "/usr/local/bin/$SCRIPT_NAME"

    # 清理临时文件
    rm -rf "$temp_dir"

    print_success "安装完成"
}

# ========== 验证安装 ========== #
verify_installation() {
    print_info "验证安装..."

    if [[ -f "$INSTALL_DIR/gost-manage.sh" ]] && [[ -x "$INSTALL_DIR/gost-manage.sh" ]]; then
        print_success "主脚本安装正确"
    else
        print_error "主脚本安装失败"
        return 1
    fi

    if [[ -f "$INSTALL_DIR/lib/utils.sh" ]]; then
        print_success "工具函数库安装正确"
    else
        print_error "工具函数库安装失败"
        return 1
    fi

    local modules=("config.sh" "environment.sh" "service.sh")
    for module in "${modules[@]}"; do
        if [[ -f "$INSTALL_DIR/modules/$module" ]]; then
            print_success "模块 $module 安装正确"
        else
            print_error "模块 $module 安装失败"
            return 1
        fi
    done

    if [[ -L "/usr/local/bin/$SCRIPT_NAME" ]]; then
        print_success "系统链接创建成功"
    else
        print_error "系统链接创建失败"
        return 1
    fi

    return 0
}

# ========== 主安装流程 ========== #
main() {
    print_title "Gost 管理脚本安装器 v2.0.0"

    # 检查权限
    check_root

    # 检查依赖
    check_dependencies

    # 检查网络
    check_network

    # 下载和安装
    download_and_install

    # 验证安装
    if verify_installation; then
        print_title "安装成功"
        print_info "安装位置: $INSTALL_DIR"
        print_info "可执行命令: $SCRIPT_NAME"
        print_info "使用方法: sudo $SCRIPT_NAME"
        echo

        # 询问是否立即运行
        echo -n -e "${COLOR_YELLOW}是否立即运行 Gost 管理脚本？[Y/n]: ${COLOR_RESET}"
        read -r response

        if [[ -z "$response" || "$response" =~ ^[Yy] ]]; then
            echo
            print_info "切换到安装目录并启动脚本..."
            cd "$INSTALL_DIR"
            exec "$INSTALL_DIR/gost-manage.sh"
        else
            print_info "您可以随时使用 'sudo $SCRIPT_NAME' 命令运行脚本"
        fi
    else
        print_error "安装验证失败"
        exit 1
    fi
}

# ========== 启动安装 ========== #
main "$@"

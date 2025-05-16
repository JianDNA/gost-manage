# Gost 转发规则管理脚本

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个高效、友好的 Bash 脚本，用于简化 Gost 代理服务器的端口转发规则管理。提供了直观的交互式菜单，让您轻松创建、修改和管理转发规则，无需手动编辑复杂的 YAML 配置。

## 功能特点

- **简单易用的交互式菜单**：无需记忆复杂命令或配置语法
- **完整的转发规则管理**：
  - 新增转发规则
  - 修改现有规则
  - 删除规则
  - 查看当前配置
  - 验证配置有效性
- **智能端口管理**：
  - 自动检测端口占用情况
  - 区分 Gost 自身使用和其他程序占用的端口
  - 自动分配可用端口
- **全面的配置校验**：
  - YAML 语法检查
  - 端口占用分析
  - 详细的错误提示和修复建议
- **自动化安装和依赖管理**：自动安装 Gost 和必要依赖
- **系统兼容性**：支持多种 Linux 发行版（Debian/Ubuntu、CentOS/RHEL、Fedora 等）

## 安装方法

### 方法 1：一步式安装（推荐）
```bash
curl -sSL https://raw.githubusercontent.com/JianDNA/gost-manage/main/install.sh -o install.sh && bash install.sh
```


### 方法 2：手动安装
```bash

# 下载脚本
curl -sSL https://raw.githubusercontent.com/JianDNA/gost-manage/main/gost.sh -o gost.sh

# 设置执行权限
chmod +x gost.sh

# 运行脚本
./gost.sh

```


### 首次运行

首次运行时，脚本会：
1. 检查并安装 Gost（如果未安装）
2. 创建基本配置文件
3. 设置 systemd 服务
4. 提示安装必要的依赖项（如 Python3 和 PyYAML，用于进阶 YAML 语法检查）

## 使用指南

### 主菜单选项

脚本提供以下功能选项：

1. **新增转发规则**：添加新的端口转发配置
2. **修改转发规则**：更新现有转发规则的设置
3. **删除转发规则**：移除不需要的转发规则
4. **查看当前配置**：显示完整的配置文件内容
5. **校验配置文件**：检查配置文件格式和端口占用情况
0. **退出**：退出脚本

### 新增转发规则

添加新规则时，您需要提供：

- **服务名称**：规则的唯一标识符
- **监听地址**：本地监听地址（留空表示监听所有接口）
- **监听端口**：本地监听端口（可自动分配）
- **协议类型**：tcp 或 udp
- **目标地址**：转发目标的 IP:端口

例如，创建 HTTPS 转发：
```
请输入服务名称: web_proxy
请输入监听地址 [默认本机]:
请输入监听端口 [默认自动分配]: 443
协议类型 [tcp/udp，默认tcp]: tcp
请输入目标地址（IP:PORT）: 192.168.1.100:8443
```

### 修改转发规则

修改时，系统会先显示当前所有规则，然后：

1. 选择要修改的规则序号
2. 显示该规则的当前配置
3. 可以逐个更新各项配置
4. 留空表示保持当前值不变

### 校验配置文件

校验功能会进行：

- YAML 语法检查
- 配置结构验证
- 端口占用情况分析
- 详细的错误信息和修复建议

## 配置格式

脚本管理的配置文件位于 `/etc/gost/config.yml`，使用标准的 Gost 配置格式：

```yaml
services:
- name: service_name
  addr: :port_number
  handler:
    type: protocol
  listener:
    type: protocol
  forwarder:
    nodes:
    - name: service_name
      addr: target_ip:target_port
```

## 常见问题解答

### 端口已被占用？

如果端口被其他程序占用，脚本会提示您选择其他端口或使用自动分配功能。如果端口被 Gost 自身使用，在修改配置时不会视为冲突。

### 配置格式错误？

使用"校验配置文件"功能可以检测并自动修复常见的配置格式问题，如不正确的缩进或语法错误。

### 如何修改服务启动选项？

服务配置文件位于 `/etc/systemd/system/gost.service`，可以手动编辑以修改启动参数。

## 故障排除

### 服务无法启动

1. 使用脚本的"校验配置文件"功能检查配置
2. 查看系统日志：`journalctl -u gost.service`
3. 检查端口占用情况：`ss -tuln`

### 连接被拒绝

1. 确认目标服务器正在运行
2. 检查防火墙设置（使用 `iptables -L` 或 `ufw status`）
3. 验证目标 IP 和端口是否正确

## 系统要求

- Linux 操作系统
- Bash 4.0+
- root 权限（用于服务管理和端口监听）
- 可选：Python3 和 PyYAML（用于高级 YAML 语法检查）

## 许可证

该项目采用 MIT 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件。

## 贡献

欢迎提交问题报告和改进建议！

---

希望您喜欢使用这个脚本！如有任何问题或需要改进的地方，请随时联系。
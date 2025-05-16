#!/bin/bash
# 安装脚本 - install.sh
echo "正在下载 Gost 管理脚本..."
curl -sSL https://raw.githubusercontent.com/JianDNA/gost-manage/main/gost.sh -o gost.sh
chmod +x gost.sh
echo "下载完成，开始执行..."
exec ./gost.sh

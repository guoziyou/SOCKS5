#!/bin/bash

# ==========================================
# SOCKS5 一键安装脚本 (GOST版 - 修复IP获取)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${RED}错误：此脚本必须以 root 权限运行。${NC}"
   exit 1
fi

INFO_FILE="/root/gost_socks5_info.txt"
SERVICE_FILE="/etc/systemd/system/gost.service"
BIN_PATH="/usr/local/bin/gost"

# --- URL 编码 ---
url_encode() {
    local string="$1"
    local encoded=""
    local char
    for (( i=0; i<${#string}; i++ )); do
        char=${string:$i:1}
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    echo "$encoded"
}

# --- 获取公网IP (增强版) ---
get_public_ip() {
    local version=$1
    local ip=""
    
    # 尝试源 1: icanhazip (最稳定)
    if [ "$version" == "4" ]; then
        ip=$(curl -s4 -m 5 --user-agent "Mozilla/5.0" https://ipv4.icanhazip.com)
        # 如果失败或返回了html错误，尝试源 2: ipify
        if [ -z "$ip" ] || [[ "$ip" == *"html"* ]] || [[ "$ip" == *"DOCTYPE"* ]]; then
            ip=$(curl -s4 -m 5 --user-agent "Mozilla/5.0" https://api.ipify.org)
        fi
    elif [ "$version" == "6" ]; then
        ip=$(curl -s6 -m 5 --user-agent "Mozilla/5.0" https://ipv6.icanhazip.com)
        if [ -z "$ip" ] || [[ "$ip" == *"html"* ]] || [[ "$ip" == *"DOCTYPE"* ]]; then
            ip=$(curl -s6 -m 5 --user-agent "Mozilla/5.0" https://api64.ipify.org)
        fi
    fi

    # 清理可能存在的空格
    echo $ip | tr -d '[:space:]'
}

# --- 显示连接信息 ---
show_links() {
    if [ ! -f "$INFO_FILE" ]; then
        echo -e "${RED}错误：未找到配置文件，请先安装。${NC}"
        return
    fi
    source $INFO_FILE
    
    echo -e "${YELLOW}正在获取服务器 IP...${NC}"
    IPV4=$(get_public_ip 4)
    IPV6=$(get_public_ip 6)
    
    ENCODED_PASS=$(url_encode "$PASSWORD")
    
    echo -e "\n${GREEN}=== SOCKS5 节点信息 ===${NC}"
    echo -e "状态: $(systemctl is-active gost 2>/dev/null || echo '未运行')"
    echo -e "-------------------------------------"
    
    if [ -n "$IPV4" ] && [[ "$IPV4" != *"html"* ]]; then
        echo -e "${YELLOW}IPv4 链接:${NC}"
        echo "socks5://${USERNAME}:${ENCODED_PASS}@${IPV4}:${PORT}"
    else
        echo -e "${RED}警告: 无法获取有效 IPv4 地址 (可能无IPv4网络)${NC}"
    fi
    
    echo ""

    if [ -n "$IPV6" ] && [[ "$IPV6" != *"html"* ]]; then
        echo -e "${YELLOW}IPv6 链接:${NC}"
        echo "socks5://${USERNAME}:${ENCODED_PASS}@[${IPV6}]:${PORT}"
    fi
    
    echo -e "-------------------------------------"
    echo -e "端口: $PORT"
    echo -e "用户: $USERNAME"
    echo -e "密码: $PASSWORD"
    echo -e "-------------------------------------"
}

# --- 安装 GOST ---
install_socks5() {
    echo -e "${YELLOW}--- 开始安装 SOCKS5 (GOST) ---${NC}"

    # 1. 环境准备
    apt-get update
    apt-get install -y wget curl gzip

    # 2. 下载 GOST 二进制文件 (不依赖 apt 源)
    echo -e "${YELLOW}正在下载 GOST 主程序...${NC}"
    ARCH=$(uname -m)
    GOST_VER="2.11.5"
    URL=""
    
    if [[ "$ARCH" == "x86_64" ]]; then
        URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost-linux-amd64-${GOST_VER}.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost-linux-arm64-${GOST_VER}.gz"
    else
        echo -e "${RED}不支持的架构: $ARCH${NC}"
        exit 1
    fi

    wget -qO gost.gz "$URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败，请检查网络连接！${NC}"
        exit 1
    fi

    gzip -d -f gost.gz
    mv gost $BIN_PATH
    chmod +x $BIN_PATH
    
    if ! command -v $BIN_PATH &> /dev/null; then
        echo -e "${RED}安装失败：二进制文件无法执行。${NC}"
        exit 1
    fi

    # 3. 配置参数
    USERNAME="user$(openssl rand -hex 3)"
    PASSWORD=$(openssl rand -base64 10)
    
    while true; do
        PORT=$((RANDOM % 20000 + 30000))
        if ! ss -lntu | grep -q ":${PORT}\b"; then
            break
        fi
    done

    # 4. 创建服务
    echo -e "${YELLOW}正在配置系统服务...${NC}"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=GOST SOCKS5 Server
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH -L "$USERNAME:$PASSWORD@:$PORT"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # 5. 启动服务
    systemctl daemon-reload
    systemctl enable gost
    systemctl restart gost

    # 6. 检查状态
    sleep 2
    if systemctl is-active --quiet gost; then
        echo -e "${GREEN}服务启动成功！${NC}"
    else
        echo -e "${RED}服务启动失败！${NC}"
        systemctl status gost
        exit 1
    fi

    # 7. 保存信息
    echo "PORT=$PORT" > $INFO_FILE
    echo "USERNAME=$USERNAME" >> $INFO_FILE
    echo "PASSWORD=$PASSWORD" >> $INFO_FILE
    chmod 600 $INFO_FILE

    show_links
}

# --- 卸载 ---
uninstall_socks5() {
    echo -e "${YELLOW}正在卸载...${NC}"
    systemctl stop gost
    systemctl disable gost
    rm -f $SERVICE_FILE
    rm -f $BIN_PATH
    rm -f $INFO_FILE
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成。${NC}"
}

# --- 菜单 ---
main_menu() {
    clear
    echo "SOCKS5 管理脚本 (GOST版)"
    echo "=========================="
    echo "1. 安装 SOCKS5"
    echo "2. 卸载 SOCKS5"
    echo "3. 查看链接 (修复IP显示)"
    echo "4. 退出"
    echo ""
    read -p "选择: " choice
    case $choice in
        1) install_socks5 ;;
        2) uninstall_socks5 ;;
        3) show_links ;;
        4) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu

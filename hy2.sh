#!/bin/bash

# ======================================================
#      Hysteria2 一体化工具脚本 (安装/卸载/检测)
#      适配 Alpine / Debian / Ubuntu
#      作者: ChatGPT (OpenAI)
# ======================================================

set -e

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG_FILE="/etc/hysteria/config.yaml"
BIN="/usr/local/bin/hysteria"
SERVICE_FILE="/etc/systemd/system/hysteria.service"
PORT=""
PASSWORD=""

# === 生成随机密码 ===
random_pass() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# === 安装 Hysteria2 ===
install_hysteria() {
    echo -e "${YELLOW}开始安装 Hysteria2...${NC}"

    # 检测系统并安装依赖
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl wget openssl iptables net-tools
    elif command -v apk >/dev/null 2>&1; then
        apk update
        apk add curl wget openssl iptables busybox-extras
    else
        echo -e "${RED}不支持的系统，安装中止${NC}"
        exit 1
    fi

    # 固定版本下载 URL（v2.6.1）
    LATEST_URL="https://github.com/apernet/hysteria/releases/download/app/v2.6.1/hysteria-linux-amd64"
    curl -Lo /usr/local/bin/hysteria "$LATEST_URL"
    chmod +x /usr/local/bin/hysteria

    # 生成配置文件
    mkdir -p /etc/hysteria
    PORT=${PORT:-443}
    PASSWORD=$(random_pass)

    cat > "$CONFIG_FILE" <<EOF
listen: 0.0.0.0:$PORT
obfs: false
acme:
  disabled: true
tls:
  cert: /etc/hysteria/self-cert.crt
  key: /etc/hysteria/self-cert.key
auth:
  password: "$PASSWORD"
EOF

    # 生成自签证书
    openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-cert.key \
        -out /etc/hysteria/self-cert.crt -days 3650 -nodes -subj "/CN=bing.com"

    # 写入 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria

    # 开放防火墙端口（避免重复插入）
    if ! iptables -C INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    fi

    echo -e "\n${GREEN}Hysteria2 安装完成！${NC}"
    echo -e "${YELLOW}连接信息：${NC}"
    echo -e "${GREEN}hysteria2://$PASSWORD@$(curl -s https://api64.ipify.org):$PORT/?insecure=1${NC}"
}

# === 卸载 Hysteria2 ===
uninstall_hysteria() {
    echo -e "${YELLOW}卸载 Hysteria2...${NC}"
    systemctl stop hysteria || true
    systemctl disable hysteria || true
    rm -f "$SERVICE_FILE"
    rm -f "$BIN"
    rm -rf /etc/hysteria
    systemctl daemon-reload
    echo -e "${GREEN}Hysteria2 已卸载${NC}"
}

# === 检查 Hysteria2 状态 ===
check_hysteria() {
    echo -e "${YELLOW}① 检查服务状态...${NC}"
    systemctl is-active --quiet hysteria && \
        echo -e "${GREEN}Hysteria2 正在运行${NC}" || \
        echo -e "${RED}Hysteria2 未运行${NC}"

    echo -e "${YELLOW}② 检查端口监听...${NC}"
    PORT=$(grep -Po '(?<=listen: 0.0.0.0:)\d+' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$PORT" ] && ss -uln | grep -q ":$PORT" && \
        echo -e "${GREEN}UDP 端口 $PORT 正在监听${NC}" || \
        echo -e "${RED}未监听端口 $PORT${NC}"

    echo -e "${YELLOW}③ 防火墙状态...${NC}"
    iptables -L INPUT -n | grep -q "udp dpt:$PORT" && \
        echo -e "${GREEN}iptables 已放行 UDP $PORT${NC}" || \
        echo -e "${RED}iptables 未放行此端口${NC}"

    echo -e "${YELLOW}④ 公网 IP: ${NC}$(curl -s https://api64.ipify.org)"

    PASSWORD=$(grep -Po '(?<=password: ).*' "$CONFIG_FILE" 2>/dev/null)
    echo -e "${YELLOW}⑤ 节点链接：${NC}"
    echo -e "${GREEN}hysteria2://$PASSWORD@$(curl -s https://api64.ipify.org):$PORT/?insecure=1${NC}"
}

# === 菜单 ===
echo -e "\n${YELLOW}Hysteria2 一体化工具脚本${NC}"
echo "1. 安装 Hysteria2"
echo "2. 卸载 Hysteria2"
echo "3. 检查运行状态"
echo "0. 退出"
echo -n "请输入选项 [0-3]: "
read choice

case $choice in
    1)
        echo -n "请输入端口号 (1024-65535，默认 443): "; read p
        PORT=${p:-443}
        install_hysteria
        ;;
    2)
        uninstall_hysteria
        ;;
    3)
        check_hysteria
        ;;
    *)
        echo -e "${YELLOW}已退出${NC}"
        ;;
esac

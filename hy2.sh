#!/bin/bash

# ======================================================
#      Hysteria2 一体化工具脚本 (安装/卸载/检测)
#      支持 Alpine(OpenRC) / Debian / Ubuntu(systemd)
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
    curl -Lo "$BIN" "$LATEST_URL"
    chmod +x "$BIN"

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

    # 根据服务管理器写服务脚本
    if command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 systemd，配置 systemd 服务...${NC}"
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$BIN server -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reexec
        systemctl daemon-reload
        systemctl enable hysteria
        systemctl restart hysteria

    elif command -v rc-service >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 OpenRC，配置 OpenRC 服务...${NC}"
        RC_SCRIPT="/etc/init.d/hysteria"
        cat > "$RC_SCRIPT" <<EOF
#!/sbin/openrc-run

command=$BIN
command_args="server -c $CONFIG_FILE"
pidfile=/run/hysteria.pid

depend() {
    need net
}

start_pre() {
    checkpath --directory --mode 0755 /run
}
EOF
        chmod +x "$RC_SCRIPT"
        rc-update add hysteria default
        rc-service hysteria restart

    else
        echo -e "${RED}无法检测到 systemd 或 OpenRC，无法配置服务${NC}"
        exit 1
    fi

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

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop hysteria || true
        systemctl disable hysteria || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service hysteria stop || true
        rc-update del hysteria default || true
        rm -f /etc/init.d/hysteria
    else
        echo -e "${RED}未检测到 systemd 或 OpenRC，无法卸载服务${NC}"
    fi

    rm -f "$BIN"
    rm -rf /etc/hysteria

    echo -e "${GREEN}Hysteria2 已卸载${NC}"
}

# === 检查 Hysteria2 状态 ===
check_hysteria() {
    echo -e "${YELLOW}① 检查服务状态...${NC}"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet hysteria && \
            echo -e "${GREEN}Hysteria2 正在运行${NC}" || \
            echo -e "${RED}Hysteria2 未运行${NC}"
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service hysteria status >/dev/null 2>&1 && \
            echo -e "${GREEN}Hysteria2 正在运行${NC}" || \
            echo -e "${RED}Hysteria2 未运行${NC}"
    else
        echo -e "${RED}未检测到 systemd 或 OpenRC，无法检查服务状态${NC}"
    fi

    echo -e "${YELLOW}② 检查端口监听...${NC}"
    PORT=$(grep -Po '(?<=listen: 0.0.0.0:)\d+' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$PORT" ]; then
        if ss -uln | grep -q ":$PORT"; then
            echo -e "${GREEN}UDP 端口 $PORT 正在监听${NC}"
        else
            echo -e "${RED}未监听端口 $PORT${NC}"
        fi
    else
        echo -e "${RED}未找到配置端口${NC}"
    fi

    echo -e "${YELLOW}③ 防火墙状态...${NC}"
    if iptables -L INPUT -n | grep -q "udp dpt:$PORT"; then
        echo -e "${GREEN}iptables 已放行 UDP $PORT${NC}"
    else
        echo -e "${RED}iptables 未放行此端口${NC}"
    fi

    echo -e "${YELLOW}④ 公网 IP: ${NC}$(curl -s https://api64.ipify.org)"

    PASSWORD=$(grep -Po '(?<=password: ).*' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$PASSWORD" ] && [ -n "$PORT" ]; then
        echo -e "${YELLOW}⑤ 节点链接：${NC}"
        echo -e "${GREEN}hysteria2://$PASSWORD@$(curl -s https://api64.ipify.org):$PORT/?insecure=1${NC}"
    fi
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

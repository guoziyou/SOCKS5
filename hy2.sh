#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：请以root用户运行此脚本！${NC}"
    exit 1
fi

# 参数定义
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
HYSTERIA_VERSION="2.6.1"
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/app/v$HYSTERIA_VERSION/hysteria-linux-amd64"
BACKUP_URL="https://ghproxy.com/https://github.com/apernet/hysteria/releases/download/app/v$HYSTERIA_VERSION/hysteria-linux-amd64"

# 生成随机密码
HY2_PASSWORD=$(openssl rand -base64 12)
echo -e "${YELLOW}已生成随机密码：$HY2_PASSWORD${NC}"

# 提示用户输入端口
while true; do
    read -p "请输入 Hysteria2 端口（1024-65535，推荐 443）：" HY2_PORT
    HY2_PORT=${HY2_PORT:-443}
    if [[ "$HY2_PORT" =~ ^[0-9]+$ ]] && [ "$HY2_PORT" -ge 1024 ] && [ "$HY2_PORT" -le 65535 ]; then
        echo -e "${GREEN}已设置端口：$HY2_PORT${NC}"
        break
    else
        echo -e "${RED}错误：端口必须是 1024 到 65535 之间的数字！${NC}"
    fi
done

# 更新系统并安装依赖
echo -e "${YELLOW}正在更新系统并安装依赖...${NC}"
apt-get update -y
apt-get install -y curl openssl libc6 || {
    echo -e "${RED}错误：依赖安装失败，请检查网络或包源！${NC}"
    exit 1
}

# 下载 Hysteria2
echo -e "${YELLOW}正在下载 Hysteria2 v$HYSTERIA_VERSION（架构：x86_64）...${NC}"
for url in "$DOWNLOAD_URL" "$BACKUP_URL"; do
    if curl -L -o /usr/local/bin/hysteria "$url"; then
        echo -e "${GREEN}下载成功！${NC}"
        break
    else
        echo -e "${YELLOW}下载失败，尝试备用 URL...${NC}"
        sleep 2
    fi
done

# 验证下载文件
if [ ! -s /usr/local/bin/hysteria ] || [ $(stat -c %s /usr/local/bin/hysteria) -lt 1000000 ]; then
    echo -e "${RED}错误：Hysteria2 下载文件为空或过小！${NC}"
    echo -e "${YELLOW}请手动下载：$DOWNLOAD_URL 或 $BACKUP_URL${NC}"
    exit 1
fi

chmod +x /usr/local/bin/hysteria

# 检查 Hysteria2 是否可执行
if ! /usr/local/bin/hysteria version &> /dev/null; then
    echo -e "${RED}错误：Hysteria2 二进制文件不可执行，可能文件损坏！${NC}"
    echo -e "${YELLOW}请手动下载：$DOWNLOAD_URL 或 $BACKUP_URL${NC}"
    exit 1
fi

# 停止现有 Hysteria2 服务（如果存在）
systemctl stop hysteria-server &> /dev/null

# 创建 Hysteria2 配置文件
echo -e "${YELLOW}正在创建 Hysteria2 配置文件...${NC}"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
listen: :$HY2_PORT

auth:
  type: password
  password: $HY2_PASSWORD

tls:
  cert: $CONFIG_DIR/server.crt
  key: $CONFIG_DIR/server.key

fastOpen: true
masquerade:
  type: proxy
  proxy:
    url: https://www.example.com
    rewriteHost: true
EOF

# 生成自签名证书
echo -e "${YELLOW}正在生成自签名 TLS 证书...${NC}"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$CONFIG_DIR/server.key" \
    -out "$CONFIG_DIR/server.crt" \
    -subj "/CN=Hysteria" \
    -days 3650 || {
    echo -e "${RED}错误：证书生成失败！${NC}"
    exit 1
}

# 设置文件权限
chmod 600 "$CONFIG_DIR/server.key" "$CONFIG_DIR/server.crt"
chmod 644 "$CONFIG_FILE"

# 创建系统服务文件
echo -e "${YELLOW}正在配置系统服务...${NC}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c $CONFIG_FILE
Restart=on-failure
NoNewPrivileges=yes
PrivateUsers=no
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启动服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl start hysteria-server

# 检查服务状态
if systemctl is-active --quiet hysteria-server; then
    echo -e "${GREEN}Hysteria2 服务已成功启动！${NC}"
else
    echo -e "${RED}错误：Hysteria2 服务启动失败！${NC}"
    systemctl status hysteria-server
    echo -e "${YELLOW}提示：如果你在 LXC 容器中运行，可能需要检查容器权限或网络配置！${NC}"
    exit 1
fi

# 获取服务器公网 IP
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}警告：无法获取公网 IP，请手动检查！${NC}"
    SERVER_IP="YOUR_SERVER_IP"
fi

# 生成 Hysteria2 节点链接
HY2_LINK="hysteria2://$HY2_PASSWORD@$SERVER_IP:$HY2_PORT/?insecure=1"
echo -e "${YELLOW}节点链接已生成，请妥善保存！${NC}"

# 输出节点信息
echo -e "\n${GREEN}Hysteria2 节点部署完成！${NC}"
echo -e "服务器 IP: ${SERVER_IP}"
echo -e "端口: ${HY2_PORT}"
echo -e "密码: ${HY2_PASSWORD}"
echo -e "节点链接: ${HY2_LINK}\n"
echo -e "${YELLOW}请保存节点链接以便客户端使用！${NC}"

# 提示防火墙设置
echo -e "${YELLOW}提示：请确保防火墙允许端口 $HY2_PORT 的 UDP 流量 (如使用 ufw：ufw allow $HY2_PORT/udp)${NC}"
echo -e "${YELLOW}如果在云服务器上，请检查安全组是否允许 UDP 端口 $HY2_PORT${NC}"

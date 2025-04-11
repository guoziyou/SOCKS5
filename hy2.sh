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

# 检查端口是否被占用
if netstat -tuln | grep ":$HY2_PORT" > /dev/null; then
    echo -e "${RED}错误：端口 $HY2_PORT 已被占用，请选择其他端口！${NC}"
    exit 1
fi

# 更新系统并安装依赖
echo -e "${YELLOW}正在更新系统并安装依赖...${NC}"
apt-get update -y
apt-get install -y curl openssl libc6 net-tools ufw iptables || {
    echo -e "${RED}错误：依赖安装失败，请检查网络或包源！${NC}"
    exit 1
}

# 配置 LXC 环境（如果适用）
echo -e "${YELLOW}正在检查 LXC 环境...${NC}"
if [ -f "/run/systemd/system/service.d/zzz-lxc-service.conf" ]; then
    echo -e "${YELLOW}检测到 LXC 容器，尝试优化网络配置...${NC}"
    sysctl -w net.ipv4.ip_unprivileged_port_start=0 > /dev/null
    modprobe udp_tunnel 2> /dev/null || echo -e "${YELLOW}警告：无法加载 udp_tunnel 模块，可能需要宿主机运行：lxc config set <容器名称> linux.kernel_modules udp_tunnel${NC}"
fi

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

# 创建 Hysteria2 配置文件（强制绑定 IPv4）
echo -e "${YELLOW}正在创建 Hysteria2 配置文件...${NC}"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
listen: 0.0.0.0:$HY2_PORT

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
    exit 1
fi

# 验证端口监听（确保绑定 IPv4）
echo -e "${YELLOW}正在验证端口监听...${NC}"
if netstat -uln | grep "0.0.0.0:$HY2_PORT" > /dev/null; then
    echo -e "${GREEN}端口 $HY2_PORT 已正确绑定 IPv4！${NC}"
else
    echo -e "${RED}错误：端口 $HY2_PORT 未绑定 IPv4，仅检测到 IPv6 或无监听！${NC}"
    netstat -uln | grep $HY2_PORT || echo "无监听记录"
    echo -e "${YELLOW}可能原因：LXC 限制或网络配置错误。请检查 LXC 配置或尝试更换端口（如 443）。${NC}"
    exit 1
fi

# 配置防火墙
echo -e "${YELLOW}正在配置防火墙...${NC}"
if command -v ufw > /dev/null; then
    ufw allow $HY2_PORT/udp
    ufw reload
    echo -e "${GREEN}已通过 ufw 开放 UDP 端口 $HY2_PORT！${NC}"
    ufw status | grep $HY2_PORT
else
    if ! command -v iptables > /dev/null; then
        echo -e "${YELLOW}警告：未找到 iptables，尝试安装...${NC}"
        apt-get install -y iptables
    fi
    iptables -A INPUT -p udp --dport $HY2_PORT -j ACCEPT
    echo -e "${GREEN}已通过 iptables 开放 UDP 端口 $HY2_PORT！${NC}"
    iptables -L -n -v | grep $HY2_PORT
fi

# 测试 UDP 连通性
echo -e "${YELLOW}正在测试 UDP 端口 $HY2_PORT 的连通性...${NC}"
timeout 5 nc -u -l $HY2_PORT > /dev/null 2>&1 &
sleep 1
if netstat -uln | grep ":$HY2_PORT" > /dev/null; then
    echo -e "${GREEN}UDP 端口 $HY2_PORT 可本地监听！${NC}"
    echo -e "${YELLOW}请从客户端运行以下命令测试连通性：${NC}"
    echo -e "  echo \"test\" | nc -u $SERVER_IP $HY2_PORT"
else
    echo -e "${RED}错误：无法监听 UDP 端口 $HY2_PORT！${NC}"
    echo -e "${YELLOW}可能原因：LXC 限制或防火墙未正确配置。${NC}"
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

# 提示注意事项
echo -e "${YELLOW}注意事项：${NC}"
echo -e "1. 如果使用云服务器，请确保安全组允许 UDP 端口 $HY2_PORT 的入站流量。"
echo -e "2. 如果节点仍不通，请从客户端运行以下命令测试 UDP 连通性："
echo -e "   nc -zv -u $SERVER_IP $HY2_PORT"
echo -e "   echo \"test\" | nc -u $SERVER_IP $HY2_PORT"
echo -e "3. 检查客户端配置，确保使用正确的 IP、端口、密码，并设置 insecure=1。"
if [ -f "/run/systemd/system/service.d/zzz-lxc-service.conf" ]; then
    echo -e "4. 检测到 LXC 容器，如果 UDP 仍不通，可能需宿主机运行："
    echo -e "   lxc config set <容器名称> linux.kernel_modules udp_tunnel"
fi

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
SS_METHOD="chacha20-ietf-poly1305"
CONFIG_FILE="/etc/shadowsocks-libev/config.json"
SERVICE_FILE="/etc/systemd/system/shadowsocks-libev.service"

# 生成随机密码
SS_PASSWORD=$(openssl rand -base64 12)
echo -e "${YELLOW}已生成随机密码：$SS_PASSWORD${NC}"

# 提示用户输入端口
while true; do
    read -p "请输入 Shadowsocks 端口（1024-65535，推荐 15818）：" SS_PORT
    SS_PORT=${SS_PORT:-15818} # 默认端口为 15818
    if [[ "$SS_PORT" =~ ^[0-9]+$ ]] && [ "$SS_PORT" -ge 1024 ] && [ "$SS_PORT" -le 65535 ]; then
        echo -e "${GREEN}已设置端口：$SS_PORT${NC}"
        break
    else
        echo -e "${RED}错误：端口必须是 1024 到 65535 之间的数字！${NC}"
    fi
done

# 更新系统并安装依赖
echo -e "${YELLOW}正在更新系统并安装依赖...${NC}"
apt-get update -y
apt-get install -y shadowsocks-libev simple-obfs curl

# 检查Shadowsocks是否安装成功
if ! command -v ss-server &> /dev/null; then
    echo -e "${RED}错误：Shadowsocks-libev 安装失败！${NC}"
    exit 1
fi

# 停止现有Shadowsocks服务（如果存在）
systemctl stop shadowsocks-libev &> /dev/null

# 创建Shadowsocks配置文件
echo -e "${YELLOW}正在创建Shadowsocks配置文件...${NC}"
mkdir -p /etc/shadowsocks-libev
cat > $CONFIG_FILE <<EOF
{
    "server":"0.0.0.0",
    "server_port":$SS_PORT,
    "password":"$SS_PASSWORD",
    "timeout":300,
    "method":"$SS_METHOD",
    "fast_open":true,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp"
}
EOF

# 设置文件权限
chmod 600 $CONFIG_FILE

# 创建系统服务文件
echo -e "${YELLOW}正在配置系统服务...${NC}"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Shadowsocks-libev Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd并启动服务
systemctl daemon-reload
systemctl enable shadowsocks-libev
systemctl start shadowsocks-libev

# 检查服务状态
if systemctl is-active --quiet shadowsocks-libev; then
    echo -e "${GREEN}Shadowsocks服务已成功启动！${NC}"
else
    echo -e "${RED}错误：Shadowsocks服务启动失败！${NC}"
    systemctl status shadowsocks-libev
    exit 1
fi

# 获取服务器公网IP
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}警告：无法获取公网IP，请手动检查！${NC}"
    SERVER_IP="YOUR_SERVER_IP"
fi

# 生成Shadowsocks节点链接
SS_LINK=$(echo -n "$SS_METHOD:$SS_PASSWORD@$SERVER_IP:$SS_PORT" | base64 -w 0)
SS_URI="ss://$SS_LINK"

# 输出节点信息
echo -e "\n${GREEN}Shadowsocks节点部署完成！${NC}"
echo -e "服务器IP: ${SERVER_IP}"
echo -e "端口: ${SS_PORT}"
echo -e "密码: ${SS_PASSWORD}"
echo -e "加密方式: ${SS_METHOD}"
echo -e "节点链接: ${SS_URI}\n"
echo -e "${YELLOW}请保存节点链接以便客户端使用！${NC}"

# 提示防火墙设置
echo -e "${YELLOW}提示：请确保防火墙允许端口 $SS_PORT (如使用 ufw：ufw allow $SS_PORT)${NC}"

#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 必须以root运行
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：请以root用户运行此脚本！${NC}"
    exit 1
fi

# 手动输入端口
read -p "$(echo -e ${YELLOW}请输入要使用的端口: ${NC})" HY_PORT
if [[ -z "$HY_PORT" ]]; then
    echo -e "${RED}端口不能为空！${NC}"
    exit 1
fi

# 自动生成强随机密码
HY_PASSWORD=$(openssl rand -hex 12)

# 安装依赖
echo -e "${YELLOW}正在安装依赖...${NC}"
apt update -y
apt install -y curl wget unzip tar

# 下载最新hysteria核心
echo -e "${YELLOW}正在下载 Hysteria2 核心...${NC}"
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    ARCH="arm64"
else
    echo -e "${RED}暂不支持的架构：$ARCH${NC}"
    exit 1
fi

mkdir -p /usr/local/hysteria
cd /usr/local/hysteria

HY_LATEST=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep browser_download_url | grep linux-$ARCH | grep -v .sig | cut -d '"' -f 4)
wget -O hysteria.tar.gz "$HY_LATEST"
tar -xzf hysteria.tar.gz
chmod +x hysteria
rm -f hysteria.tar.gz

# 创建配置文件
mkdir -p /etc/hysteria
cat > /etc/hysteria/config.yaml <<EOF
listen: :$HY_PORT
protocol: hy2
tls:
  cert: /etc/hysteria/fullchain.crt
  key: /etc/hysteria/private.key
auth:
  type: password
  password: $HY_PASSWORD
masquerade:
  type: proxy
  url: https://www.bing.com
  rewriteHost: true
EOF

# 生成 TLS 证书（自签名）
echo -e "${YELLOW}正在生成自签名 TLS 证书...${NC}"
openssl req -newkey rsa:2048 -nodes -keyout /etc/hysteria/private.key \
    -x509 -days 3650 -out /etc/hysteria/fullchain.crt \
    -subj "/C=CN/ST=Hysteria/L=Server/O=SelfSigned/CN=$(hostname)"

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/hysteria/hysteria server -c /etc/hysteria/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# 获取服务器公网 IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ip.sb)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR.SERVER.IP"
    echo -e "${YELLOW}警告：未能自动获取公网IP，请手动替换节点链接中的 IP。${NC}"
fi

# 生成 hy2 节点链接
HY_URI="hy2://$HY_PASSWORD@$SERVER_IP:$HY_PORT?insecure=1&obfs=bing.com"

# 输出信息
echo -e "\n${GREEN}Hysteria2 节点部署完成！${NC}"
echo -e "服务器IP: ${SERVER_IP}"
echo -e "端口: ${HY_PORT}"
echo -e "密码: ${HY_PASSWORD}"
echo -e "节点链接:\n${YELLOW}$HY_URI${NC}\n"
echo -e "${YELLOW}提示：建议使用自签名证书时，在客户端设置 insecure=true${NC}"
echo -e "${YELLOW}防火墙提示：请放行端口 $HY_PORT${NC}"

#!/bin/bash

# 一些颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：请以 root 用户运行此脚本！${NC}"
    exit 1
fi

# 用户输入端口
read -p "请输入 Hy2 节点端口: " PORT
if [[ -z "$PORT" ]]; then
    echo -e "${RED}端口不能为空，退出。${NC}"
    exit 1
fi

# 自动生成密码
PASSWORD=$(openssl rand -hex 8)

# 安装依赖
echo -e "${YELLOW}安装依赖...${NC}"
apt update -y && apt install -y curl wget tar

# 下载 hysteria
echo -e "${YELLOW}正在下载 Hysteria2...${NC}"
mkdir -p /usr/local/hysteria
cd /usr/local/hysteria
curl -L -o hysteria.tar.gz https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64.tar.gz
tar -xzvf hysteria.tar.gz
chmod +x hysteria
ln -sf /usr/local/hysteria/hysteria /usr/bin/hysteria

# 生成自签 TLS 证书
echo -e "${YELLOW}生成自签 TLS 证书...${NC}"
mkdir -p /etc/hysteria
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -keyout /etc/hysteria/key.pem -out /etc/hysteria/cert.pem \
  -subj "/CN=bing.com"

# 生成配置文件
cat > /etc/hysteria/config.yaml <<EOF
listen: :$PORT
tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem
auth:
  type: password
  password: $PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/hysteria/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
LimitNOFILE=40960

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# 检查运行状态
if systemctl is-active --quiet hysteria; then
    echo -e "${GREEN}✅ Hysteria2 服务已启动成功！${NC}"
else
    echo -e "${RED}❌ Hysteria2 启动失败，请检查配置。${NC}"
    journalctl -u hysteria --no-pager
    exit 1
fi

# 获取公网IP
SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")

# 输出连接信息
echo -e "\n${GREEN}🎉 Hy2 节点部署完成！${NC}"
echo -e "服务器IP: ${SERVER_IP}"
echo -e "端口: $PORT"
echo -e "密码: $PASSWORD"
echo -e "节点链接: hy2://$PASSWORD@$SERVER_IP:$PORT?insecure=1&obfs=bing.com"
echo -e "${YELLOW}提示：请在客户端设置 insecure=true 以跳过自签 TLS 校验。${NC}"

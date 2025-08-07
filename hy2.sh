#!/bin/bash

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 确保是root权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行本脚本。${NC}"
  exit 1
fi

# 检测系统类型
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_NAME=$NAME
  else
    echo -e "${RED}无法检测操作系统类型。${NC}"
    exit 1
  fi
}

# 安装依赖
install_dependencies() {
  echo -e "${YELLOW}正在安装依赖...${NC}"
  case "$OS_ID" in
    debian|ubuntu)
      apt update && apt install -y curl openssl iproute2 net-tools
      ;;
    centos|rocky|almalinux|rhel)
      (command -v dnf && dnf install -y curl openssl iproute net-tools) || \
      (yum install -y curl openssl iproute net-tools)
      ;;
    alpine)
      apk update && apk add curl openssl iproute2 busybox-extras
      ;;
    *)
      echo -e "${RED}不支持的操作系统：$OS_NAME${NC}"
      exit 1
      ;;
  esac
}

# 下载 hysteria2
install_hysteria2() {
  echo -e "${YELLOW}正在下载 Hysteria2...${NC}"
  VERSION="2.6.1"
  URL="https://github.com/apernet/hysteria/releases/download/app/v${VERSION}/hysteria-linux-amd64"

  curl -L -o /usr/local/bin/hysteria "$URL" || {
    echo -e "${RED}下载失败，请检查网络连接。${NC}"
    exit 1
  }

  chmod +x /usr/local/bin/hysteria
}

# 生成证书
generate_cert() {
  echo -e "${YELLOW}正在生成自签证书...${NC}"
  mkdir -p /etc/hysteria

  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=Hysteria2" \
    -days 3650 || {
    echo -e "${RED}生成证书失败，请检查 openssl 安装情况。${NC}"
    exit 1
  }
}

# 生成配置
generate_config() {
  PASSWORD=$(openssl rand -base64 12)
  read -p "请输入 Hysteria2 端口（1024-65535，默认443）：" PORT
  PORT=${PORT:-443}

  cat > /etc/hysteria/config.yaml <<EOF
listen: 0.0.0.0:$PORT

auth:
  type: password
  password: $PASSWORD

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

fastOpen: true
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

  echo "$PORT $PASSWORD" > /etc/hysteria/install.info
}

# 开放端口（iptables 简单处理）
open_firewall_port() {
  PORT=$(cut -d' ' -f1 /etc/hysteria/install.info)
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  echo -e "${GREEN}已通过 iptables 开放 UDP 端口 $PORT${NC}"
}

# 配置服务（支持 Alpine 和 systemd 系统）
setup_service() {
  echo -e "${YELLOW}正在配置服务启动项...${NC}"
  if command -v rc-service >/dev/null 2>&1; then
    # Alpine OpenRC
    cat > /etc/init.d/hysteria <<EOF
#!/sbin/openrc-run
command=/usr/local/bin/hysteria
command_args="server -c /etc/hysteria/config.yaml"
pidfile=/run/hysteria.pid
command_background=true
EOF
    chmod +x /etc/init.d/hysteria
    rc-update add hysteria default
    rc-service hysteria start
  else
    # Systemd
    cat > /etc/systemd/system/hysteria.service <<EOF
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
    systemctl enable --now hysteria
  fi
}

# 显示连接信息
show_result() {
  PASSWORD=$(cut -d' ' -f2 /etc/hysteria/install.info)
  PORT=$(cut -d' ' -f1 /etc/hysteria/install.info)
  IP=$(curl -s https://api64.ipify.org || echo "YOUR_SERVER_IP")
  LINK="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1"

  echo -e "\n${GREEN}✅ Hysteria2 安装完成！${NC}"
  echo -e "服务器地址: ${IP}"
  echo -e "端口: ${PORT}"
  echo -e "密码: ${PASSWORD}"
  echo -e "节点链接:\n${YELLOW}$LINK${NC}"
}

# ===== 脚本执行入口 =====
detect_os
install_dependencies
install_hysteria2
generate_cert
generate_config
open_firewall_port
setup_service
show_result

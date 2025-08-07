#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG_DIR="/etc/hysteria"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/hysteria.service"
SERVICE_FILE_OPENRC="/etc/init.d/hysteria"
BIN_PATH="/usr/local/bin/hysteria"
INFO_FILE="$CONFIG_DIR/install.info"

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行本脚本！${NC}"
  exit 1
fi

# 检测系统
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

# 卸载函数
uninstall_hysteria() {
  echo -e "${YELLOW}正在卸载 Hysteria2...${NC}"
  if [ -f "$INFO_FILE" ]; then
    PORT=$(cut -d' ' -f1 "$INFO_FILE")
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
  fi

  # 停止并删除服务
  if [ -f "$SERVICE_FILE_SYSTEMD" ]; then
    systemctl stop hysteria
    systemctl disable hysteria
    rm -f "$SERVICE_FILE_SYSTEMD"
    systemctl daemon-reload
  elif [ -f "$SERVICE_FILE_OPENRC" ]; then
    rc-service hysteria stop
    rc-update del hysteria default
    rm -f "$SERVICE_FILE_OPENRC"
  fi

  # 删除文件
  rm -rf "$CONFIG_DIR"
  rm -f "$BIN_PATH"

  echo -e "${GREEN}Hysteria2 已卸载完成！${NC}"
  exit 0
}

# 如果传入参数为 uninstall，则执行卸载
[ "$1" = "uninstall" ] && detect_os && uninstall_hysteria

# 安装依赖
install_dependencies() {
  echo -e "${YELLOW}安装依赖中...${NC}"
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

# 下载二进制
install_hysteria2() {
  echo -e "${YELLOW}正在下载 Hysteria2...${NC}"
  VERSION="2.6.1"
  URL="https://github.com/apernet/hysteria/releases/download/app/v${VERSION}/hysteria-linux-amd64"
  curl -L -o "$BIN_PATH" "$URL" || {
    echo -e "${RED}下载失败！${NC}"
    exit 1
  }
  chmod +x "$BIN_PATH"
}

# 生成证书
generate_cert() {
  echo -e "${YELLOW}生成自签证书...${NC}"
  mkdir -p "$CONFIG_DIR"
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$CONFIG_DIR/server.key" \
    -out "$CONFIG_DIR/server.crt" \
    -subj "/CN=Hysteria2" \
    -days 3650 || {
    echo -e "${RED}证书生成失败！${NC}"
    exit 1
  }
}

# 配置文件
generate_config() {
  PASSWORD=$(openssl rand -base64 12)
  read -p "请输入 Hysteria2 端口（1024-65535，默认 443）：" PORT
  PORT=${PORT:-443}

  cat > "$CONFIG_DIR/config.yaml" <<EOF
listen: 0.0.0.0:$PORT

auth:
  type: password
  password: $PASSWORD

tls:
  cert: $CONFIG_DIR/server.crt
  key: $CONFIG_DIR/server.key

fastOpen: true
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

  echo "$PORT $PASSWORD" > "$INFO_FILE"
}

# 防火墙
open_port() {
  PORT=$(cut -d' ' -f1 "$INFO_FILE")
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
}

# 服务
setup_service() {
  echo -e "${YELLOW}配置服务启动项...${NC}"
  if command -v rc-service >/dev/null 2>&1; then
    # OpenRC
    cat > "$SERVICE_FILE_OPENRC" <<EOF
#!/sbin/openrc-run
command=$BIN_PATH
command_args="server -c $CONFIG_DIR/config.yaml"
pidfile=/run/hysteria.pid
command_background=true
EOF
    chmod +x "$SERVICE_FILE_OPENRC"
    rc-update add hysteria default
    rc-service hysteria restart
  else
    # systemd
    cat > "$SERVICE_FILE_SYSTEMD" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$BIN_PATH server -c $CONFIG_DIR/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now hysteria
  fi
}

# 显示结果
show_result() {
  PASSWORD=$(cut -d' ' -f2 "$INFO_FILE")
  PORT=$(cut -d' ' -f1 "$INFO_FILE")
  IP=$(curl -s https://api64.ipify.org || echo "YOUR_SERVER_IP")
  LINK="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1"

  echo -e "\n${GREEN}✅ Hysteria2 安装完成！${NC}"
  echo -e "服务器地址: ${IP}"
  echo -e "端口: ${PORT}"
  echo -e "密码: ${PASSWORD}"
  echo -e "节点链接:\n${YELLOW}$LINK${NC}"
}

# 主流程
detect_os
install_dependencies
install_hysteria2
generate_cert
generate_config
open_port
setup_service
show_result

#!/bin/bash

# ====== 颜色输出 ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ====== 路径配置 ======
CONFIG_DIR="/etc/hysteria"
BIN_PATH="/usr/local/bin/hysteria"
INFO_FILE="$CONFIG_DIR/install.info"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/hysteria.service"
SERVICE_FILE_OPENRC="/etc/init.d/hysteria"

# ====== 检查 root ======
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行本脚本！${NC}"
  exit 1
fi

# ====== 系统识别 ======
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_NAME=$NAME
  else
    echo -e "${RED}无法识别操作系统。${NC}"
    exit 1
  fi
}

# ====== 安装依赖 ======
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

# ====== 下载二进制 ======
install_hysteria2() {
  echo -e "${YELLOW}下载 Hysteria2...${NC}"
  VERSION="2.6.1"
  curl -L -o "$BIN_PATH" "https://github.com/apernet/hysteria/releases/download/app/v${VERSION}/hysteria-linux-amd64"
  chmod +x "$BIN_PATH"
}

# ====== 生成证书 ======
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

# ====== 生成配置文件 ======
generate_config() {
  PASSWORD=$(openssl rand -base64 12)
  read -p "请输入 Hysteria2 端口（默认 443）：" PORT
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

# ====== 防火墙开放端口 ======
open_port() {
  PORT=$(cut -d' ' -f1 "$INFO_FILE")
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
}

# ====== 设置服务 ======
setup_service() {
  echo -e "${YELLOW}设置服务启动项...${NC}"
  if command -v rc-service >/dev/null 2>&1; then
    # Alpine OpenRC
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
    # Systemd
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

# ====== 显示链接信息 ======
show_result() {
  PASSWORD=$(cut -d' ' -f2 "$INFO_FILE")
  PORT=$(cut -d' ' -f1 "$INFO_FILE")
  IP=$(curl -s https://api64.ipify.org || echo "YOUR_SERVER_IP")
  LINK="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1"

  echo -e "\n${GREEN}✅ 安装完成！${NC}"
  echo -e "IP地址: $IP"
  echo -e "端口: $PORT"
  echo -e "密码: $PASSWORD"
  echo -e "链接: ${YELLOW}$LINK${NC}"
}

# ====== 卸载函数 ======
uninstall_hysteria() {
  echo -e "${YELLOW}正在卸载 Hysteria2...${NC}"
  if [ -f "$INFO_FILE" ]; then
    PORT=$(cut -d' ' -f1 "$INFO_FILE")
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
  fi

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

  rm -rf "$CONFIG_DIR"
  rm -f "$BIN_PATH"

  echo -e "${GREEN}✅ Hysteria2 已成功卸载。${NC}"
}

# ====== 主菜单 ======
main_menu() {
  echo -e "${GREEN}欢迎使用 Hysteria2 管理脚本${NC}"
  echo -e "请选择操作："
  echo "1. 安装 Hysteria2"
  echo "2. 卸载 Hysteria2"
  echo "3. 退出"
  read -p "请输入选项 [1-3]: " choice

  case $choice in
    1)
      detect_os
      install_dependencies
      install_hysteria2
      generate_cert
      generate_config
      open_port
      setup_service
      show_result
      ;;
    2)
      detect_os
      uninstall_hysteria
      ;;
    3)
      echo "已退出。"
      exit 0
      ;;
    *)
      echo -e "${RED}无效选项，请输入 1-3。${NC}"
      ;;
  esac
}

# ====== 执行入口 ======
main_menu

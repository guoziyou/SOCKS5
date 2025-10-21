#!/bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
   echo "错误：此脚本必须以 root 权限运行。"
   exit 1
fi

# 定义保存配置信息的文件
INFO_FILE="/root/danted_info.txt"

# --- URL 编码功能 ---
# 用于处理密码中的特殊字符, 如 + / =
url_encode() {
    local string="$1"
    local encoded=""
    local char
    for (( i=0; i<${#string}; i++ )); do
        char=${string:$i:1}
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    echo "$encoded"
}

# --- 显示 SOCKS5 节点链接 功能 ---
show_links() {
    echo "--- 正在生成 SOCKS5 节点链接 ---"

    if [ ! -f "$INFO_FILE" ]; then
        echo "错误：未找到配置文件 $INFO_FILE。"
        echo "请先安装 SOCKS5 代理 (选项 1)。"
        echo "-------------------------------------"
        return
    fi

    # 1. 加载配置
    source $INFO_FILE
    if [ -z "$PORT" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo "错误：配置文件 $INFO_FILE 不完整。"
        echo "请尝试重新安装 SOCKS5 代理。"
        echo "-------------------------------------"
        return
    fi

    # 2. 获取 IP
    local IPV4
    local IPV6
    IPV4=$(curl -s https://ipv4.icanhazip.com)
    IPV6=$(curl -s https://ipv6.icanhazip.com)

    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        echo "错误：无法获取服务器的公共 IP 地址。"
        echo "-------------------------------------"
        return
    fi

    # 3. URL 编码密码
    local ENCODED_PASSWORD
    ENCODED_PASSWORD=$(url_encode "$PASSWORD")

    echo "您可以复制以下链接并导入到您的代理客户端中："
    echo "-------------------------------------"

    if [ -n "$IPV4" ]; then
        echo "🔗 IPv4 链接 (推荐):"
        echo "socks5://${USERNAME}:${ENCODED_PASSWORD}@${IPV4}:${PORT}"
        echo ""
    fi
    
    if [ -n "$IPV6" ]; then
        echo "🔗 IPv6 链接 (如果您的本地网络支持):"
        # 注意: IPv6 地址在 URL 中必须用 [] 括起来
        echo "socks5://${USERNAME}:${ENCODED_PASSWORD}@[${IPV6}]:${PORT}"
        echo ""
    fi
    
    echo "--- 原始连接信息 ---"
    echo "  服务器 (IP): $IPV4 (或 $IPV6)"
    echo "  端口 (Port): $PORT"
    echo "  用户名 (User): $USERNAME"
    echo "  密码 (Pass): $PASSWORD"
    echo "-------------------------------------"
}


# --- 安装 SOCKS5 功能 ---
install_socks5() {
    echo "--- 正在安装 SOCKS5 代理 ---"

    # 1. 生成随机凭据和端口
    echo "正在生成随机用户名和密码..."
    USERNAME="user$(openssl rand -hex 4)"
    PASSWORD=$(openssl rand -base64 12)

    echo "正在查找 40000 以上未被占用的随机端口..."
    while true; do
        PORT=$((RANDOM % 25535 + 40000))
        if ! ss -lntu | grep -q ":${PORT}\b"; then
            echo "找到可用端口: $PORT"
            break
        fi
    done

    # 2. 安装 dante-server 及依赖
    echo "正在更新软件包列表并安装 dante-server, curl, openssl..."
    apt update
    apt install dante-server curl openssl -y

    # 3. 检查网卡名
    IFACE=$(ip -o -6 addr show scope global | awk '{print $2}' | head -n1)
    IFACE=${IFACE:-eth0}
    echo "将使用 $IFACE 作为外部接口..."

    # 4. 写入配置文件
    echo "正在写入配置文件 /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $PORT
internal: :: port = $PORT
external: $IFACE
method: username
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
client pass {
    from: ::/0 to: ::/0
    log: connect disconnect error
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
    method: username
}
pass {
    from: ::/0 to: ::/0
    protocol: tcp udp
    log: connect disconnect error
    method: username
}
EOF

    # 5. 添加 SOCKS5 用户
    echo "正在创建用户 $USERNAME..."
    useradd --no-create-home --shell /usr/sbin/nologin $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd

    # 6. 启动 danted 服务
    echo "正在启动并启用 danted 服务..."
    systemctl enable danted
    systemctl restart danted

    # 7. 开放防火墙端口
    echo "正在开放端口 $PORT (IPv4 & IPv6)..."
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    ip6tables -I INPUT -p tcp --dport $PORT -j ACCEPT

    # 8. 保存信息以备卸载 (包含密码)
    echo "正在保存配置信息到 $INFO_FILE..."
    echo "PORT=$PORT" > $INFO_FILE
    echo "USERNAME=$USERNAME" >> $INFO_FILE
    echo "PASSWORD=$PASSWORD" >> $INFO_FILE # 新增
    chmod 600 $INFO_FILE

    # 9. 显示信息 (自动调用 show_links)
    echo ""
    echo "✅ SOCKS5 代理安装完成"
    show_links # 自动显示节点链接
}

# --- 卸载 SOCKS5 功能 ---
uninstall_socks5() {
    echo "--- 正在卸载 SOCKS5 代理 ---"

    # 1. 停止和禁用服务
    echo "正在停止和禁用 danted 服务..."
    systemctl stop danted
    systemctl disable danted

    # 2. 读取保存的配置
    if [ -f "$INFO_FILE" ]; then
        source $INFO_FILE
        echo "已从 $INFO_FILE 加载配置信息。"
    else
        echo "警告：未找到 $INFO_FILE 文件。"
        echo "无法自动删除防火墙规则和用户，请手动操作。"
        PORT=""
        USERNAME=""
    fi

    # 3. 删除防火墙规则
    if [ -n "$PORT" ]; then
        echo "正在删除端口 $PORT 的防火墙规则..."
        iptables -D INPUT -p tcp --dport $PORT -j ACCEPT
        ip6tables -D INPUT -p tcp --dport $PORT -j ACCEPT
    fi

    # 4. 卸载软件包
    echo "正在彻底卸载 dante-server..."
    apt remove --purge dante-server -y
    apt autoremove -y

    # 5. 删除用户
    if [ -n "$USERNAME" ]; then
        echo "正在删除用户 $USERNAME..."
        userdel $USERNAME
    fi

    # 6. 清理残留文件
    echo "正在清理残留文件..."
    rm -f /var/log/danted.log
    rm -f $INFO_FILE

    echo "✅ SOCKS5 卸载完成。"
}

# --- 主菜单 ---
main_menu() {
    clear
    echo "SOCKS5 (Dante) 代理管理脚本"
    echo "=========================="
    echo ""
    echo "请选择一个操作:"
    echo "  1. 安装 SOCKS5 代理"
    echo "  2. 卸载 SOCKS5 代理"
    echo "  3. 显示 SOCKS5 节点链接"
    echo "  4. 退出"
    echo ""
    read -p "请输入选项 [1-4]: " choice

    case $choice in
        1)
            install_socks5
            read -p "按 Enter 键返回菜单..."
            main_menu
            ;;
        2)
            uninstall_socks5
            read -p "按 Enter 键返回菜单..."
            main_menu
            ;;
        3)
            show_links
            read -p "按 Enter 键返回菜单..."
            main_menu
            ;;
        4)
            echo "退出。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            sleep 2
            main_menu
            ;;
    esac
}

# 运行主菜单
main_menu

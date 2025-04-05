#!/bin/bash

# 设置用户名和密码
USERNAME="socks6user"
PASSWORD="pass6word"

# 安装 dante-server
apt update
apt install dante-server -y

# 检查网卡名（取第一个非 lo 网卡）
IFACE=$(ip -o -6 addr show scope global | awk '{print $2}' | head -n1)
IFACE=${IFACE:-eth0}

# 写入配置文件
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = 1080
internal: :: port = 1080
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

# 添加 socks5 用户
useradd --no-create-home --shell /usr/sbin/nologin $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# 启动 danted 服务
systemctl enable danted
systemctl restart danted

# 开放端口（IPv4 & IPv6）
iptables -I INPUT -p tcp --dport 1080 -j ACCEPT
ip6tables -I INPUT -p tcp --dport 1080 -j ACCEPT

# 显示信息
echo "✅ SOCKS5 代理安装完成"
echo "📌 IPv4: $(curl -s https://ipv4.icanhazip.com)"
echo "📌 IPv6: $(curl -s https://ipv6.icanhazip.com)"
echo "📌 端口: 1080"
echo "👤 用户名: $USERNAME"
echo "🔑 密码: $PASSWORD"

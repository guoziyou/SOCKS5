#!/bin/bash

echo "🧹 开始卸载部署的项目..."

# 停止并卸载 x-ui
if [ -f "/usr/local/x-ui/x-ui" ]; then
  echo "🚫 卸载 x-ui..."
  /usr/local/x-ui/x-ui uninstall
  rm -rf /usr/local/x-ui /etc/systemd/system/x-ui.service
fi

# 停止并卸载 sing-box
echo "🚫 卸载 sing-box..."
pkill -f sing-box
rm -rf /etc/s-box /etc/systemd/system/sing-box.service

# 停止并卸载 xray
echo "🚫 卸载 xray..."
pkill -f xray
rm -rf /root/bin/xray* /root/bin/config.json

# 停止 wireguard-go / warp-up
echo "🚫 卸载 wireguard-go / WARP-UP..."
pkill -f wireguard-go
pkill -f WARP-UP.sh
rm -rf /usr/bin/wireguard-go /root/WARP-UP.sh

# 卸载 nginx、php、mariadb
echo "🚫 卸载 nginx php mariadb..."
apt-get remove --purge -y nginx php* mariadb* mysql* 
apt-get autoremove -y
apt-get clean

# 删除相关目录
echo "🗑 清理网站和配置文件..."
rm -rf /etc/nginx /etc/php /etc/mysql /var/www /usr/share/nginx/html
rm -rf /var/lib/mysql /var/log/mysql
rm -rf /var/log/nginx /var/log/php*

# 删除 systemd 服务残留
systemctl daemon-reload

echo "✅ 所有部署项目已卸载完成！"

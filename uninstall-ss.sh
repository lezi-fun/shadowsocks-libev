#!/bin/bash

# Shadowsocks-libev 卸载脚本
if [ "$(id -u)" != "0" ]; then
   echo "必须使用 root 用户运行此脚本！" 1>&2
   exit 1
fi

echo -e "\033[33m===== 正在卸载 Shadowsocks-libev =====\033[0m"

# 获取当前配置信息（如果存在）
CONFIG_FILE="/etc/shadowsocks-libev/config.json"
PORT=""
if [ -f "$CONFIG_FILE" ]; then
    PORT=$(jq -r '.server_port' $CONFIG_FILE 2>/dev/null)
fi

# 停止并禁用服务
if systemctl is-active --quiet shadowsocks-libev.service; then
    systemctl stop shadowsocks-libev.service
    systemctl disable shadowsocks-libev.service
elif systemctl is-active --quiet shadowsocks-libev; then
    systemctl stop shadowsocks-libev
    systemctl disable shadowsocks-libev
fi

# 卸载软件包
if grep -Eqi "Ubuntu|Debian" /etc/issue; then
    apt purge -y shadowsocks-libev
    apt autoremove -y
elif grep -Eqi "CentOS|Red Hat" /etc/redhat-release; then
    yum remove -y shadowsocks-libev
fi

# 清理配置文件
rm -f /etc/shadowsocks-libev/config.json
rm -rf /etc/shadowsocks-libev/

# 清理日志文件
rm -f /var/log/shadowsocks-libev.log

# 清理BBR加速（如果安装了）
BBR_SCRIPT="/usr/local/tcp.sh"
if [ -f "$BBR_SCRIPT" ]; then
    rm -f "$BBR_SCRIPT"
fi

# 关闭防火墙端口
if [ -n "$PORT" ]; then
    echo -e "\033[33m关闭防火墙端口: ${PORT}\033[0m"
    if command -v ufw &> /dev/null; then
        ufw delete allow ${PORT}/tcp
        ufw delete allow ${PORT}/udp
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-port=${PORT}/tcp
        firewall-cmd --permanent --remove-port=${PORT}/udp
        firewall-cmd --reload
    fi
fi

echo -e "\n\033[32m===== Shadowsocks-libev 已成功卸载 =====\033[0m"
echo "已移除以下内容："
echo "1. Shadowsocks-libev 软件包"
echo "2. 配置文件 (/etc/shadowsocks-libev/)"
echo "3. 服务配置"
echo "4. 防火墙规则"
echo "5. BBR加速脚本"
echo -e "\n\033[33m注意：此脚本不会卸载BBR内核模块，如需完全卸载BBR，请手动恢复系统内核设置。\033[0m"

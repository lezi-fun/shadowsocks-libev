#!/bin/bash

# 安装 Shadowsocks-libev + BBR 加速 (Ubuntu/Debian/CentOS) with 自定义配置和订阅链接生成
if [ "$(id -u)" != "0" ]; then
   echo "必须使用 root 用户运行此脚本！" 1>&2
   exit 1
fi

# 选择是否启用 BBR 加速
read -p "是否启用 BBR 加速? [Y/n]: " ENABLE_BBR_INPUT
if [ -z "$ENABLE_BBR_INPUT" ] || [[ "$ENABLE_BBR_INPUT" =~ ^[Yy]$ ]]; then
    ENABLE_BBR=true
else
    ENABLE_BBR=false
fi

# 自动检测系统并安装
if grep -Eqi "Ubuntu|Debian" /etc/issue; then
    apt update && apt upgrade -y
    apt install -y curl wget git jq qrencode
    if [ "$ENABLE_BBR" = true ]; then
        bash <(curl -Lso- https://git.io/kernel.sh)
    else
        echo "已跳过 BBR 加速。"
    fi
    
    # 安装 Shadowsocks
    apt install -y shadowsocks-libev
    systemctl stop shadowsocks-libev.service
    
elif grep -Eqi "CentOS|Red Hat" /etc/redhat-release; then
    yum update -y
    yum install -y curl wget git jq qrencode
    if [ "$ENABLE_BBR" = true ]; then
        bash <(curl -Lso- https://git.io/kernel.sh)
    else
        echo "已跳过 BBR 加速。"
    fi
    
    # 安装 Shadowsocks
    yum install -y epel-release
    yum install -y shadowsocks-libev
    systemctl stop shadowsocks-libev
else
    echo "不支持的操作系统！"
    exit 1
fi

# 获取公网 IP
PUBLIC_IP=$(curl -4 icanhazip.com 2>/dev/null || curl -4 ip.sb)

# 用户自定义配置
echo -e "\n\033[33m===== Shadowsocks 配置 =====\033[0m"

# 端口输入验证
while true; do
    read -p "输入端口 [默认：随机20000-30000]: " CUSTOM_PORT
    if [ -z "$CUSTOM_PORT" ]; then
        PORT=$((RANDOM % 10000 + 20000))
        break
    elif [[ ! "$CUSTOM_PORT" =~ ^[0-9]+$ ]] || [ "$CUSTOM_PORT" -lt 1 ] || [ "$CUSTOM_PORT" -gt 65535 ]; then
        echo -e "\033[31m错误：端口必须是1-65535之间的数字！\033[0m"
    else
        PORT=$CUSTOM_PORT
        break
    fi
done

# 密码输入
read -p "输入密码 [默认：随机16位字符]: " CUSTOM_PASS
if [ -z "$CUSTOM_PASS" ]; then
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
else
    PASSWORD=$CUSTOM_PASS
fi

# 加密算法选择菜单
echo -e "\n请选择加密算法："
echo "1) aes-256-gcm (默认)"
echo "2) aes-192-gcm"
echo "3) aes-128-gcm"
echo "4) chacha20-ietf-poly1305"
echo "5) xchacha20-ietf-poly1305"
echo "6) camellia-256-gcm"
echo "7) camellia-192-gcm"
echo "8) camellia-128-gcm"

read -p "输入选项 [1-8] (默认为1): " ALGO_CHOICE

case $ALGO_CHOICE in
    1) METHOD="aes-256-gcm" ;;
    2) METHOD="aes-192-gcm" ;;
    3) METHOD="aes-128-gcm" ;;
    4) METHOD="chacha20-ietf-poly1305" ;;
    5) METHOD="xchacha20-ietf-poly1305" ;;
    6) METHOD="camellia-256-gcm" ;;
    7) METHOD="camellia-192-gcm" ;;
    8) METHOD="camellia-128-gcm" ;;
    *) METHOD="aes-256-gcm" ;;
 esac

# 创建配置文件
cat > /etc/shadowsocks-libev/config.json << EOF
{
    "server":"0.0.0.0",
    "server_port":${PORT},
    "password":"${PASSWORD}",
    "method":"${METHOD}",
    "mode":"tcp_and_udp",
    "fast_open":true
}
EOF

# 重启服务
if grep -Eqi "Ubuntu|Debian" /etc/issue; then
    systemctl restart shadowsocks-libev.service
    systemctl enable shadowsocks-libev.service
elif grep -Eqi "CentOS|Red Hat" /etc/redhat-release; then
    systemctl restart shadowsocks-libev
    systemctl enable shadowsocks-libev
fi

# 防火墙放行
if command -v ufw &> /dev/null; then
    ufw allow ${PORT}/tcp
    ufw allow ${PORT}/udp
    ufw reload
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=${PORT}/tcp
    firewall-cmd --permanent --add-port=${PORT}/udp
    firewall-cmd --reload
fi

# 生成订阅链接
SS_URL="ss://$(echo -n "${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}" | base64 -w 0)"
SUB_LINK="ss://$(echo -n "${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=//g')#Shadowsocks_Server"

# 显示配置信息
echo -e "\n\033[32m===== 安装成功！Shadowsocks 配置 =====\033[0m"
echo "服务器IP: $PUBLIC_IP"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "加密: $METHOD"
echo "协议: TCP + UDP"
echo -e "\n\033[33m===== 订阅链接 =====\033[0m"
echo "原始链接: $SS_URL"
echo "订阅链接: $SUB_LINK"
echo -e "\n\033[33m===== 二维码 (使用客户端扫描) =====\033[0m"
qrencode -t UTF8 "$SS_URL" 2>/dev/null || echo "二维码生成失败，请手动复制链接"
echo "==============================="
echo "客户端下载: https://shadowsocks.org/en/download/clients.html"

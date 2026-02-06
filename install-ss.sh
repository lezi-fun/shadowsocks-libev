#!/bin/bash
set -euo pipefail
IFS=$' \n\t'

# 安装 Shadowsocks-libev + 可选 BBR 优化（Ubuntu/Debian/CentOS）

SUPPORTED_CIPHERS=(
    "aes-256-gcm"
    "aes-192-gcm"
    "aes-128-gcm"
    "chacha20-ietf-poly1305"
    "xchacha20-ietf-poly1305"
    "camellia-256-gcm"
    "camellia-192-gcm"
    "camellia-128-gcm"
)

MANUAL_IP_USED="false"

if [ "$(id -u)" != "0" ]; then
    echo "必须使用 root 用户运行此脚本！" 1>&2
    exit 1
fi

die() {
    echo "错误：$*" 1>&2
    exit 1
}

require_cmd_success() {
    local desc="$1"
    shift
    if ! "$@"; then
        die "${desc} 失败。"
    fi
}

is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    read -r o1 o2 o3 o4 <<< "$ip"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$o" =~ ^[0-9]+$ ]] || return 1
        [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
    done
    return 0
}

get_public_ip() {
    local ip=""
    ip=$(curl -4fsS icanhazip.com 2>/dev/null || true)
    ip=${ip//$'\n'/}
    if is_ipv4 "$ip"; then
        echo "$ip"
        return
    fi
    ip=$(curl -4fsS ip.sb 2>/dev/null || true)
    ip=${ip//$'\n'/}
    if is_ipv4 "$ip"; then
        echo "$ip"
        return
    fi
    echo ""
}

prompt_ipv4() {
    local detected_ip="$1"
    local input_ip=""

    while true; do
        if [ -n "$detected_ip" ] && is_ipv4 "$detected_ip"; then
            read -r -p "输入服务器IP [默认：$detected_ip]: " input_ip
            if [ -z "$input_ip" ]; then
                echo "$detected_ip"
                return
            fi
        else
            read -r -p "自动检测 IP 失败或格式不合法，请输入服务器IP: " input_ip
            MANUAL_IP_USED="true"
        fi

        if is_ipv4 "$input_ip"; then
            [ -n "$detected_ip" ] && [ "$input_ip" != "$detected_ip" ] && MANUAL_IP_USED="true"
            echo "$input_ip"
            return
        fi
        echo "错误：IP 地址格式不合法，请重新输入。"
    done
}

enable_bbr_if_requested() {
    local enable_bbr="$1"
    [ "$enable_bbr" = "true" ] || {
        echo "已跳过 BBR 加速。"
        return
    }

    echo "开始通过系统内核参数启用 BBR（不使用短链接脚本）..."
    if ! modprobe tcp_bbr 2>/dev/null; then
        echo "警告：当前内核可能不支持 tcp_bbr，已跳过 BBR 设置。"
        return
    fi

    printf 'tcp_bbr\n' > /etc/modules-load.d/bbr.conf
    cat > /etc/sysctl.d/99-bbr.conf << 'BBRCONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
BBRCONF
    require_cmd_success "应用 sysctl 参数" sysctl --system
    echo "BBR 参数已写入系统配置。"
}

install_dependencies() {
    if grep -Eqi "Ubuntu|Debian" /etc/issue; then
        export DEBIAN_FRONTEND=noninteractive
        require_cmd_success "更新软件源" apt update -qq
        require_cmd_success "升级系统包" apt upgrade -y -qq
        require_cmd_success "安装依赖" apt install -y -qq curl wget git jq qrencode
        require_cmd_success "安装 shadowsocks-libev" apt install -y -qq shadowsocks-libev
        require_cmd_success "停止 shadowsocks 服务" systemctl stop shadowsocks-libev.service
        OS_FAMILY="debian"
    elif grep -Eqi "CentOS|Red Hat" /etc/redhat-release; then
        require_cmd_success "更新系统包" yum -y -q update
        require_cmd_success "安装依赖" yum -y -q install curl wget git jq qrencode
        require_cmd_success "安装 epel-release" yum -y -q install epel-release
        require_cmd_success "安装 shadowsocks-libev" yum -y -q install shadowsocks-libev
        require_cmd_success "停止 shadowsocks 服务" systemctl stop shadowsocks-libev
        OS_FAMILY="rhel"
    else
        die "不支持的操作系统。"
    fi
}

configure_ss() {
    local port password method choice

    echo -e "\n\033[33m===== Shadowsocks 配置 =====\033[0m"

    while true; do
        read -r -p "输入端口 [默认：随机20000-30000]: " port
        if [ -z "$port" ]; then
            PORT=$((RANDOM % 10000 + 20000))
            break
        elif [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            PORT="$port"
            break
        else
            echo -e "\033[31m错误：端口必须是1-65535之间的数字！\033[0m"
        fi
    done

    read -r -p "输入密码 [默认：随机16位字符]: " password
    if [ -z "$password" ]; then
        PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    else
        PASSWORD="$password"
    fi

    echo -e "\n请选择加密算法："
    echo "1) aes-256-gcm (默认)"
    echo "2) aes-192-gcm"
    echo "3) aes-128-gcm"
    echo "4) chacha20-ietf-poly1305"
    echo "5) xchacha20-ietf-poly1305"
    echo "6) camellia-256-gcm"
    echo "7) camellia-192-gcm"
    echo "8) camellia-128-gcm"
    read -r -p "输入选项 [1-8] (默认为1): " choice

    if [[ "$choice" =~ ^[1-8]$ ]]; then
        method="${SUPPORTED_CIPHERS[$((choice - 1))]}"
    else
        method="aes-256-gcm"
    fi
    METHOD="$method"
}

write_config_and_validate() {
    cat > /etc/shadowsocks-libev/config.json << EOF_CONF
{
    "server":"0.0.0.0",
    "server_port":${PORT},
    "password":"${PASSWORD}",
    "method":"${METHOD}",
    "mode":"tcp_and_udp",
    "fast_open":true
}
EOF_CONF

    [ -s /etc/shadowsocks-libev/config.json ] || die "配置写入失败。"
    if command -v jq >/dev/null 2>&1; then
        require_cmd_success "校验配置文件 JSON" jq -e '.server_port and .password and .method' /etc/shadowsocks-libev/config.json >/dev/null
    fi
}

restart_service() {
    if [ "$OS_FAMILY" = "debian" ]; then
        require_cmd_success "重启 shadowsocks 服务" systemctl restart shadowsocks-libev.service
        require_cmd_success "启用 shadowsocks 开机启动" systemctl enable shadowsocks-libev.service
    else
        require_cmd_success "重启 shadowsocks 服务" systemctl restart shadowsocks-libev
        require_cmd_success "启用 shadowsocks 开机启动" systemctl enable shadowsocks-libev
    fi
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        require_cmd_success "放行 UFW TCP 端口" ufw allow "${PORT}/tcp"
        require_cmd_success "放行 UFW UDP 端口" ufw allow "${PORT}/udp"
        require_cmd_success "重载 UFW" ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1; then
        require_cmd_success "放行 firewalld TCP 端口" firewall-cmd --permanent --add-port="${PORT}/tcp"
        require_cmd_success "放行 firewalld UDP 端口" firewall-cmd --permanent --add-port="${PORT}/udp"
        require_cmd_success "重载 firewalld" firewall-cmd --reload
    fi
}

main() {
    local enable_bbr_input enable_bbr public_ip ss_raw ss_url sub_link

    read -r -p "是否启用 BBR 加速? [Y/n]: " enable_bbr_input
    if [ -z "$enable_bbr_input" ] || [[ "$enable_bbr_input" =~ ^[Yy]$ ]]; then
        enable_bbr="true"
    else
        enable_bbr="false"
    fi

    install_dependencies
    enable_bbr_if_requested "$enable_bbr"

    public_ip=$(get_public_ip)
    PUBLIC_IP=$(prompt_ipv4 "$public_ip")

    configure_ss
    write_config_and_validate
    restart_service
    open_firewall

    ss_raw="${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}"
    ss_url="ss://$(echo -n "$ss_raw" | base64 -w 0)"
    sub_link="ss://$(echo -n "$ss_raw" | base64 -w 0 | tr '+/' '-_' | sed 's/=//g')#Shadowsocks_Server"

    echo -e "\n\033[32m===== 安装成功！Shadowsocks 配置 =====\033[0m"
    [ "$MANUAL_IP_USED" = "true" ] && echo "提示：自动检测失败或未采用检测值，已使用手动输入 IP。"
    echo "服务器IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密: $METHOD"
    echo "协议: TCP + UDP"
    echo -e "\n\033[33m===== 订阅链接 =====\033[0m"
    echo "原始链接: $ss_url"
    echo "订阅链接: $sub_link"
    echo -e "\n\033[33m===== 二维码 (使用客户端扫描) =====\033[0m"
    if command -v qrencode >/dev/null 2>&1; then
        require_cmd_success "生成二维码" qrencode -t UTF8 "$ss_url"
    else
        echo "未检测到 qrencode，跳过二维码生成。"
    fi
    echo "==============================="
    echo "客户端下载: https://github.com/clash-version/clash-download"
    echo "请根据你的系统与当前版本需求，自行选择适配的 Clash 客户端。"
}

main "$@"

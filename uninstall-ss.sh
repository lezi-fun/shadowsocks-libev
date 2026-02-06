#!/bin/bash
set -euo pipefail
IFS=$' \n\t'

# Shadowsocks-libev 卸载脚本

CONFIG_FILE="/etc/shadowsocks-libev/config.json"

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

is_valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

extract_port_from_config() {
    local port=""

    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        return
    fi

    if command -v jq >/dev/null 2>&1; then
        port=$(jq -r '.server_port // empty' "$CONFIG_FILE" 2>/dev/null || true)
    else
        port=$(sed -n 's/.*"server_port"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' "$CONFIG_FILE" | head -n 1)
        if [ -z "$port" ]; then
            port=$(awk -F: '/"server_port"/ {gsub(/[^0-9]/,"",$2); if ($2!="") {print $2; exit}}' "$CONFIG_FILE")
        fi
    fi

    if is_valid_port "$port"; then
        echo "$port"
    else
        echo ""
    fi
}

prompt_port_if_needed() {
    local detected_port="$1"
    local input_port=""

    while true; do
        if [ -n "$detected_port" ]; then
            read -r -p "检测到端口 ${detected_port}，是否使用该端口清理防火墙？[Y/n]: " use_detected
            if [ -z "$use_detected" ] || [[ "$use_detected" =~ ^[Yy]$ ]]; then
                echo "$detected_port"
                return
            fi
        fi

        read -r -p "请输入需要清理的端口: " input_port
        if is_valid_port "$input_port"; then
            echo "$input_port"
            return
        fi
        echo "错误：端口必须是 1-65535 之间的数字！"
    done
}

cleanup_firewall() {
    local port="$1"
    [ -n "$port" ] || return

    echo -e "\033[33m清理防火墙端口: ${port}\033[0m"
    if command -v ufw >/dev/null 2>&1; then
        if ufw delete allow "${port}/tcp"; then
            echo "UFW: 已清理 TCP 规则 ${port}/tcp"
        else
            echo "UFW: 未清理 TCP 规则 ${port}/tcp（可能原本不存在）"
        fi

        if ufw delete allow "${port}/udp"; then
            echo "UFW: 已清理 UDP 规则 ${port}/udp"
        else
            echo "UFW: 未清理 UDP 规则 ${port}/udp（可能原本不存在）"
        fi

        if ufw reload; then
            echo "UFW: 已重载防火墙规则"
        else
            echo "UFW: 重载失败，请手动检查"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --permanent --remove-port="${port}/tcp"; then
            echo "firewalld: 已清理 TCP 规则 ${port}/tcp"
        else
            echo "firewalld: 未清理 TCP 规则 ${port}/tcp（可能原本不存在）"
        fi

        if firewall-cmd --permanent --remove-port="${port}/udp"; then
            echo "firewalld: 已清理 UDP 规则 ${port}/udp"
        else
            echo "firewalld: 未清理 UDP 规则 ${port}/udp（可能原本不存在）"
        fi

        if firewall-cmd --reload; then
            echo "firewalld: 已重载防火墙规则"
        else
            echo "firewalld: 重载失败，请手动检查"
        fi
    else
        echo "未检测到 ufw/firewalld，跳过防火墙规则清理。"
    fi
}

echo -e "\033[33m===== 正在卸载 Shadowsocks-libev =====\033[0m"

PORT=$(extract_port_from_config)
if [ -z "$PORT" ]; then
    echo "未能从配置文件自动解析端口（即使没有 jq 也已尝试 sed/awk）。"
    PORT=$(prompt_port_if_needed "")
fi

if systemctl is-active --quiet shadowsocks-libev.service; then
    require_cmd_success "停止 shadowsocks-libev.service" systemctl stop shadowsocks-libev.service
    require_cmd_success "禁用 shadowsocks-libev.service" systemctl disable shadowsocks-libev.service
elif systemctl is-active --quiet shadowsocks-libev; then
    require_cmd_success "停止 shadowsocks-libev" systemctl stop shadowsocks-libev
    require_cmd_success "禁用 shadowsocks-libev" systemctl disable shadowsocks-libev
fi

if grep -Eqi "Ubuntu|Debian" /etc/issue; then
    require_cmd_success "卸载 shadowsocks-libev 软件包" apt purge -y shadowsocks-libev
    require_cmd_success "自动清理依赖" apt autoremove -y
elif grep -Eqi "CentOS|Red Hat" /etc/redhat-release; then
    require_cmd_success "卸载 shadowsocks-libev 软件包" yum remove -y shadowsocks-libev
fi

require_cmd_success "删除配置文件" rm -f /etc/shadowsocks-libev/config.json
require_cmd_success "删除配置目录" rm -rf /etc/shadowsocks-libev/
require_cmd_success "删除日志文件" rm -f /var/log/shadowsocks-libev.log

BBR_SCRIPT="/usr/local/tcp.sh"
if [ -f "$BBR_SCRIPT" ]; then
    require_cmd_success "删除旧 BBR 脚本" rm -f "$BBR_SCRIPT"
fi

cleanup_firewall "$PORT"

echo -e "\n\033[32m===== Shadowsocks-libev 已成功卸载 =====\033[0m"
echo "已移除以下内容："
echo "1. Shadowsocks-libev 软件包"
echo "2. 配置文件 (/etc/shadowsocks-libev/)"
echo "3. 服务配置"
echo "4. 防火墙规则"
echo "5. BBR加速脚本"
echo -e "\n\033[33m注意：此脚本不会卸载BBR内核模块，如需完全卸载BBR，请手动恢复系统内核设置。\033[0m"

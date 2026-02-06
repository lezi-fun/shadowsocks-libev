#!/bin/bash
set -euo pipefail
IFS=$' \n\t'

# 仅生成 Shadowsocks 链接与二维码（不进行安装与系统修改）

CONFIG_FILE="/etc/shadowsocks-libev/config.json"
METHOD=""
PASSWORD=""
PORT=""
PUBLIC_IP=""
LABEL="Shadowsocks_Server"
MANUAL_IP_USED="false"

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

print_divider() {
    echo "==============================="
}

is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    read -r a b c d <<< "$ip"
    for n in "$a" "$b" "$c" "$d"; do
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        [ "$n" -ge 0 ] && [ "$n" -le 255 ] || return 1
    done
    return 0
}

detect_public_ip() {
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

load_from_config_if_available() {
    if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        local method_from_conf password_from_conf port_from_conf
        method_from_conf=$(jq -r '.method' "$CONFIG_FILE" 2>/dev/null || true)
        password_from_conf=$(jq -r '.password' "$CONFIG_FILE" 2>/dev/null || true)
        port_from_conf=$(jq -r '.server_port' "$CONFIG_FILE" 2>/dev/null || true)

        if [ -n "$method_from_conf" ] && [ "$method_from_conf" != "null" ] \
           && [ -n "$password_from_conf" ] && [ "$password_from_conf" != "null" ] \
           && [ -n "$port_from_conf" ] && [ "$port_from_conf" != "null" ]; then
            read -r -p "检测到现有配置文件，是否使用其中参数生成链接？[Y/n]: " use_conf
            if [ -z "$use_conf" ] || [[ "$use_conf" =~ ^[Yy]$ ]]; then
                METHOD="$method_from_conf"
                PASSWORD="$password_from_conf"
                PORT="$port_from_conf"
            fi
        fi
    fi
}

prompt_for_manual_inputs() {
    PUBLIC_IP=$(prompt_ipv4 "$(detect_public_ip)")

    while true; do
        if [ -n "$PORT" ]; then
            read -r -p "输入端口 [默认：$PORT]: " custom_port
            if [ -z "$custom_port" ]; then
                break
            fi
        else
            read -r -p "输入端口: " custom_port
        fi

        if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
            PORT="$custom_port"
            break
        else
            echo "错误：端口必须是 1-65535 之间的数字！"
        fi
    done

    while [ -z "$PASSWORD" ]; do
        read -r -p "输入密码: " PASSWORD
        [ -n "$PASSWORD" ] || echo "密码不能为空！"
    done

    if [ -z "$METHOD" ]; then
        echo
        echo "请选择加密算法："
        echo "1) aes-256-gcm (默认)"
        echo "2) aes-192-gcm"
        echo "3) aes-128-gcm"
        echo "4) chacha20-ietf-poly1305"
        echo "5) xchacha20-ietf-poly1305"
        echo "6) camellia-256-gcm"
        echo "7) camellia-192-gcm"
        echo "8) camellia-128-gcm"
        read -r -p "输入选项 [1-8] (默认为1): " algo_choice
        case $algo_choice in
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
    fi

    read -r -p "输入标签（用于订阅链接 # 后标识）[默认：$LABEL]: " custom_label
    [ -n "$custom_label" ] && LABEL="$custom_label"
}

url_safe_label() {
    local input="$1"
    local out=""
    local hex byte char

    for hex in $(printf '%s' "$input" | od -An -tx1 -v); do
        byte=$((16#$hex))
        if { [ "$byte" -ge 48 ] && [ "$byte" -le 57 ]; } ||
           { [ "$byte" -ge 65 ] && [ "$byte" -le 90 ]; } ||
           { [ "$byte" -ge 97 ] && [ "$byte" -le 122 ]; } ||
           [ "$byte" -eq 45 ] || [ "$byte" -eq 46 ] || [ "$byte" -eq 95 ] || [ "$byte" -eq 126 ]; then
            printf -v char '%b' "\\x$hex"
            out+="$char"
        else
            out+="%${hex^^}"
        fi
    done

    printf '%s' "$out"
}

generate_and_print() {
    is_ipv4 "$PUBLIC_IP" || die "IP 地址不合法，已停止生成链接。"

    local label_encoded raw encoded encoded_urlsafe ss_url sub_link
    label_encoded=$(url_safe_label "$LABEL")

    raw="${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}"
    encoded=$(echo -n "$raw" | base64 -w 0)
    encoded_urlsafe=$(echo -n "$raw" | base64 -w 0 | tr '+/' '-_' | sed 's/=//g')

    ss_url="ss://${encoded}"
    sub_link="ss://${encoded_urlsafe}#${label_encoded}"

    echo
    echo "===== Shadowsocks 配置信息（未执行安装） ====="
    [ "$MANUAL_IP_USED" = "true" ] && echo "提示：自动检测失败或未采用检测值，已使用手动输入 IP。"
    echo "服务器IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密: $METHOD"
    print_divider
    echo "原始链接: $ss_url"
    echo "订阅链接: $sub_link"
    print_divider

    if command -v qrencode >/dev/null 2>&1; then
        echo "===== 二维码（客户端可扫描） ====="
        require_cmd_success "生成二维码" qrencode -t UTF8 "$ss_url"
    else
        echo "未检测到 qrencode，跳过二维码生成。"
        echo "可执行以下命令安装后再次生成：sudo apt install -y qrencode  或  sudo yum install -y qrencode"
    fi

    print_divider
    echo "客户端下载: https://github.com/clash-version/clash-download"
    echo "请根据你的系统与当前版本需求，自行选择适配的 Clash 客户端。"
}

main() {
    echo "===== 仅生成 Shadowsocks 链接与二维码 ====="
    load_from_config_if_available
    prompt_for_manual_inputs
    generate_and_print
}

main "$@"

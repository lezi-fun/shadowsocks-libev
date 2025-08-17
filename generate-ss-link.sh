#!/bin/bash

# 仅生成 Shadowsocks 链接与二维码（不进行安装与系统修改）

CONFIG_FILE="/etc/shadowsocks-libev/config.json"
METHOD=""
PASSWORD=""
PORT=""
PUBLIC_IP=""
LABEL="Shadowsocks_Server"

print_divider() {
    echo "==============================="
}

detect_public_ip() {
    curl -4 icanhazip.com 2>/dev/null || curl -4 ip.sb 2>/dev/null || echo ""
}

load_from_config_if_available() {
    if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        local method_from_conf password_from_conf port_from_conf
        method_from_conf=$(jq -r '.method' "$CONFIG_FILE" 2>/dev/null)
        password_from_conf=$(jq -r '.password' "$CONFIG_FILE" 2>/dev/null)
        port_from_conf=$(jq -r '.server_port' "$CONFIG_FILE" 2>/dev/null)

        if [ -n "$method_from_conf" ] && [ "$method_from_conf" != "null" ] \
           && [ -n "$password_from_conf" ] && [ "$password_from_conf" != "null" ] \
           && [ -n "$port_from_conf" ] && [ "$port_from_conf" != "null" ]; then
            echo -n "检测到现有配置文件，是否使用其中参数生成链接？[Y/n]: "
            read use_conf
            if [ -z "$use_conf" ] || [[ "$use_conf" =~ ^[Yy]$ ]]; then
                METHOD="$method_from_conf"
                PASSWORD="$password_from_conf"
                PORT="$port_from_conf"
            fi
        fi
    fi
}

prompt_for_manual_inputs() {
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(detect_public_ip)
    fi

    if [ -n "$PUBLIC_IP" ]; then
        echo -n "输入服务器IP [默认：$PUBLIC_IP]: "
        read custom_ip
        if [ -n "$custom_ip" ]; then
            PUBLIC_IP="$custom_ip"
        fi
    else
        echo -n "输入服务器IP: "
        read PUBLIC_IP
    fi

    # 端口输入与校验
    while true; do
        if [ -n "$PORT" ]; then
            echo -n "输入端口 [默认：$PORT]: "
            read custom_port
            if [ -z "$custom_port" ]; then
                break
            fi
        else
            echo -n "输入端口: "
            read custom_port
        fi

        if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
            PORT="$custom_port"
            break
        else
            echo "错误：端口必须是 1-65535 之间的数字！"
        fi
    done

    # 密码输入（必填）
    while [ -z "$PASSWORD" ]; do
        echo -n "输入密码: "
        read PASSWORD
        if [ -z "$PASSWORD" ]; then
            echo "密码不能为空！"
        fi
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
        echo -n "输入选项 [1-8] (默认为1): "
        read algo_choice
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

    echo -n "输入标签（用于订阅链接 # 后标识）[默认：$LABEL]: "
    read custom_label
    if [ -n "$custom_label" ]; then
        LABEL="$custom_label"
    fi
}

url_safe_label() {
    # 仅进行最基础的空格转义，避免引入外部依赖
    echo -n "$1" | sed 's/ /%20/g'
}

generate_and_print() {
    local label_encoded
    label_encoded=$(url_safe_label "$LABEL")

    local raw="${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}"
    local encoded
    encoded=$(echo -n "$raw" | base64 -w 0)
    local encoded_urlsafe
    encoded_urlsafe=$(echo -n "$raw" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=//g')

    local ss_url="ss://${encoded}"
    local sub_link="ss://${encoded_urlsafe}#${label_encoded}"

    echo
    echo "===== Shadowsocks 配置信息（未执行安装） ====="
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
        qrencode -t UTF8 "$ss_url" 2>/dev/null || echo "二维码生成失败，请手动复制链接"
    else
        echo "未检测到 qrencode，跳过二维码生成。"
        echo "可执行以下命令安装后再次生成：sudo apt install -y qrencode  或  sudo yum install -y qrencode"
    fi

    print_divider
    echo "客户端下载: https://shadowsocks.org/en/download/clients.html"
}

main() {
    echo "===== 仅生成 Shadowsocks 链接与二维码 ====="
    load_from_config_if_available
    prompt_for_manual_inputs
    generate_and_print
}

main "$@"
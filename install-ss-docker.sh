#!/bin/bash

# 通过 Docker 安装并运行 Shadowsocks-libev（支持自定义配置与订阅链接/二维码生成）

if [ "$(id -u)" != "0" ]; then
   echo "必须使用 root 用户运行此脚本！" 1>&2
   exit 1
fi

CONFIG_LABEL="Shadowsocks_Docker"

# 检测/安装 Docker
ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        return 0
    fi
    echo "未检测到 Docker。"
    echo -n "是否自动安装 Docker？[Y/n]: "
    read install_docker
    if [ -z "$install_docker" ] || [[ "$install_docker" =~ ^[Yy]$ ]]; then
        echo "开始安装 Docker（使用官方安装脚本）..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker >/dev/null 2>&1 || true
    else
        echo "取消自动安装 Docker，退出。"
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 安装失败，请手动安装后重试。"
        exit 1
    fi
}

# 获取公网 IP
get_public_ip() {
    curl -4 icanhazip.com 2>/dev/null || curl -4 ip.sb 2>/dev/null || echo ""
}

print_divider() {
    echo "==============================="
}

prompt_config() {
    echo -e "\n\033[33m===== Shadowsocks (Docker) 参数设置 =====\033[0m"

    # 端口
    while true; do
        echo -n "输入映射端口 [默认：8388]: "
        read custom_port
        if [ -z "$custom_port" ]; then
            PORT=8388
            break
        elif [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
            PORT="$custom_port"
            break
        else
            echo "错误：端口必须是 1-65535 之间的数字！"
        fi
    done

    # 密码
    echo -n "输入密码 [默认：随机16位字符]: "
    read custom_pass
    if [ -z "$custom_pass" ]; then
        PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    else
        PASSWORD="$custom_pass"
    fi

    # 加密算法
    echo -e "\n请选择加密算法："
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

    # 容器名称
    echo -n "容器名称 [默认：ss-libev]: "
    read container_name
    if [ -z "$container_name" ]; then
        CONTAINER_NAME="ss-libev"
    else
        CONTAINER_NAME="$container_name"
    fi

    # 标签
    echo -n "标签（订阅链接 # 后标识）[默认：$CONFIG_LABEL]: "
    read custom_label
    if [ -n "$custom_label" ]; then
        CONFIG_LABEL="$custom_label"
    fi
}

remove_existing_container_if_needed() {
    if docker ps -a --format '{{.Names}}' | grep -xq "$CONTAINER_NAME"; then
        echo -n "检测到同名容器 '$CONTAINER_NAME'，是否覆盖（删除并重建）？[Y/n]: "
        read replace
        if [ -z "$replace" ] || [[ "$replace" =~ ^[Yy]$ ]]; then
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        else
            echo "已取消操作。"
            exit 1
        fi
    fi
}

run_container() {
    echo "拉取镜像并启动容器..."
    docker pull teddysun/shadowsocks-libev >/dev/null 2>&1 || true
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p ${PORT}:8388/tcp \
        -p ${PORT}:8388/udp \
        -e METHOD="$METHOD" \
        -e PASSWORD="$PASSWORD" \
        -e TZ="Asia/Shanghai" \
        -e ARGS="--fast-open" \
        teddysun/shadowsocks-libev >/dev/null

    if [ $? -ne 0 ]; then
        echo "容器启动失败，请检查 Docker 日志：docker logs $CONTAINER_NAME"
        exit 1
    fi
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
        ufw allow ${PORT}/udp >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${PORT}/tcp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=${PORT}/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
}

url_safe_label() {
    echo -n "$1" | sed 's/ /%20/g'
}

print_result() {
    PUBLIC_IP=$(get_public_ip)

    local raw="${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}"
    local ss_b64
    ss_b64=$(echo -n "$raw" | base64 -w 0)
    local ss_urlsafe
    ss_urlsafe=$(echo -n "$raw" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=//g')

    local SS_URL="ss://${ss_b64}"
    local SUB_LINK="ss://${ss_urlsafe}#$(url_safe_label "$CONFIG_LABEL")"

    echo -e "\n\033[32m===== 安装完成！Shadowsocks (Docker) 配置 =====\033[0m"
    echo "服务器IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密: $METHOD"
    echo "协议: TCP + UDP"
    print_divider
    echo "原始链接: $SS_URL"
    echo "订阅链接: $SUB_LINK"
    print_divider
    if command -v qrencode >/dev/null 2>&1; then
        echo "===== 二维码（使用客户端扫描） ====="
        qrencode -t UTF8 "$SS_URL" 2>/dev/null || echo "二维码生成失败，请手动复制链接"
    else
        echo "未检测到 qrencode，跳过二维码生成。"
        echo "可执行以下命令安装后再次生成：sudo apt install -y qrencode  或  sudo yum install -y qrencode"
    fi
    print_divider
    echo "容器名称: $CONTAINER_NAME"
    echo "管理命令：docker logs -f $CONTAINER_NAME | docker restart $CONTAINER_NAME | docker rm -f $CONTAINER_NAME"
    echo "客户端下载: https://shadowsocks.org/en/download/clients.html"
}

main() {
    echo "===== 通过 Docker 安装 Shadowsocks-libev ====="
    ensure_docker
    prompt_config
    remove_existing_container_if_needed
    run_container
    open_firewall
    print_result
}

main "$@"
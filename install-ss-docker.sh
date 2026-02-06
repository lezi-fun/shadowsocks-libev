#!/bin/bash
set -euo pipefail
IFS=$' \n\t'

# 通过 Docker 安装并运行 Shadowsocks-libev（支持自定义配置与订阅链接/二维码生成）

DOCKER_INSTALL_VERSION="f381ee68b32e515bb4dc034b339266aff1fbc460"
DOCKER_INSTALL_URL="https://raw.githubusercontent.com/docker/docker-install/${DOCKER_INSTALL_VERSION}/install.sh"
EXPECTED_DOCKER_INSTALL_SHA256="395ea8cc3bdd79efb1982580a30ebc84794a6f2ca997d9ea63b42455b9d7792d"
CONFIG_LABEL="Shadowsocks_Docker"
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
    read -r a b c d <<< "$ip"
    for n in "$a" "$b" "$c" "$d"; do
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        [ "$n" -ge 0 ] && [ "$n" -le 255 ] || return 1
    done
    return 0
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

download_and_verify_script() {
    local url="$1"
    local expected_sha256="$2"
    local temp_file
    temp_file=$(mktemp)

    require_cmd_success "下载远程脚本" curl -fsSL "$url" -o "$temp_file"

    local actual_sha256
    actual_sha256=$(sha256sum "$temp_file" | awk '{print $1}')
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        rm -f "$temp_file"
        die "远程脚本校验失败，期望 ${expected_sha256}，实际 ${actual_sha256}。"
    fi

    chmod +x "$temp_file"
    echo "$temp_file"
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

print_divider() {
    echo "==============================="
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        return 0
    fi

    echo "未检测到 Docker。"
    read -r -p "是否自动安装 Docker？[Y/n]: " install_docker
    if [ -n "$install_docker" ] && [[ ! "$install_docker" =~ ^[Yy]$ ]]; then
        die "取消自动安装 Docker，退出。"
    fi

    echo "开始安装 Docker（固定版本脚本 + SHA256 校验）..."
    local installer
    installer=$(download_and_verify_script "$DOCKER_INSTALL_URL" "$EXPECTED_DOCKER_INSTALL_SHA256")
    require_cmd_success "执行 Docker 安装脚本" sh "$installer"
    rm -f "$installer"

    require_cmd_success "启用 Docker 服务" systemctl enable docker
    require_cmd_success "启动 Docker 服务" systemctl start docker

    command -v docker >/dev/null 2>&1 || die "Docker 安装失败，请手动安装后重试。"
}

prompt_config() {
    echo -e "\n\033[33m===== Shadowsocks (Docker) 参数设置 =====\033[0m"

    while true; do
        read -r -p "输入映射端口 [默认：8388]: " custom_port
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

    read -r -p "输入密码 [默认：随机16位字符]: " custom_pass
    if [ -z "$custom_pass" ]; then
        PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    else
        PASSWORD="$custom_pass"
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

    read -r -p "容器名称 [默认：ss-libev]: " container_name
    CONTAINER_NAME=${container_name:-ss-libev}

    read -r -p "标签（订阅链接 # 后标识）[默认：$CONFIG_LABEL]: " custom_label
    if [ -n "$custom_label" ]; then
        CONFIG_LABEL="$custom_label"
    fi
}

remove_existing_container_if_needed() {
    if docker ps -a --format '{{.Names}}' | grep -xq "$CONTAINER_NAME"; then
        read -r -p "检测到同名容器 '$CONTAINER_NAME'，是否覆盖（删除并重建）？[Y/n]: " replace
        if [ -z "$replace" ] || [[ "$replace" =~ ^[Yy]$ ]]; then
            require_cmd_success "删除旧容器" docker rm -f "$CONTAINER_NAME"
        else
            die "已取消操作。"
        fi
    fi
}

run_container() {
    echo "拉取镜像并启动容器..."
    require_cmd_success "拉取镜像" docker pull teddysun/shadowsocks-libev
    require_cmd_success "启动容器" docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${PORT}:8388/tcp" \
        -p "${PORT}:8388/udp" \
        -e METHOD="$METHOD" \
        -e PASSWORD="$PASSWORD" \
        -e TZ="Asia/Shanghai" \
        -e ARGS="--fast-open" \
        teddysun/shadowsocks-libev
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

print_result() {
    local detected_ip public_ip raw ss_b64 ss_urlsafe SS_URL SUB_LINK

    detected_ip=$(get_public_ip)
    public_ip=$(prompt_ipv4 "$detected_ip")

    raw="${METHOD}:${PASSWORD}@${public_ip}:${PORT}"
    ss_b64=$(echo -n "$raw" | base64 -w 0)
    ss_urlsafe=$(echo -n "$raw" | base64 -w 0 | tr '+/' '-_' | sed 's/=//g')

    SS_URL="ss://${ss_b64}"
    SUB_LINK="ss://${ss_urlsafe}#$(url_safe_label "$CONFIG_LABEL")"

    echo -e "\n\033[32m===== 安装完成！Shadowsocks (Docker) 配置 =====\033[0m"
    [ "$MANUAL_IP_USED" = "true" ] && echo "提示：自动检测失败或未采用检测值，已使用手动输入 IP。"
    echo "服务器IP: $public_ip"
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
        require_cmd_success "生成二维码" qrencode -t UTF8 "$SS_URL"
    else
        echo "未检测到 qrencode，跳过二维码生成。"
        echo "可执行以下命令安装后再次生成：sudo apt install -y qrencode  或  sudo yum install -y qrencode"
    fi

    print_divider
    echo "客户端下载: https://github.com/clash-version/clash-download"
    echo "请根据你的系统与当前版本需求，自行选择适配的 Clash 客户端。"
}

main() {
    ensure_docker
    prompt_config
    remove_existing_container_if_needed
    run_container
    open_firewall
    print_result
}

main "$@"

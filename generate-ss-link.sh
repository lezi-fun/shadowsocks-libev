#!/bin/bash

# 仅生成 Shadowsocks 链接与二维码，不进行安装或系统修改

set -e

SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="/etc/shadowsocks-libev/config.json"
DEFAULT_NAME="Shadowsocks_Server"

print_usage() {
    cat << EOF
用法: ${SCRIPT_NAME} [选项]

选项:
  --method <算法>      加密算法（如 aes-256-gcm, chacha20-ietf-poly1305 等）
  --password <密码>    密码
  --port <端口>        端口 (1-65535)
  --ip <IP>            服务器公网IP（默认自动检测）
  --name <名称>        备注名称（附加在链接 # 后），默认：${DEFAULT_NAME}
  -h, --help           显示此帮助

说明:
- 若存在 ${CONFIG_FILE} 且系统安装了 jq，将自动从中读取 method/password/port。
- 如未提供或无法读取，将交互式询问缺失的信息。
- 本脚本只生成链接与二维码，不会进行任何安装或系统修改。
EOF
}

METHOD=""
PASSWORD=""
PORT=""
SERVER_IP=""
NAME="${DEFAULT_NAME}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)
            METHOD="$2"; shift 2 ;;
        --password)
            PASSWORD="$2"; shift 2 ;;
        --port)
            PORT="$2"; shift 2 ;;
        --ip|--server-ip)
            SERVER_IP="$2"; shift 2 ;;
        --name)
            NAME="$2"; shift 2 ;;
        -h|--help)
            print_usage; exit 0 ;;
        *)
            echo "未知参数: $1" >&2
            print_usage
            exit 1 ;;
    esac
done

# 从配置文件读取（如存在且 jq 可用）
if [[ -z "${METHOD}" || -z "${PASSWORD}" || -z "${PORT}" ]]; then
    if [[ -f "${CONFIG_FILE}" ]] && command -v jq >/dev/null 2>&1; then
        METHOD=${METHOD:-$(jq -r '.method // empty' "${CONFIG_FILE}")}
        PASSWORD=${PASSWORD:-$(jq -r '.password // empty' "${CONFIG_FILE}")}
        PORT=${PORT:-$(jq -r '.server_port // empty' "${CONFIG_FILE}")}
    fi
fi

# 自动检测公网IP（如未指定）
if [[ -z "${SERVER_IP}" ]]; then
    if command -v curl >/dev/null 2>&1; then
        SERVER_IP=$(curl -4s icanhazip.com || true)
        if [[ -z "${SERVER_IP}" ]]; then
            SERVER_IP=$(curl -4s ip.sb || true)
        fi
    fi
fi

# 交互式补齐缺失项
# 加密算法
if [[ -z "${METHOD}" ]]; then
    echo -e "\n请选择加密算法："
    echo "1) aes-256-gcm (默认)"
    echo "2) aes-192-gcm"
    echo "3) aes-128-gcm"
    echo "4) chacha20-ietf-poly1305"
    echo "5) xchacha20-ietf-poly1305"
    echo "6) camellia-256-gcm"
    echo "7) camellia-192-gcm"
    echo "8) camellia-128-gcm"
    read -rp "输入选项 [1-8] (默认为1): " ALGO_CHOICE
    case "$ALGO_CHOICE" in
        1|"") METHOD="aes-256-gcm" ;;
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

# 密码
if [[ -z "${PASSWORD}" ]]; then
    read -rp "输入密码 [默认：随机16位字符]: " CUSTOM_PASS
    if [[ -z "${CUSTOM_PASS}" ]]; then
        if [[ -r /dev/urandom ]]; then
            PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
        else
            PASSWORD=$(date +%s | sha256sum | head -c 16)
        fi
    else
        PASSWORD="${CUSTOM_PASS}"
    fi
fi

# 端口
if [[ -z "${PORT}" ]]; then
    while true; do
        read -rp "输入端口 [默认：8388]: " CUSTOM_PORT
        if [[ -z "${CUSTOM_PORT}" ]]; then
            PORT=8388
            break
        elif [[ ! "${CUSTOM_PORT}" =~ ^[0-9]+$ ]] || [[ "${CUSTOM_PORT}" -lt 1 || "${CUSTOM_PORT}" -gt 65535 ]]; then
            echo -e "\033[31m错误：端口必须是1-65535之间的数字！\033[0m"
        else
            PORT="${CUSTOM_PORT}"
            break
        fi
    done
fi

# 服务器IP（允许为空，某些内网或域名场景由用户自行替换）
if [[ -z "${SERVER_IP}" ]]; then
    read -rp "输入服务器公网IP [默认：自动检测失败则需手动填写]: " CUSTOM_IP
    if [[ -n "${CUSTOM_IP}" ]]; then
        SERVER_IP="${CUSTOM_IP}"
    fi
fi

# 备注名称（可选）
if [[ "${NAME}" == "${DEFAULT_NAME}" ]]; then
    read -rp "备注名称 [默认：${DEFAULT_NAME}]: " CUSTOM_NAME
    if [[ -n "${CUSTOM_NAME}" ]]; then
        NAME="${CUSTOM_NAME}"
    fi
fi

# 基础校验
if ! command -v base64 >/dev/null 2>&1; then
    echo "缺少 base64 命令，请先安装后重试。" >&2
    exit 1
fi

# 生成链接
BASIC_STRING="${METHOD}:${PASSWORD}@${SERVER_IP}:${PORT}"
SS_URL="ss://$(echo -n "${BASIC_STRING}" | base64 -w 0)"
SUB_SAFE_BASE64=$(echo -n "${BASIC_STRING}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=//g')
SUB_LINK="ss://${SUB_SAFE_BASE64}#${NAME}"

# 输出
echo -e "\n\033[32m===== Shadowsocks 链接生成 =====\033[0m"
[[ -n "${SERVER_IP}" ]] && echo "服务器IP: ${SERVER_IP}" || echo "服务器IP: (未指定)"
echo "端口: ${PORT}"
echo "密码: ${PASSWORD}"
echo "加密: ${METHOD}"

echo -e "\n\033[33m===== 链接 =====\033[0m"
echo "原始链接: ${SS_URL}"
echo "订阅链接: ${SUB_LINK}"

# 二维码
if command -v qrencode >/dev/null 2>&1; then
    echo -e "\n\033[33m===== 二维码 (使用客户端扫描) =====\033[0m"
    qrencode -t UTF8 "${SS_URL}" || echo "二维码生成失败，请手动复制链接"
else
    echo -e "\n未检测到 qrencode，无法在终端输出二维码。可安装后重试："
    echo "  Ubuntu/Debian: apt install -y qrencode"
    echo "  CentOS: yum install -y qrencode"
fi

exit 0
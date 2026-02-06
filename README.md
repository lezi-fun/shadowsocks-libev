# Shadowsocks-libev 一键安装脚本

![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell Script](https://img.shields.io/badge/Shell_Script-100%25-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS-lightgrey)

一个自动化安装和管理 Shadowsocks-libev 服务器的脚本，支持自定义配置、BBR 加速和订阅链接生成。

English documentation: `README.en.md`

## 功能特点

- ✅ 全自动安装 Shadowsocks-libev 服务端
- 🔧 自定义端口、密码和加密算法
- 🚀 可选启用 BBR 加速优化网络性能（通过系统内核参数配置，不依赖短链接脚本）
- 🔗 自动生成订阅链接供客户端导入
- 📱 支持二维码扫描快速配置
- ️完整的防火墙配置
- 🧹 提供卸载脚本彻底清理环境
- 🔇 安装过程静默（自动使用 -y，并隐藏安装过程输出；错误信息仍会显示）

## 系统要求

- 操作系统：
  - Ubuntu 16.04+
  - Debian 9+
  - CentOS 7+
- 内存：≥ 128MB
- 磁盘空间：≥ 10MB
- 需要 root 权限运行

## 快速开始

### 1. 下载脚本

```bash
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/uninstall-ss.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/generate-ss-link.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss-docker.sh
```

### 2. 赋予执行权限

```bash
chmod +x install-ss.sh uninstall-ss.sh generate-ss-link.sh install-ss-docker.sh
```

### 3. 运行安装脚本（宿主机安装）

```bash
sudo ./install-ss.sh
```

### 4. 按照提示输入配置
- 是否启用 BBR 加速（默认启用，可选）
- 端口号（默认随机生成）
- 密码（默认随机生成）
- 加密算法（从菜单中选择）

### 5. 保存配置信息
安装完成后会显示：
- 服务器 IP
- 端口号
- 密码
- 加密算法
- 订阅链接
- 二维码

## 仅生成链接与二维码（不安装）

无需安装服务端，仅生成 `ss://` 链接与二维码，适合已有服务端或临时分享。

```bash
sudo ./generate-ss-link.sh
```

- 若存在 `/etc/shadowsocks-libev/config.json` 且安装 `jq`，脚本可直接读取 `method/password/port`
- 支持手动输入 IP、端口、密码、加密算法与标签
- 输出原始链接与 URL 安全订阅链接，并尝试用 `qrencode` 生成二维码

可选依赖安装：

```bash
# Ubuntu/Debian
sudo apt install -y jq qrencode
# CentOS
sudo yum install -y jq qrencode
```

## 通过 Docker 安装

无需在宿主机安装 shadowsocks-libev，使用 Docker 运行：

```bash
sudo ./install-ss-docker.sh
```

- 自动检测 Docker，若未安装可选择一键安装（先下载固定版本脚本到临时文件并校验 SHA256，再执行）
- 自定义端口、密码、加密算法、容器名称
- 自动放行防火墙端口（如检测到 `ufw` 或 `firewalld`）
- 安装完成后输出 `ss://` 原始链接、URL 安全订阅链接和二维码（如安装了 `qrencode`）

管理容器：
```bash
docker logs -f ss-libev
docker restart ss-libev
docker rm -f ss-libev
```

## 加密算法选择

脚本提供多种加密算法供选择：

| 选项 | 加密算法 | 推荐度 |
|------|----------|--------|
| 1 | aes-256-gcm (默认) | ⭐⭐⭐⭐⭐ |
| 2 | aes-192-gcm | ⭐⭐⭐⭐ |
| 3 | aes-128-gcm | ⭐⭐⭐⭐ |
| 4 | chacha20-ietf-poly1305 | ⭐⭐⭐⭐⭐ |
| 5 | xchacha20-ietf-poly1305 | ⭐⭐⭐⭐ |
| 6 | camellia-256-gcm | ⭐⭐⭐ |
| 7 | camellia-192-gcm | ⭐⭐⭐ |
| 8 | camellia-128-gcm | ⭐⭐⭐ |

## 订阅链接格式

脚本生成两种格式的订阅链接：

1. 标准格式：
```
ss://base64(加密算法:密码@服务器IP:端口)
```

2. URL 安全格式（兼容更多客户端）：
```
ss://base64(加密算法:密码@服务器IP:端口)#服务器标识
```

> 说明：标签会自动进行 URL 编码（非保留字符以外的字节会编码为 `%HH`），可兼容空格、中文、`#`、`?`、`&` 等内容。

### 哈希升级维护流程（Docker 安装脚本）
1. 选择新的 `docker-install` 固定版本（建议使用 commit/tag，而非短链接）。
2. 下载脚本并计算 SHA256：
```bash
curl -fsSL "https://raw.githubusercontent.com/docker/docker-install/<VERSION>/install.sh" -o /tmp/docker-install.sh
sha256sum /tmp/docker-install.sh
```
3. 仓库内已提供自动化脚本 `scripts/update-docker-install-hash.sh`，并由 GitHub Action `.github/workflows/daily-docker-install-hash.yml` 每天自动执行一次。
4. 若哈希发生变化，Action 会自动更新 `install-ss-docker.sh` 并提交代码；也可手动执行该脚本进行本地更新。

## 客户端支持

### 推荐客户端
- Clash 客户端下载集合：<https://github.com/clash-version/clash-download>
- 请根据你的系统平台与当前版本需求，自行选择适配的 Clash 客户端版本。

### 订阅链接使用
1. 复制脚本生成的订阅链接
2. 在客户端中选择「从剪贴板导入」或「订阅设置」
3. 保存并启用配置

## 管理服务（宿主机安装）

### 查看服务状态
```bash
# Ubuntu/Debian
systemctl status shadowsocks-libev.service

# CentOS
systemctl status shadowsocks-libev
```

### 重启服务
```bash
# Ubuntu/Debian
systemctl restart shadowsocks-libev.service

# CentOS
systemctl restart shadowsocks-libev
```

### 更新配置
1. 编辑配置文件：
```bash
nano /etc/shadowsocks-libev/config.json
```
2. 修改配置后重启服务

## 卸载 Shadowsocks

```bash
sudo ./uninstall-ss.sh
```

卸载脚本将：
1. 停止并禁用 Shadowsocks 服务
2. 卸载 Shadowsocks 软件包
3. 清除所有配置文件
4. 移除防火墙规则
5. 清理日志文件

即使系统中没有 `jq`，卸载脚本也会尝试通过 `sed/awk` 解析端口并清理防火墙规则；若仍失败，会提示手动输入端口。

> 注意：卸载脚本不会移除 BBR 内核优化，因为这些优化通常有益于服务器性能。

## 常见问题

### Q1: 客户端无法连接服务器
- 检查服务器防火墙是否开放端口
- 验证客户端配置是否与服务器一致
- 尝试更换端口（某些端口可能被运营商屏蔽）

### Q2: 如何修改配置后重新生成订阅链接?
1. 编辑配置文件：
```bash
nano /etc/shadowsocks-libev/config.json
```
2. 重启服务
3. 手动生成新订阅链接：
```bash
METHOD=$(jq -r '.method' /etc/shadowsocks-libev/config.json)
PASSWORD=$(jq -r '.password' /etc/shadowsocks-libev/config.json)
PORT=$(jq -r '.server_port' /etc/shadowsocks-libev/config.json)
IP=$(curl -4 icanhazip.com)
echo "ss://$(echo -n "${METHOD}:${PASSWORD}@${IP}:${PORT}" | base64 -w 0)"
```
或者直接使用脚本生成链接与二维码：
```bash
sudo ./generate-ss-link.sh
```

### Q3: 如何升级脚本?
重新下载最新版本脚本：
```bash
wget -O install-ss.sh https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss.sh
chmod +x install-ss.sh
```

## 贡献指南

欢迎提交 Pull Request 改进脚本：
1. Fork 仓库
2. 创建特性分支 (`git checkout -b feature/improvement`)
3. 提交更改 (`git commit -am 'Add some feature'`)
4. 推送到分支 dev (`git push origin feature/improvement`)
5. 创建 Pull Request

- 所有新增的脚本或功能必须同步更新 `README.md` 和 `README.en.md`（涵盖下载方式、执行权限、使用说明、常见问题等），否则 PR 可能不会被合并。

## 许可证

本项目采用 [MIT 许可证](LICENSE)

---

免责声明：此脚本仅用于教育目的，请确保在使用前了解并遵守当地法律法规。开发者不对任何不当使用负责。

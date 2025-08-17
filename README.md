# Shadowsocks-libev 一键安装脚本

![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell Script](https://img.shields.io/badge/Shell_Script-100%25-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS-lightgrey)

一个自动化安装和管理Shadowsocks-libev服务器的脚本，支持自定义配置、BBR加速和订阅链接生成。

## 功能特点

- ✅ 全自动安装Shadowsocks-libev服务端
-🔧 自定义端口、密码和加密算法
-🚀 可选启用 BBR 加速优化网络性能
-🔗 自动生成订阅链接供客户端导入
- 📱 支持二维码扫描快速配置
-️ 完整的防火墙配置
-🧹 提供卸载脚本彻底清理环境

## 系统要求

- 操作系统：
- Ubuntu 16.04+
- Debian 9+
- CentOS 7+
- 内存：≥ 128MB
- 磁盘空间：≥ 10MB
- 需要root权限运行

## 快速开始

### 1. 下载脚本

```bash
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/uninstall-ss.sh
```

### 2. 赋予执行权限

```bash
chmod +x install-ss.sh uninstall-ss.sh
```

### 3. 运行安装脚本

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
- 服务器IP
- 端口号
- 密码
- 加密算法
- 订阅链接
- 二维码

## 加密算法选择

脚本提供多种加密算法供选择：

| 选项 | 加密算法| 推荐度 |
|------|-----------------------|--------|
| 1| aes-256-gcm (默认)| ⭐⭐⭐⭐⭐ |
| 2| aes-192-gcm|⭐⭐⭐⭐|
| 3| aes-128-gcm|⭐⭐⭐⭐|
| 4| chacha20-ietf-poly1305|⭐⭐⭐⭐⭐ |
| 5| xchacha20-ietf-poly1305|⭐⭐⭐⭐ |
| 6| camellia-256-gcm| ⭐⭐⭐|
| 7| camellia-192-gcm|⭐⭐⭐|
| 8| camellia-128-gcm| ⭐⭐⭐|

## 订阅链接格式

脚本生成两种格式的订阅链接：

1. **标准格式**：
```
ss://base64(加密算法:密码@服务器IP:端口)
```

2. **URL安全格式**（兼容更多客户端）：
```
ss://base64(加密算法:密码@服务器IP:端口)#服务器标识
```

## 客户端支持

### 推荐客户端
- **Windows**: [Shadowsocks-Windows](https://github.com/shadowsocks/shadowsocks-windows)
- **macOS**: [ShadowsocksX-NG](https://github.com/shadowsocks/ShadowsocksX-NG)
- **Android**: [Shadowsocks-Android](https://github.com/shadowsocks/shadowsocks-android)
- **iOS**: [Shadowrocket](https://apps.apple.com/us/app/shadowrocket/id932747118)（付费）

### 订阅链接使用
1. 复制脚本生成的订阅链接
2. 在客户端中选择"从剪贴板导入"或"订阅设置"
3. 保存并启用配置

## 管理服务

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

## 卸载Shadowsocks

```bash
sudo ./uninstall-ss.sh
```

卸载脚本将：
1. 停止并禁用Shadowsocks服务
2. 卸载Shadowsocks软件包
3. 清除所有配置文件
4. 移除防火墙规则
5. 清理日志文件

> **注意**：卸载脚本不会移除BBR内核优化，因为这些优化通常有益于服务器性能。

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

### Q3: 如何升级脚本?
重新下载最新版本脚本：
```bash
wget -O install-ss.sh https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss.sh
chmod +x install-ss.sh
```

## 贡献指南

欢迎提交Pull Request改进脚本：
1. Fork仓库
2. 创建特性分支 (`git checkout -b feature/improvement`)
3. 提交更改 (`git commit -am 'Add some feature'`)
4. 推送到分支dev (`git push origin feature/improvement`)
5. 创建Pull Request

## 许可证

本项目采用 [MIT 许可证](LICENSE)

---

**免责声明**: 此脚本仅用于教育目的，请确保在使用前了解并遵守当地法律法规。开发者不对任何不当使用负责。

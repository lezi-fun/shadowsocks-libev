# Shadowsocks-libev One-Click Scripts

![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell Script](https://img.shields.io/badge/Shell_Script-100%25-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS-lightgrey)

English documentation for the scripts in this repository. For Chinese, see `README.md`.

## Features

- ✅ Automated installation of Shadowsocks-libev server
- 🔧 Custom port, password, and cipher
- 🚀 Optional BBR acceleration
- 🔗 Auto-generate client import links
- 📱 QR code for quick client setup
- 🔇 Silent package installation (auto -y, hide process output; errors still shown)
- 🧱 Firewall rules auto-open
- 🧹 Uninstall script included

## Requirements

- OS: Ubuntu 16.04+, Debian 9+, CentOS 7+
- Memory: ≥ 128MB, Disk: ≥ 10MB
- Root privileges

## Quick Start

### 1) Download scripts
```bash
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/uninstall-ss.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/generate-ss-link.sh
wget https://raw.githubusercontent.com/lezi-fun/shadowsocks-libev/main/install-ss-docker.sh
```

### 2) Make executable
```bash
chmod +x install-ss.sh uninstall-ss.sh generate-ss-link.sh install-ss-docker.sh
```

### 3) Install on host
```bash
sudo ./install-ss.sh
```
Follow prompts to choose port, password and cipher.

### 4) Generate link and QR only (no install)
```bash
sudo ./generate-ss-link.sh
```
- Reads `method/password/port` from `/etc/shadowsocks-libev/config.json` if present (requires `jq`)
- Otherwise prompts for manual input
- Prints raw `ss://` link, URL-safe link, and QR code (requires `qrencode`)

### 5) Run with Docker
```bash
sudo ./install-ss-docker.sh
```
- Detects Docker and offers auto-install (official script)
- Custom port, password, cipher, container name
- Auto-open firewall (if `ufw` or `firewalld` exists)
- Outputs links and QR after setup

Container management:
```bash
docker logs -f ss-libev
docker restart ss-libev
docker rm -f ss-libev
```

## Cipher Options

- aes-256-gcm (default)
- aes-192-gcm
- aes-128-gcm
- chacha20-ietf-poly1305
- xchacha20-ietf-poly1305
- camellia-256-gcm
- camellia-192-gcm
- camellia-128-gcm

## Subscription Link Format

1) Standard:
```
ss://base64(cipher:password@server_ip:port)
```
2) URL-safe (for broader client compatibility):
```
ss://base64(cipher:password@server_ip:port)#label
```

## Clients

- Windows: Shadowsocks-Windows
- macOS: ShadowsocksX-NG
- Android: Shadowsocks-Android
- iOS: Shadowrocket (paid)

## Manage Service (host install)

Check status:
```bash
# Ubuntu/Debian
systemctl status shadowsocks-libev.service
# CentOS
systemctl status shadowsocks-libev
```

Restart:
```bash
# Ubuntu/Debian
systemctl restart shadowsocks-libev.service
# CentOS
systemctl restart shadowsocks-libev
```

Update config:
```bash
nano /etc/shadowsocks-libev/config.json
# then restart service
```

## Uninstall
```bash
sudo ./uninstall-ss.sh
```
- Stops and disables service
- Removes package and config
- Cleans firewall rules and logs

## FAQ

- Client cannot connect?
  - Check firewall rules
  - Verify client config matches server
  - Try another port (ISP filtering possible)

- Regenerate subscription link after config change?
  - Use `generate-ss-link.sh`, or manually:
```bash
METHOD=$(jq -r '.method' /etc/shadowsocks-libev/config.json)
PASSWORD=$(jq -r '.password' /etc/shadowsocks-libev/config.json)
PORT=$(jq -r '.server_port' /etc/shadowsocks-libev/config.json)
IP=$(curl -4 icanhazip.com)
echo "ss://$(echo -n "${METHOD}:${PASSWORD}@${IP}:${PORT}" | base64 -w 0)"
```

## Contributing

- Please update both `README.md` and `README.en.md` when adding new scripts or features (download, permissions, usage, FAQ), otherwise the PR may not be accepted.

## License

MIT License. See `LICENSE`.

---

Disclaimer: For educational purposes only. Ensure compliance with local laws and regulations. The author assumes no responsibility for misuse.
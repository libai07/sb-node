# sb-node

sing-box 一键搭建脚本，默认部署：

```text
VLESS TCP REALITY Vision
Hysteria2
```

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/libai07/sb-node/main/install.sh -o /tmp/sb-node-install.sh && sudo bash /tmp/sb-node-install.sh
```

自定义参数示例：

```bash
curl -fsSL https://raw.githubusercontent.com/libai07/sb-node/main/install.sh -o /tmp/sb-node-install.sh && sudo PORT=8443 HY2_PORT=8443 SERVER_NAME=apple.com REALITY_SERVER=apple.com SERVER_ADDR=your.server.domain bash /tmp/sb-node-install.sh
```

## 默认参数

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `443` | VLESS TCP 端口 |
| `HY2_PORT` | 同 `PORT` | Hysteria2 UDP 端口 |
| `SERVER_ADDR` | 自动探测 | 节点地址，优先 IPv4 |
| `SERVER_NAME` | `apple.com` | SNI |
| `REALITY_SERVER` | 同 `SERVER_NAME` | REALITY 握手目标 |
| `OUTPUT_DIR` | `/root/sb-node` | 节点信息目录 |

## 输出

```text
/root/sb-node/sb-node.txt
```

脚本只输出两个节点：

```text
VLESS:
vless://...

Hysteria2:
hysteria2://...
```

## 管理

```bash
sudo systemctl status sing-box
sudo systemctl restart sing-box
sudo journalctl -u sing-box --output cat -f
sudo sing-box check -c /etc/sing-box/config.json
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/libai07/sb-node/main/uninstall.sh -o /tmp/sb-node-uninstall.sh && sudo bash /tmp/sb-node-uninstall.sh
```

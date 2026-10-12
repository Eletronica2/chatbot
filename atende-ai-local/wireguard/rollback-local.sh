#!/usr/bin/env bash
# Atende AI — IA-02: desfaz o túnel no servidor local. Não toca Wi-Fi, netplan, SSH, Docker nem dados.
# Mantém a chave em /etc/wireguard (remova manualmente se for descartar o par).
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "execute com sudo"; exit 1; }
systemctl disable --now atende-ai-netwatch.timer atende-ai-vpn-proxy.socket atende-ai-vpn-proxy.service 2>/dev/null
systemctl disable --now wg-quick@wg0 2>/dev/null
nft delete table inet atende_ai 2>/dev/null
rm -f /etc/systemd/system/atende-ai-netwatch.{service,timer} /etc/systemd/system/atende-ai-vpn-proxy.{socket,service}
systemctl daemon-reload
ip -br addr show wg0 2>/dev/null || echo "wg0 removida"
ip -4 route show default

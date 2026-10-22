#!/usr/bin/env bash
# Atende AI — IA-02: lado AWS do túnel WireGuard (servidor; escuta UDP 51820, autenticado pela chave).
#
# Uso: sudo bash infra/wireguard/setup-aws.sh <CHAVE_PUBLICA_DO_SERVIDOR_LOCAL>
#
# wg0 = 10.77.0.1/30, peer 10.77.0.2/32. Não altera a rota default, não roteia a VPC para o túnel e não
# aceita conexões iniciadas pelo servidor local (somente respostas + ping). Containers alcançam 10.77.0.2
# via MASQUERADE do Docker (origem vira 10.77.0.1).
# Rollback: sudo systemctl disable --now wg-quick@wg0
set -euo pipefail
LOCAL_PUBKEY=${1:?informe a chave pública do servidor local}
[[ $EUID -eq 0 ]] || { echo "execute com sudo"; exit 1; }
[[ "$LOCAL_PUBKEY" =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$ ]] || { echo "chave pública inválida"; exit 1; }
. /etc/os-release
[[ ${ID:-} == amzn && ${VERSION_ID:-} == 2023 ]] || {
  echo "este instalador foi preparado para Amazon Linux 2023; sistema detectado: ${PRETTY_NAME:-desconhecido}"; exit 1;
}
exec 9>/run/lock/atende-ai-wireguard-setup.lock
flock -n 9 || { echo "outra configuração WireGuard já está em andamento"; exit 1; }
if [[ -f /etc/wireguard/wg0.conf ]] \
   && ! grep -Fq '# Atende AI — túnel privado AWS' /etc/wireguard/wg0.conf; then
  echo "wg0.conf existente não pertence à IA-02; nenhuma configuração foi alterada"; exit 1
fi
if ip link show wg0 >/dev/null 2>&1 && [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "wg0 já existe sem configuração IA-02; nenhuma configuração foi alterada"; exit 1
fi
if [[ ! -f /etc/wireguard/wg0.conf ]] && iptables -nL ATENDE_WG_IN >/dev/null 2>&1; then
  echo "cadeia ATENDE_WG_IN já existe sem configuração IA-02; nenhuma configuração foi alterada"; exit 1
fi

if ! command -v wg >/dev/null || ! command -v iptables >/dev/null; then
  command -v dnf >/dev/null || { echo "dnf indisponível; instale wireguard-tools e iptables-nft manualmente"; exit 1; }
  dnf install -y wireguard-tools iptables-nft
fi

DEFAULT_BEFORE=$(ip -4 route show default)
install -d -m 700 /etc/wireguard
[[ -f /etc/wireguard/wg0.key ]] || (umask 077; wg genkey > /etc/wireguard/wg0.key)
chmod 600 /etc/wireguard/wg0.key
[[ -f /etc/wireguard/wg0.conf ]] && cp -a /etc/wireguard/wg0.conf "/etc/wireguard/wg0.conf.bak-$(date +%Y%m%d%H%M%S)"

FWD_CHAIN=FORWARD
iptables -nL DOCKER-USER >/dev/null 2>&1 && FWD_CHAIN=DOCKER-USER

umask 077
cat > /etc/wireguard/wg0.conf <<EOF
# Atende AI — túnel privado AWS <-> servidor local (somente 10.77.0.0/30). Gerado em $(date -Is).
[Interface]
Address = 10.77.0.1/30
ListenPort = 51820
PostUp = wg set %i private-key /etc/wireguard/wg0.key
PostUp = iptables -N ATENDE_WG_IN 2>/dev/null || true
PostUp = iptables -F ATENDE_WG_IN
PostUp = iptables -A ATENDE_WG_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = iptables -A ATENDE_WG_IN -s 10.77.0.2 -p icmp --icmp-type echo-request -j ACCEPT
PostUp = iptables -A ATENDE_WG_IN -j DROP
PostUp = iptables -C INPUT -i %i -j ATENDE_WG_IN 2>/dev/null || iptables -I INPUT 1 -i %i -j ATENDE_WG_IN
PostUp = iptables -C $FWD_CHAIN -i %i -m conntrack ! --ctstate ESTABLISHED,RELATED -j DROP 2>/dev/null || iptables -I $FWD_CHAIN 1 -i %i -m conntrack ! --ctstate ESTABLISHED,RELATED -j DROP
PreDown = iptables -D $FWD_CHAIN -i %i -m conntrack ! --ctstate ESTABLISHED,RELATED -j DROP || true
PreDown = iptables -D INPUT -i %i -j ATENDE_WG_IN || true
PreDown = iptables -F ATENDE_WG_IN || true
PreDown = iptables -X ATENDE_WG_IN || true

[Peer]
PublicKey = $LOCAL_PUBKEY
AllowedIPs = 10.77.0.2/32
EOF
umask 022
chmod 600 /etc/wireguard/wg0.conf

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
sleep 1
if [[ "$(ip -4 route show default)" != "$DEFAULT_BEFORE" ]]; then
  echo "ERRO: rota default mudou — desligando wg0"; systemctl disable --now wg-quick@wg0; exit 1
fi
ip -br addr show wg0
ip route show dev wg0
wg show wg0 | grep -v -i 'private key'
AWS_PUBLIC_KEY=$(wg pubkey < /etc/wireguard/wg0.key)
printf '%s\n' "$AWS_PUBLIC_KEY" > /home/ec2-user/ia02-wireguard/aws-public.key
chown ec2-user:ec2-user /home/ec2-user/ia02-wireguard/aws-public.key
chmod 644 /home/ec2-user/ia02-wireguard/aws-public.key
echo "AWS_PUBKEY=$AWS_PUBLIC_KEY"

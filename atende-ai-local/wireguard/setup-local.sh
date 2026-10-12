#!/usr/bin/env bash
# Atende AI — IA-02: configura o túnel WireGuard no servidor local (lado cliente; ele inicia a conexão).
#
# Uso (executar a partir de uma sessão SSH na LAN; a sessão não passa pelo túnel):
#   sudo bash /opt/atende-ai-local/wireguard/setup-local.sh <CHAVE_PUBLICA_AWS> [ENDPOINT_AWS:51820]
#
# O que faz: auditoria root (somente leitura) -> backups -> instala wireguard-tools -> gera chave local (600)
# -> wg0 10.77.0.2/30 com AllowedIPs 10.77.0.1/32 (sem rota default, sem full tunnel) -> regras nft restritas
# -> proxy 10.77.0.2:8100 -> 127.0.0.1:8100 -> monitor de rede. Não altera netplan, Wi-Fi, IP, SSH nem Docker.
# Se a rota default ou o SSH mudarem depois de subir o túnel, o túnel é desligado automaticamente.
# Rollback completo: sudo bash /opt/atende-ai-local/wireguard/rollback-local.sh
set -euo pipefail

AWS_PUBKEY=${1:?informe a chave pública WireGuard da AWS}
ENDPOINT=${2:-3.218.194.130:51820}
SRC=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)
BACKUP=/var/backups/atende-ai-local/pre-ia02-$TS
REPORT=/tmp/ia02-setup-report.txt
WIFI=wlxe01cfca274a9

[[ $EUID -eq 0 ]] || { echo "execute com sudo"; exit 1; }
[[ "$AWS_PUBKEY" =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$ ]] || { echo "chave pública inválida"; exit 1; }

exec > >(tee "$REPORT") 2>&1
chmod 644 "$REPORT"
echo "== IA-02 setup-local $(date -Is)"

echo "== 1. Linha de base (antes)"
DEFAULT_BEFORE=$(ip -4 route show default)
DEFAULT6_DEV_BEFORE=$(ip -6 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
echo "rota default: $DEFAULT_BEFORE"
echo "rota default v6 (dev): ${DEFAULT6_DEV_BEFORE:-nenhuma}"
ss -lnt '( sport = :22 )' | tail -n +2

echo "== 2. Auditoria root (somente leitura)"
echo "-- ufw"; ufw status verbose 2>&1 || true
echo "-- tabelas nft"; nft list tables 2>&1 || true
echo "-- regras nft/ip6tables que mencionam a porta 22"; (nft list ruleset 2>/dev/null | grep -n -E 'dport (22|ssh)\b' || echo "nenhuma")
echo "-- ip6tables INPUT (política)"; ip6tables -S INPUT 2>/dev/null | head -5 || true
echo "-- sshd efetivo"; sshd -T 2>/dev/null | grep -E '^(port|listenaddress|addressfamily|passwordauthentication|permitrootlogin|pubkeyauthentication|kbdinteractiveauthentication) ' || true
echo "-- sudoers.d"; ls -1 /etc/sudoers.d
if command -v iw >/dev/null; then echo "-- power save"; iw dev "$WIFI" get power_save || true; fi

echo "== 3. Backups (não sobrescreve: diretório novo $BACKUP)"
install -d -m 700 "$BACKUP"
cp -a /etc/netplan "$BACKUP/netplan"
nft list ruleset > "$BACKUP/nft-ruleset.txt" 2>/dev/null || true
cp -a /etc/ssh/sshd_config "$BACKUP/" 2>/dev/null || true
[[ -d /etc/wireguard ]] && cp -a /etc/wireguard "$BACKUP/wireguard"
chmod -R go-rwx "$BACKUP"
echo "backup de configuração: $BACKUP"
if [[ -x /opt/atende-ai-local/scripts/backup.sh || -f /opt/atende-ai-local/scripts/backup.sh ]]; then
  echo "-- snapshot Qdrant"
  KEEP=14 bash /opt/atende-ai-local/scripts/backup.sh | tail -2 || echo "AVISO: backup Qdrant falhou (continuando; registrar)"
fi

echo "== 4. Pacotes"
if ! command -v wg >/dev/null; then
  apt-get update -q >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends wireguard-tools iw >/dev/null
fi
wg --version
command -v iw >/dev/null && { echo "-- power save (somente leitura)"; iw dev "$WIFI" get power_save || true; }

echo "== 5. Chave local (gerada no servidor; nunca exibida)"
install -d -m 700 /etc/wireguard
if [[ ! -f /etc/wireguard/wg0.key ]]; then
  (umask 077; wg genkey > /etc/wireguard/wg0.key)
fi
chmod 600 /etc/wireguard/wg0.key
LOCAL_PUBKEY=$(wg pubkey < /etc/wireguard/wg0.key)

echo "== 6. Configuração wg0"
install -d -m 755 /etc/atende-ai
install -m 644 "$SRC/atende-ai.nft" /etc/atende-ai/atende-ai.nft
NFT_CHECK=$(mktemp)
sed 's/table inet atende_ai {/table inet atende_ai_validation {/' /etc/atende-ai/atende-ai.nft > "$NFT_CHECK"
if nft -c -f "$NFT_CHECK"; then
  rm -f "$NFT_CHECK"
else
  rm -f "$NFT_CHECK"
  exit 1
fi
umask 077
cat > /etc/wireguard/wg0.conf <<EOF
# Atende AI — túnel privado servidor local <-> AWS (somente 10.77.0.0/30). Gerado em $(date -Is).
[Interface]
Address = 10.77.0.2/30
PostUp = wg set %i private-key /etc/wireguard/wg0.key
PostUp = nft delete table inet atende_ai 2>/dev/null || true
PostUp = nft -f /etc/atende-ai/atende-ai.nft
PreDown = nft delete table inet atende_ai || true

[Peer]
PublicKey = $AWS_PUBKEY
Endpoint = $ENDPOINT
AllowedIPs = 10.77.0.1/32
PersistentKeepalive = 25
EOF
umask 022
chmod 600 /etc/wireguard/wg0.conf

echo "== 7. Proxy e monitor"
install -m 644 "$SRC/atende-ai-vpn-proxy.socket" "$SRC/atende-ai-vpn-proxy.service" \
  "$SRC/atende-ai-netwatch.service" "$SRC/atende-ai-netwatch.timer" /etc/systemd/system/
install -m 755 "$SRC/netwatch.sh" /usr/local/sbin/atende-ai-netwatch
install -d -m 755 /var/lib/atende-ai/netwatch
systemctl daemon-reload

echo "== 8. Ativação"
systemctl enable --now wg-quick@wg0
sleep 2
DEFAULT_AFTER=$(ip -4 route show default)
DEFAULT6_DEV_AFTER=$(ip -6 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
if [[ "$DEFAULT_AFTER" != "$DEFAULT_BEFORE" || "$DEFAULT6_DEV_AFTER" != "$DEFAULT6_DEV_BEFORE" ]] \
   || ! ss -lnt '( sport = :22 )' | grep -q LISTEN; then
  echo "ERRO: rota default ou SSH mudou após subir wg0 — desligando o túnel"
  systemctl disable --now wg-quick@wg0
  exit 1
fi
systemctl enable --now atende-ai-vpn-proxy.socket
systemctl enable --now atende-ai-netwatch.timer

echo "== 9. Verificação"
echo "rota default (depois): $DEFAULT_AFTER"
ip -br addr show wg0
ip route show dev wg0
wg show wg0 | grep -v -i 'private key'
nft list table inet atende_ai | grep -c counter | xargs echo "regras com contador:"
systemctl is-active wg-quick@wg0 atende-ai-vpn-proxy.socket atende-ai-netwatch.timer
ss -lnt '( sport = :8100 )' | tail -n +2
echo
echo "LOCAL_PUBKEY=$LOCAL_PUBKEY"
echo "== concluído. Relatório: $REPORT"

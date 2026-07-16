#!/bin/bash
set -e

echo "=== [houbeidSW] Installation des paquets ==="
apt-get update -y
apt-get install -y curl netcat-openbsd

echo "=== [houbeidSW] SSH sans mot de passe ==="
echo "Vagrant fournit deja une connexion SSH sans mot de passe (host -> VM) via sa cle par defaut."

echo "=== [houbeidSW] Attente du server K3s ==="
RETRIES=0
until nc -z ${SERVER_IP} 6443; do
  sleep 5
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -ge 60 ]; then
    echo "ERREUR: Server K3s inaccessible"
    exit 1
  fi
  echo "En attente du server... ($RETRIES/60)"
done

echo "=== [houbeidSW] Installation K3s agent ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server=https://${SERVER_IP}:6443 \
  --token=${K3S_TOKEN} \
  --node-ip=${WORKER_IP}" sh -

echo "=== [houbeidSW] Verification agent ==="
systemctl status k3s-agent --no-pager

echo "=== [houbeidSW] Pret ! ==="
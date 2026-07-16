#!/bin/bash
set -e

echo "=== [houbeidS] Installation des paquets ==="
apt-get update -y
apt-get install -y curl

echo "=== [houbeidS] SSH sans mot de passe ==="
echo "Vagrant fournit deja une connexion SSH sans mot de passe (host -> VM) via sa cle par defaut."
echo "Verification : vagrant ssh houbeidS doit fonctionner sans demander de mot de passe."

echo "=== [houbeidS] Installation K3s (server) ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --node-ip=${SERVER_IP} \
  --token=${K3S_TOKEN} \
  --disable=traefik \
  --write-kubeconfig-mode=644" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== [houbeidS] Attente que K3s soit pret ==="
RETRIES=0
until k3s kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 5
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -ge 24 ]; then
    echo "ERREUR: K3s ne demarre pas"
    exit 1
  fi
  echo "En attente de K3s... ($RETRIES/24)"
done

echo "=== [houbeidS] Configuration kubeconfig ==="
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 600 /home/vagrant/.kube/config

echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc

echo "=== [houbeidS] Installation explicite de kubectl ==="
if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl
fi

echo "=== [houbeidS] Verification ==="
kubectl get nodes
kubectl get pods -A

echo "=== [houbeidS] Pret ! ==="
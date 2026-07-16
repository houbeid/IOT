#!/bin/bash
set -e

echo "=== [houbeidS] Installation des paquets ==="
apt-get update -y
apt-get install -y curl

echo "=== [houbeidS] Installation K3s (server, Traefik actif, composants inutiles desactives) ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --node-ip=${SERVER_IP} \
  --disable=metrics-server \
  --disable=local-storage \
  --write-kubeconfig-mode=644" sh -

# IMPORTANT : sans cet export, kubectl ne trouve pas le cluster
# et la boucle d'attente ci-dessous tournerait indefiniment.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== [houbeidS] Attente que K3s soit pret ==="
RETRIES=0
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 5
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -ge 24 ]; then
    echo "ERREUR: K3s ne demarre pas"
    exit 1
  fi
  echo "En attente de K3s... ($RETRIES/24)"
done

echo "=== [houbeidS] Configuration kubeconfig pour l'utilisateur vagrant ==="
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

echo "=== [houbeidS] Attente que Traefik (ingress controller) soit pret ==="
RETRIES=0
MAX_RETRIES=60   # 60 x 5s = 5 minutes : le telechargement de l'image Traefik peut etre long
until kubectl get pods -n kube-system --no-headers 2>/dev/null \
    | awk '{print $1, $3}' | grep -E '^traefik-' | grep -q 'Running'; do
  sleep 5
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -ge $MAX_RETRIES ]; then
    echo "ERREUR: Traefik ne demarre pas apres 5 minutes"
    echo "--- Etat des pods kube-system pour diagnostic ---"
    kubectl get pods -n kube-system -o wide
    exit 1
  fi
  echo "En attente de Traefik... ($RETRIES/$MAX_RETRIES)"
done

echo "=== [houbeidS] Deploiement des 3 applications + Ingress ==="

# La VM etant limitee a 1 CPU, l'API server peut timeout ponctuellement
# quand plusieurs pods demarrent en meme temps. Cette fonction reessaie
# automatiquement au lieu de faire planter tout le script.
apply_with_retry() {
  local file=$1
  local attempts=0
  until kubectl apply -f "$file" --request-timeout=60s; do
    attempts=$((attempts+1))
    if [ $attempts -ge 5 ]; then
      echo "ERREUR: impossible d'appliquer $file apres 5 tentatives"
      exit 1
    fi
    echo "Nouvelle tentative pour $file dans 10s... ($attempts/5)"
    sleep 10
  done
}

apply_with_retry /vagrant/confs/app1.yaml
sleep 5
apply_with_retry /vagrant/confs/app2.yaml
sleep 5
apply_with_retry /vagrant/confs/app3.yaml
sleep 5
apply_with_retry /vagrant/confs/ingress.yaml

echo "=== [houbeidS] Attente que les pods soient prets ==="
kubectl wait --for=condition=Ready pods --all --timeout=180s || true

echo "=== [houbeidS] Verification ==="
kubectl get all
kubectl get ingress -o wide

echo "=== [houbeidS] Pret ! ==="
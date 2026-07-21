#!/bin/bash
set -e

# ---------- Fonctions de log ----------
log_info()    { echo -e "\e[34m[INFO]\e[0m $1"; }
log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
log_warn()    { echo -e "\e[33m[WARN]\e[0m $1"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $1"; }

GITHUB_REPO="https://github.com/houbeid/houbeid-iot-argocd.git"
CLUSTER_NAME="iot-cluster"
APP_PORT="${APP_PORT:-8888}"

# ---------- 1. Mise a jour systeme + prerequis ----------
log_info "=== Mise a jour du systeme ==="
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git apt-transport-https

# ---------- 2. Docker ----------
log_info "=== Installation de Docker ==="
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh -
  usermod -aG docker vagrant
  systemctl enable docker
  systemctl start docker
  log_success "Docker installe"
else
  log_warn "Docker deja installe, on passe"
fi

# ---------- 3. kubectl ----------
log_info "=== Installation de kubectl ==="
if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl
  log_success "kubectl installe"
else
  log_warn "kubectl deja installe, on passe"
fi

# ---------- 4. k3d ----------
log_info "=== Installation de k3d ==="
if ! command -v k3d >/dev/null 2>&1; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  log_success "k3d installe"
else
  log_warn "k3d deja installe, on passe"
fi

# ---------- 5. argocd CLI ----------
log_info "=== Installation du CLI argocd ==="
if ! command -v argocd >/dev/null 2>&1; then
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x /usr/local/bin/argocd
  log_success "argocd CLI installe"
else
  log_warn "argocd CLI deja installe, on passe"
fi

# ---------- 6. Cluster K3d ----------
log_info "=== Creation du cluster K3d ==="
if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  k3d cluster create "$CLUSTER_NAME" \
    --agents 1 \
    --port "${APP_PORT}:${APP_PORT}@loadbalancer" \
    --wait
  log_success "Cluster K3d '$CLUSTER_NAME' cree"
else
  log_warn "Cluster K3d '$CLUSTER_NAME' existe deja"
fi

# ---------- 7. kubeconfig ----------
log_info "=== Configuration du kubeconfig ==="
mkdir -p /root/.kube /home/vagrant/.kube
k3d kubeconfig get "$CLUSTER_NAME" > /root/.kube/config
cp /root/.kube/config /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 600 /home/vagrant/.kube/config
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc
export KUBECONFIG=/root/.kube/config

log_info "=== Attente que le cluster K3d soit pret ==="
RETRIES=0
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 5
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -ge 24 ]; then
    log_error "Le cluster K3d ne demarre pas"
    exit 1
  fi
  log_info "En attente du cluster... ($RETRIES/24)"
done
log_success "Cluster K3d pret"

# ---------- 8. Namespaces ----------
log_info "=== Creation des namespaces ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# ---------- 9. Installation Argo CD ----------
log_info "=== Installation d'Argo CD (namespace argocd) ==="
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log_info "=== Attente que Argo CD soit pret (peut prendre plusieurs minutes) ==="
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# ---------- 10. Deploiement de l'Application (GitOps) ----------
log_info "=== Deploiement de l'Application Argo CD (pointe vers ${GITHUB_REPO}) ==="
kubectl apply -f /vagrant/confs/argocd-application.yaml

log_info "=== Attente de la premiere synchronisation ==="
sleep 20
kubectl get applications -n argocd

# ---------- 11. Exposition de l'application ----------
log_info "=== Exposition de wil-playground sur le port ${APP_PORT} ==="
pkill -f "port-forward.*wil-playground" 2>/dev/null || true
nohup kubectl port-forward svc/wil-playground -n dev "${APP_PORT}:${APP_PORT}" --address 0.0.0.0 \
  > /var/log/port-forward.log 2>&1 &
sleep 5

# ---------- 12. Verification ----------
log_info "=== Verification finale ==="
kubectl get ns
echo ""
kubectl get pods -n dev
echo ""
kubectl get applications -n argocd
echo ""
curl -s "http://localhost:${APP_PORT}/" || log_warn "App pas encore prete, reessayez dans quelques secondes : curl http://localhost:${APP_PORT}/"

log_success "=== Installation terminee ==="
log_info "Mot de passe admin Argo CD : kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
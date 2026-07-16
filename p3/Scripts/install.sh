!/bin/bash
 
# # =============================================================================
# #   Script d'installation - IoT Part 3 : K3d + ArgoCD
# # =============================================================================
 
# set -e  # Stop si une erreur survient
 
# # Couleurs pour les logs
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# NC='\033[0m' # No Color
 
# log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
# log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
# log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
# log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
 
# # =============================================================================
# # VARIABLES
# # =============================================================================
 
ARGOCD_VERSION="v2.10.0"
K3D_VERSION="v5.6.3"
KUBECTL_VERSION="v1.29.0"
CLUSTER_NAME="iot-cluster"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITHUB_REPO="https://github.com/houbeid/IOT"  # ← Modifier ici
APP_PORT="8888"
 
# # =============================================================================
# # 1. MISE A JOUR DU SYSTEME
# # =============================================================================
 
# log_info "Mise à jour du système..."
# sudo apt-get update -y && sudo apt-get upgrade -y
# sudo apt-get install -y \
#     curl \
#     wget \
#     git \
#     apt-transport-https \
#     ca-certificates \
#     gnupg \
#     lsb-release \
#     jq
# log_success "Système mis à jour"
 
# # =============================================================================
# # 3. INSTALLATION DE KUBECTL
# # =============================================================================
 
# log_info "Installation de kubectl ${KUBECTL_VERSION}..."
 
# if command -v kubectl &> /dev/null; then
#     log_warn "kubectl déjà installé : $(kubectl version --client --short 2>/dev/null)"
# else
#     curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
#     chmod +x kubectl
#     sudo mv kubectl /usr/local/bin/kubectl
#     log_success "kubectl installé : $(kubectl version --client --short 2>/dev/null)"
# fi
 
# # =============================================================================
# # 4. INSTALLATION DE K3D
# # =============================================================================
 
# log_info "Installation de K3d ${K3D_VERSION}..."
 
# if command -v k3d &> /dev/null; then
#     log_warn "K3d déjà installé : $(k3d version)"
# else
#     curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | \
#         TAG=${K3D_VERSION} bash
#     log_success "K3d installé : $(k3d version)"
# fi
 
# # =============================================================================
# # 5. INSTALLATION DE L'ARGOCD CLI
# # =============================================================================
 
# log_info "Installation de ArgoCD CLI ${ARGOCD_VERSION}..."
 
# if command -v argocd &> /dev/null; then
#     log_warn "ArgoCD CLI déjà installé : $(argocd version --client --short 2>/dev/null)"
# else
#     curl -sSL -o argocd \
#         "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
#     chmod +x argocd
#     sudo mv argocd /usr/local/bin/argocd
#     log_success "ArgoCD CLI installé : $(argocd version --client --short 2>/dev/null)"
# fi
 
# =============================================================================
# 6. CREATION DU CLUSTER K3D
# =============================================================================
 
log_info "Création du cluster K3d '${CLUSTER_NAME}'..."
 
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' déjà existant"
else
    k3d cluster create ${CLUSTER_NAME} \
        --port "${APP_PORT}:${APP_PORT}@loadbalancer" \
        --wait
 
    log_success "Cluster '${CLUSTER_NAME}' créé"
fi
 
# Vérification que kubectl pointe bien sur le cluster
kubectl config use-context k3d-${CLUSTER_NAME}
log_success "kubectl configuré sur le cluster k3d-${CLUSTER_NAME}"
 
# =============================================================================
# 7. CREATION DES NAMESPACES
# =============================================================================
 
log_info "Création des namespaces..."
 
# Namespace ArgoCD
if kubectl get namespace ${ARGOCD_NAMESPACE} &> /dev/null; then
    log_warn "Namespace '${ARGOCD_NAMESPACE}' déjà existant"
else
    kubectl create namespace ${ARGOCD_NAMESPACE}
    log_success "Namespace '${ARGOCD_NAMESPACE}' créé"
fi
 
# Namespace dev
if kubectl get namespace ${DEV_NAMESPACE} &> /dev/null; then
    log_warn "Namespace '${DEV_NAMESPACE}' déjà existant"
else
    kubectl create namespace ${DEV_NAMESPACE}
    log_success "Namespace '${DEV_NAMESPACE}' créé"
fi
 
# =============================================================================
# 8. INSTALLATION DE ARGOCD DANS LE CLUSTER
# =============================================================================
 
log_info "Installation d'ArgoCD dans le namespace '${ARGOCD_NAMESPACE}'..."
 
kubectl apply -n ${ARGOCD_NAMESPACE} \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
 
log_info "Attente que les pods ArgoCD soient prêts..."
kubectl wait --for=condition=available \
    --timeout=300s \
    deployment/argocd-server \
    -n ${ARGOCD_NAMESPACE}
 
log_success "ArgoCD installé et prêt"
 
# =============================================================================
# 9. EXPOSITION D'ARGOCD (port-forward en arrière-plan)
# =============================================================================
 
log_info "Exposition de l'interface ArgoCD sur le port 8080..."
 
# Tuer un éventuel port-forward existant
pkill -f "port-forward.*argocd" 2>/dev/null || true
sleep 2
 
kubectl port-forward svc/argocd-server \
    -n ${ARGOCD_NAMESPACE} \
    8080:443 &>/dev/null &
 
log_success "ArgoCD accessible sur https://localhost:8080"
 
# =============================================================================
# 10. RECUPERATION DU MOT DE PASSE ARGOCD
# =============================================================================
 
log_info "Récupération du mot de passe admin ArgoCD..."
sleep 5  # Laisser le temps au secret d'être créé
 
ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
    get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
 
log_success "Mot de passe ArgoCD récupéré"
 
# =============================================================================
# 11. CONNEXION ET CONFIGURATION DE L'APPLICATION ARGOCD
# =============================================================================
 
log_info "Connexion à ArgoCD..."
sleep 5
 
argocd login localhost:8080 \
    --username admin \
    --password "${ARGOCD_PASSWORD}" \
    --insecure
 
log_info "Création de l'application ArgoCD pointant sur GitHub..."
 
argocd app create wil-playground \
    --repo "https://github.com/houbeid/IOT" \
    --path "p3/confs" \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace dev \
    --sync-policy automated \
    --auto-prune \
    --self-heal \
    --insecure
 
log_success "Application ArgoCD configurée"
 
# Synchronisation manuelle initiale
argocd app sync wil-playground --insecure 2>/dev/null || true
 
# =============================================================================
# 12. VERIFICATION FINALE
# =============================================================================
 
log_info "Vérification de l'installation..."
echo ""
echo "=========================================="
echo "  Namespaces"
echo "=========================================="
kubectl get ns
 
echo ""
echo "=========================================="
echo "  Pods dans '${DEV_NAMESPACE}'"
echo "=========================================="
kubectl get pods -n ${DEV_NAMESPACE}
 
echo ""
echo "=========================================="
echo "  Pods dans '${ARGOCD_NAMESPACE}'"
echo "=========================================="
kubectl get pods -n ${ARGOCD_NAMESPACE}
 
# =============================================================================
# RESUME FINAL
# =============================================================================
 
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Installation terminée avec succès !      ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  ${BLUE}ArgoCD UI${NC}       → https://localhost:8080"
echo -e "  ${BLUE}Login${NC}           → admin"
echo -e "  ${BLUE}Password${NC}        → ${ARGOCD_PASSWORD}"
echo -e "  ${BLUE}Application${NC}     → http://localhost:${APP_PORT}"
echo -e "  ${BLUE}GitHub repo${NC}     → ${GITHUB_REPO}"
echo ""
echo -e "${YELLOW}N'oublie pas de modifier GITHUB_REPO dans ce script !${NC}"
echo ""
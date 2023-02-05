#k8s sa,role,secret
k apply -f /Users/gvr/Projects/YAML/vault-k8s/sa-vault.yaml

k get sa vault-auth-sa
k get clusterrolebinding secret-reader-binding
k describe clusterrolebinding secret-reader-binding
k get secret vault-auth-secret

#secret name
export K8S_SECRET=$(kubectl get secrets --output=json \
    | jq -r '.items[].metadata | select(.name|startswith("vault-auth-")).name')
echo $K8S_SECRET

#token
export K8S_TOKEN=$(k get secret vault-auth-secret -o jsonpath="{.data.token}" | base64 -d)
echo $K8S_TOKEN

#ca cert
export K8S_CA_CRT=$(k get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')
export K8S_CA_CRT=$(k get secret vault-auth-secret -o jsonpath="{.data['ca\.crt']}" | base64 -d )
export K8S_CA_CRT=$(k config view --raw -o 'jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode )
echo $K8S_CA_CRT 

#host
export K8S_HOST=$(k config view --raw -o 'jsonpath={.clusters[].cluster.server}')
echo $K8S_HOST 
# ---------------------
#create valut k8s auth
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt=$K8S_TOKEN \
    kubernetes_host=$K8S_HOST \
    kubernetes_ca_cert=$K8S_CA_CRT \
    disable_local_ca_jwt=true

vault read auth/kubernetes/config

#create valut secret, secret policy
vault secrets enable -path=/secret kv
vault kv put secret/db-pass pwd="admin@123"
vault kv get secret/db-pass

vault policy write internal-app - <<EOF
path "secret/db-pass" {
  capabilities = ["read"]
}
EOF
vault policy read internal-app

# k create sa webapp-sa

vault write auth/kubernetes/role/database \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=default \
    policies=internal-app \
    ttl=20m

vault read auth/kubernetes/role/database
# ---------------------
# Install Secret store CSI driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm upgrade -i csi secrets-store-csi-driver/secrets-store-csi-driver --set syncSecret.enabled=true \
    --set enableSecretRotation=true --set rotationPollInterval=30s --set syncSecret.enabled=true

k get ds
k api-resources | grep -i csi
k get csidriver
k get csinodes
k get po

# Install Valut CSI Provider
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
    --set "server.enabled=false" \
    --set "injector.enabled=false" \
    --set "csi.enabled=true"

k apply -f /Users/gvr/Projects/YAML/vault-k8s/spc-crd-vault.yaml

k api-resources | grep -i secret
k get secretproviderclasses
k describe secretproviderclasses vault-database

#pod which mounts valut secret
k apply -f /Users/gvr/Projects/YAML/vault-k8s/webapp.yaml

#export VAULT_TOKEN=$(vault print token)

# test k8s calls
k run debug-tool --image=wbitt/network-multitool

curl -H "X-Vault-Token: hvs.*********" \
    -X LIST http://192.168.10.10:8200/v1/auth/kubernetes/role | jq

curl -X POST \
    --data '{"role": "database","jwt": $K8S_TOKEN }' \
    http://192.168.10.10:8200/v1/auth/kubernetes/login

curl -H "X-Vault-Request: true" \
    -H "X-Vault-Token: hvs.DfEsZbi6K9HWzhiBPVIcRypG" \
    http://192.168.10.10:8200/v1/secret/db-pass



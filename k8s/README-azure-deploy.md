# Deploying Spring PetClinic to AKS (using provided resources)

This document contains commands and manifests to build the container image, push it to ACR, and deploy to AKS using Workload Identity.

Prereqs (already provided in your env):
- `RESOURCE_GROUP_NAME`, `AKS_CLUSTER_NAME`, `ACR_NAME`, `ACR_LOGIN_SERVER`
- `POSTGRES_SERVER_FQDN`, `POSTGRES_DATABASE_NAME`, `USER_ASSIGNED_IDENTITY_RESOURCE_ID`, `USER_ASSIGNED_IDENTITY_CLIENT_ID`

Basic commands (copy & run):

```bash
# 1) Get AKS credentials
${AKS_GET_CREDENTIALS}

# 2) Login to ACR
${ACR_LOGIN}

# 3) Build & push image (local docker)
docker build -t ${ACR_LOGIN_SERVER}/spring-petclinic:latest .
docker push ${ACR_LOGIN_SERVER}/spring-petclinic:latest

# 4) Ensure AKS can pull from ACR
az aks update --name ${AKS_CLUSTER_NAME} --resource-group ${RESOURCE_GROUP_NAME} --attach-acr ${ACR_NAME}

# 5) Apply k8s resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccount.yaml
# Create federated credential for the user-assigned identity (requires OIDC issuer)
OIDC_ISSUER=$(az aks show -g ${RESOURCE_GROUP_NAME} -n ${AKS_CLUSTER_NAME} --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo "OIDC issuer: $OIDC_ISSUER"

# Replace subject if namespace or SA name differ
az identity federated-credential create \
  --name petclinic-federated-cred \
  --identity-name $(basename ${USER_ASSIGNED_IDENTITY_RESOURCE_ID}) \
  --resource-group ${RESOURCE_GROUP_NAME} \
  --issuer $OIDC_ISSUER \
  --subject "system:serviceaccount:petclinic:petclinic-sa"

# 6) Deploy app
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
# Optional: apply ingress if you have ingress controller + DNS
kubectl apply -f k8s/ingress.yaml
```

Notes:
- Replace `petclinic.example.com` in `k8s/ingress.yaml` with your DNS name and configure TLS as needed.
- Ensure the user-assigned managed identity has database permissions or create a database user mapped to that identity.
- The manifests use env vars embedded in Deployment; you may prefer Kubernetes Secrets or ConfigMaps for better management.

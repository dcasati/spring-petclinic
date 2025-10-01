# Workload Identity Setup Guide (Without Service Connector)

This guide shows you how to manually set up Azure Workload Identity for the PetClinic application to connect to Azure Database for PostgreSQL using Entra ID (AAD) authentication.

## Prerequisites

Based on your current environment:
- **Resource Group**: `petclinic-workshop-rg`
- **AKS Cluster**: `aks-petclinic-py2t5evhiqdr4`
- **PostgreSQL Server**: `postgres-petclinic-py2t5evhiqdr4.postgres.database.azure.com`
- **Database**: `petclinic`
- **Namespace**: `default`
- **Tenant ID**: `de060cb6-6b37-489b-8a6e-c078c6dbeb09`
- **OIDC Issuer**: `https://westus3.oic.prod-aks.azure.com/de060cb6-6b37-489b-8a6e-c078c6dbeb09/7164c9b2-8642-434d-a710-7a617af30fed/`

## Current Setup (Service Connector Created)

Your existing resources:
- **Managed Identity**: `petclinic-app-uami-yqkjlqj5mgv34`
- **Client ID**: `79bfdfb1-54f2-4b58-9bdf-5545c12b4793`
- **Principal ID**: `e9e1d347-3106-4393-bc5f-c6b21f37f69c`
- **Service Account**: `sc-account-79bfdfb1-54f2-4b58-9bdf-5545c12b4793`
- **Federated Credential**: `sc_t5evhiqdr4_default` (for default namespace)

## Architecture Components

### 1. Azure Managed Identity
A User-Assigned Managed Identity that represents your application in Azure.

### 2. Federated Identity Credential
Links the Azure Managed Identity to the Kubernetes Service Account using OIDC.

### 3. Kubernetes Service Account
A service account in your AKS cluster that pods use to authenticate.

### 4. PostgreSQL Database Role
A database user mapped to the Managed Identity's principal ID.

---

## Step-by-Step Setup (From Scratch)

If you want to recreate this setup without Service Connector:

### Step 1: Create User-Assigned Managed Identity

```bash
# Set variables
RESOURCE_GROUP="petclinic-workshop-rg"
LOCATION="westus3"
IDENTITY_NAME="petclinic-workload-identity"

# Create the managed identity
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --location $LOCATION

# Get the identity details
export CLIENT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query clientId -o tsv)

export PRINCIPAL_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query principalId -o tsv)

echo "Client ID: $CLIENT_ID"
echo "Principal ID: $PRINCIPAL_ID"
```

### Step 2: Get AKS OIDC Issuer URL

```bash
AKS_CLUSTER_NAME="aks-petclinic-py2t5evhiqdr4"

# Get the OIDC issuer URL
export OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

echo "OIDC Issuer: $OIDC_ISSUER"

# If OIDC is not enabled, enable it:
# az aks update -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME --enable-oidc-issuer
```

### Step 3: Create Kubernetes Service Account

```bash
# Set variables
NAMESPACE="default"
SERVICE_ACCOUNT_NAME="petclinic-sa"

# Create the service account YAML
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
  annotations:
    azure.workload.identity/client-id: $CLIENT_ID
  labels:
    azure.workload.identity/use: "true"
EOF

# Verify
kubectl get sa $SERVICE_ACCOUNT_NAME -n $NAMESPACE
```

### Step 4: Create Federated Identity Credential

This links the Azure Managed Identity to the Kubernetes Service Account:

```bash
FEDERATED_CREDENTIAL_NAME="petclinic-federated-credential"

az identity federated-credential create \
  --name $FEDERATED_CREDENTIAL_NAME \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer $OIDC_ISSUER \
  --subject "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}"

# Verify
az identity federated-credential show \
  --name $FEDERATED_CREDENTIAL_NAME \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP
```

**Important**: The subject must match exactly: `system:serviceaccount:<namespace>:<service-account-name>`

### Step 5: Grant PostgreSQL Database Permissions

Create a database role for the managed identity:

```bash
PG_SERVER="postgres-petclinic-py2t5evhiqdr4"
PG_DATABASE="petclinic"

# Get PostgreSQL admin token (you need to be logged in as AAD admin)
# Connect to PostgreSQL and run:
```

SQL to run on PostgreSQL (as AAD admin):

```sql
-- Connect to the petclinic database
\c petclinic

-- Create the AAD user using the Managed Identity's Principal ID
-- Replace with your actual PRINCIPAL_ID
SET aad_validate_oids_in_tenant = off;

CREATE ROLE "petclinic-workload-identity" WITH LOGIN IN ROLE azure_pg_admin;

-- Or if using the principal ID directly:
CREATE ROLE "e9e1d347-3106-4393-bc5f-c6b21f37f69c" WITH LOGIN IN ROLE azure_pg_admin;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE petclinic TO "e9e1d347-3106-4393-bc5f-c6b21f37f69c";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "e9e1d347-3106-4393-bc5f-c6b21f37f69c";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "e9e1d347-3106-4393-bc5f-c6b21f37f69c";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "e9e1d347-3106-4393-bc5f-c6b21f37f69c";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "e9e1d347-3106-4393-bc5f-c6b21f37f69c";
```

**Note**: The database username should be the **Principal ID** (object ID) of the managed identity, not the client ID.

### Step 6: Update Deployment to Use Workload Identity

Update your deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-deployment
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: petclinic
  template:
    metadata:
      labels:
        app: petclinic
        azure.workload.identity/use: "true"  # Important!
    spec:
      serviceAccountName: petclinic-sa  # Use your service account
      containers:
      - name: petclinic
        image: <your-acr>.azurecr.io/petclinic:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "postgres"
        - name: DATABASE
          value: "postgres"
        - name: AZURE_CLIENT_ID
          value: "<CLIENT_ID>"  # Your managed identity client ID
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres-petclinic-py2t5evhiqdr4.postgres.database.azure.com:5432/petclinic?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"
        - name: SPRING_DATASOURCE_USERNAME
          value: "<PRINCIPAL_ID>"  # The database username (Principal ID)
        - name: SPRING_DATASOURCE_PASSWORD
          value: ""  # Leave empty for AAD auth
```

### Step 7: Verify the Setup

```bash
# Check if the service account has the correct annotations
kubectl get sa $SERVICE_ACCOUNT_NAME -n $NAMESPACE -o yaml

# Check pod logs
kubectl logs -l app=petclinic -n $NAMESPACE

# Test database connection from within the pod
kubectl exec -it <pod-name> -n $NAMESPACE -- bash
# Inside the pod, check if AZURE_CLIENT_ID is set
env | grep AZURE
```

---

## Using Your Current Setup

Since Service Connector already created everything, you can simply reference the existing resources:

```bash
# Your existing values:
export CLIENT_ID="79bfdfb1-54f2-4b58-9bdf-5545c12b4793"
export PRINCIPAL_ID="e9e1d347-3106-4393-bc5f-c6b21f37f69c"
export SERVICE_ACCOUNT_NAME="sc-account-79bfdfb1-54f2-4b58-9bdf-5545c12b4793"
export IDENTITY_NAME="petclinic-app-uami-yqkjlqj5mgv34"
```

**Your deployment already references these correctly!**

---

## Key Components Explained

### 1. **Service Account Annotation**
```yaml
annotations:
  azure.workload.identity/client-id: <CLIENT_ID>
```
This tells Azure Workload Identity which managed identity to use.

### 2. **Pod Label**
```yaml
labels:
  azure.workload.identity/use: "true"
```
This enables the workload identity mutating webhook to inject the necessary tokens.

### 3. **Federated Credential Subject**
```
system:serviceaccount:<namespace>:<service-account-name>
```
This must match exactly for the trust relationship to work.

### 4. **Database Username**
The PostgreSQL username must be the **Principal ID** (Object ID) of the managed identity, not the Client ID.

---

## Troubleshooting

### Check Federated Credential
```bash
az identity federated-credential list \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  -o table
```

### Check Pod Identity
```bash
kubectl describe pod <pod-name> -n $NAMESPACE
# Look for environment variables: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_FEDERATED_TOKEN_FILE
```

### Check Database Roles
```sql
-- Connect to PostgreSQL and check:
\du
SELECT * FROM pg_roles WHERE rolname = '<PRINCIPAL_ID>';
```

### Common Issues

1. **Authentication fails**: Check that the Principal ID matches the database username
2. **Federated credential not found**: Verify the subject matches the service account
3. **Token not injected**: Ensure the pod has the label `azure.workload.identity/use: "true"`
4. **Permission denied**: Verify the database role has the necessary grants

---

## Clean Up Service Connector Resources (Optional)

If you want to clean up and create fresh resources:

```bash
# Delete federated credentials created by Service Connector
az identity federated-credential delete \
  --name sc_t5evhiqdr4_default \
  --identity-name petclinic-app-uami-yqkjlqj5mgv34 \
  --resource-group petclinic-workshop-rg

# Delete Kubernetes secret and service account
kubectl delete secret sc-pg-secret -n default
kubectl delete sa sc-account-79bfdfb1-54f2-4b58-9bdf-5545c12b4793 -n default

# Then follow the steps above to create new ones
```

---

## References

- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/docs/)
- [PostgreSQL Flexible Server AAD Authentication](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-configure-sign-in-azure-ad-authentication)
- [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)

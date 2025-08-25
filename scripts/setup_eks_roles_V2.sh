#!/usr/bin/env bash
set -euo pipefail

# =========[ Parámetros ]=========
CLUSTER_ROLE_NAME="eks-cluster-role"
NODE_ROLE_NAME="eks-node-role"
INSTANCE_PROFILE_NAME="eks-node-instance-profile"
AUTOSCALER_POLICY_NAME="ClusterAutoscalerPolicy"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# =========[ Utilidades ]=========
exists_role () { aws iam get-role --role-name "$1" >/dev/null 2>&1; }
attach_if_missing () {
  local role="$1" policy_arn="$2"
  if ! aws iam list-attached-role-policies --role-name "$role" \
      --query "AttachedPolicies[?PolicyArn=='${policy_arn}'] | length(@)" --output text | grep -q "^1$"; then
    echo "Adjuntando $policy_arn a $role ..."
    aws iam attach-role-policy --role-name "$role" --policy-arn "$policy_arn"
  else
    echo "Ya estaba adjunta $policy_arn a $role"
  fi
}

# =========[ 1) Rol del CLÚSTER EKS ]=========
CLUSTER_TRUST_FILE="$(mktemp)"
cat > "$CLUSTER_TRUST_FILE" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": [ "sts:AssumeRole", "sts:TagSession" ]
    }
  ]
}
JSON

if exists_role "$CLUSTER_ROLE_NAME"; then
  echo "Rol $CLUSTER_ROLE_NAME ya existe. Actualizando política de confianza (incluye sts:TagSession)..."
  aws iam update-assume-role-policy \
    --role-name "$CLUSTER_ROLE_NAME" \
    --policy-document "file://${CLUSTER_TRUST_FILE}"
else
  echo "Creando rol $CLUSTER_ROLE_NAME ..."
  aws iam create-role \
    --role-name "$CLUSTER_ROLE_NAME" \
    --assume-role-policy-document "file://${CLUSTER_TRUST_FILE}"
  aws iam wait role-exists --role-name "$CLUSTER_ROLE_NAME"
fi

# Políticas RECOMENDADAS para modo automático de EKS + ClusterPolicy
CLUSTER_POLICIES=(
  arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  arn:aws:iam::aws:policy/AmazonEKSComputePolicy
  arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy
  arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy
  arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy
)
for p in "${CLUSTER_POLICIES[@]}"; do attach_if_missing "$CLUSTER_ROLE_NAME" "$p"; done

# =========[ 2) Rol de NODOS (EC2) ]=========
NODE_TRUST_FILE="$(mktemp)"
cat > "$NODE_TRUST_FILE" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

if exists_role "$NODE_ROLE_NAME"; then
  echo "Rol $NODE_ROLE_NAME ya existe."
else
  echo "Creando rol $NODE_ROLE_NAME ..."
  aws iam create-role \
    --role-name "$NODE_ROLE_NAME" \
    --assume-role-policy-document "file://${NODE_TRUST_FILE}"
  aws iam wait role-exists --role-name "$NODE_ROLE_NAME"
fi

# Políticas recomendadas para nodos (Managed Node Groups / EC2)
NODE_POLICIES=(
  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
)
for p in "${NODE_POLICIES[@]}"; do attach_if_missing "$NODE_ROLE_NAME" "$p"; done

# =========[ 3) Instance Profile para nodos ]=========
if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  echo "Creando Instance Profile $INSTANCE_PROFILE_NAME ..."
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"
fi

# Asociar el rol al Instance Profile (si aún no está asociado)
if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --query "InstanceProfile.Roles[?RoleName=='${NODE_ROLE_NAME}'] | length(@)" --output text | grep -q "^1$"; then
  echo "Asociando rol $NODE_ROLE_NAME al Instance Profile $INSTANCE_PROFILE_NAME ..."
  aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$NODE_ROLE_NAME"
else
  echo "El Instance Profile ya incluye el rol $NODE_ROLE_NAME"
fi

# =========[ 4) (Opcional) Política para Cluster Autoscaler ]=========
# Nota: En producción se recomienda IRSA (rol para ServiceAccount) en vez de adjuntar
# al rol de los nodos. Este bloque replica tu enfoque original para mantener compatibilidad.
if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${AUTOSCALER_POLICY_NAME}" >/dev/null 2>&1; then
  echo "Creando política ${AUTOSCALER_POLICY_NAME} ..."
  aws iam create-policy --policy-name "${AUTOSCALER_POLICY_NAME}" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:DescribeTags"
        ],
        "Resource": "*"
      }
    ]
  }'
else
  echo "La política ${AUTOSCALER_POLICY_NAME} ya existe en la cuenta."
fi

attach_if_missing "$NODE_ROLE_NAME" "arn:aws:iam::${ACCOUNT_ID}:policy/${AUTOSCALER_POLICY_NAME}"

# =========[ 5) Resumen ]=========
echo
echo "===== Resumen ====="
echo "Rol de clúster: $CLUSTER_ROLE_NAME"
aws iam list-attached-role-policies --role-name "$CLUSTER_ROLE_NAME" --output table
echo
echo "Rol de nodos: $NODE_ROLE_NAME"
aws iam list-attached-role-policies --role-name "$NODE_ROLE_NAME" --output table
echo
echo "Instance Profile: $INSTANCE_PROFILE_NAME"
aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --output table
echo
echo "¡Listo! Roles y políticas configurados."

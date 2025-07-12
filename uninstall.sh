#!/bin/bash

# Function to show script usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --release-name NAME    Helm release name to uninstall (default: cdp-forge)"
    echo "  -n, --namespace NAMESPACE  Kubernetes namespace (default: cdpforge)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default values"
    echo "  $0 -r my-release                      # Specify release name"
    echo "  $0 -n my-namespace                    # Specify namespace"
    echo "  $0 -r my-release -n my-namespace      # Specify both"
    echo ""
    echo "⚠️  WARNING: This script will delete ALL data in the specified namespace!"
    echo ""
}

# Default values
NAMESPACE="cdpforge"
RELEASE_NAME="cdp-forge"

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo "🗑️ Starting CDP Forge uninstallation..."
echo "📋 Configuration:"
echo "   Release Name: $RELEASE_NAME"
echo "   Namespace:    $NAMESPACE"
echo ""

# User confirmation
echo "⚠️  WARNING: This script will delete ALL data in namespace '$NAMESPACE'!"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Uninstallation cancelled by user"
    exit 1
fi

# Uninstall all involved releases
echo "🔧 Uninstalling Helm releases..."
helm uninstall $RELEASE_NAME -n $NAMESPACE || true
helm uninstall strimzi-kafka-operator -n $NAMESPACE || true

# 1. Disinstallare il release Helm
helm uninstall cert-manager -n cert-manager

# 2. Eliminare il namespace (opzionale)
kubectl delete namespace cert-manager

# 3. Rimuovere le CRDs (Custom Resource Definitions)
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml || true

# Delete ALL Kafka CRDs (warning: you will lose any custom data!)
echo "🗑️ Deleting Kafka CRDs..."
kubectl delete crd $(kubectl get crd | grep kafka | awk '{print $1}') || true

# Delete ALL Strimzi CRDs (warning: you will lose any custom data!)
echo "🗑️ Deleting Strimzi CRDs..."
kubectl delete crd $(kubectl get crd | grep strimzi | awk '{print $1}') || true

# Delete opensearch certs
kubectl delete secret $RELEASE_NAME-opensearch-client-cert -n $NAMESPACE

# Delete all PVCs in the namespace
echo "🗑️ Deleting Kafka and MySQL PVCs in namespace $NAMESPACE..."
kubectl delete pvc -l app.kubernetes.io/name=kafka -n $NAMESPACE || true
kubectl delete pvc -l app.kubernetes.io/name=mysql -n $NAMESPACE || true

# Delete also any orphaned PVCs that might remain
echo "🧹 Cleaning up orphaned PVCs..."
kubectl get pvc -A | grep $NAMESPACE | awk '{print $2}' | xargs -I {} kubectl delete pvc {} -n $NAMESPACE || true
rm certs/os-root-ca.pem

echo "✅ Uninstallation completed successfully!"
echo ""
echo "📊 To verify everything has been removed:"
echo "   kubectl get all -n $NAMESPACE"
echo "   kubectl get pvc -n $NAMESPACE"
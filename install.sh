#!/bin/bash
set -e  # Exit on any error

# Function to show script usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --release-name NAME    Helm release name (default: cdp-forge)"
    echo "  -f, --values-file FILE     Values file to use (default: values.yaml)"
    echo "  -n, --namespace NAMESPACE  Kubernetes namespace (default: cdpforge)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                                  # Use default values"
    echo "  $0 -r my-release                                    # Specify release name"
    echo "  $0 -f custom-values/development.yaml                # Specify values file"
    echo "  $0 -r my-release -f custom-values/development.yaml  # Specify both"
    echo ""
}

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "❌ Error: yq is not installed. Please install yq before running this script."
    exit 1
fi

# Default values
NAMESPACE="cdpforge"
RELEASE_NAME="cdp-forge"
VALUES_FILE="values.yaml"

# Argument parsing
while [ $# -gt 0 ]; do
    case $1 in
        -r|--release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values-file)
            VALUES_FILE="$2"
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

# Validate values file
if [ ! -f "$VALUES_FILE" ]; then
    echo "❌ Values file not found: $VALUES_FILE"
    exit 1
fi

echo "🚀 Starting CDP Forge installation..."
echo "📋 Configuration:"
echo "   Release Name: $RELEASE_NAME"
echo "   Values File:  $VALUES_FILE"
echo "   Namespace:    $NAMESPACE"
echo ""

# 1. Add required repositories
echo "📦 Adding required Helm repositories..."

# Pulsar repository (Pulsar)
helm repo add apache https://pulsar.apache.org/charts || true

# Bitnami repository (MySQL)
helm repo add bitnami https://charts.bitnami.com/bitnami || true

# OpenSearch repository
helm repo add opensearch https://opensearch-project.github.io/helm-charts/ || true

# Jetstack repository (cert-manager)
helm repo add jetstack https://charts.jetstack.io || true

# Update all repositories
helm repo update

# Build deps
helm dependency build

kubectl create namespace $NAMESPACE || true

# 2. Install cert-manager (if not already present)
echo "🔧 Installing cert-manager..."
if helm list -n cert-manager | grep -q "cert-manager"; then
    echo "✅ cert-manager already installed"
else
    echo "📥 Installing cert-manager..."
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.13.3 \
      --set installCRDs=true
    
    echo "⏳ Waiting for cert-manager CRDs to be available..."
    kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s || {
        echo "❌ Timeout waiting for cert-manager pods"
        exit 1
    }
    kubectl wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s || {
        echo "❌ Timeout waiting for cainjector pods"
        exit 1
    }
    kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s || {
        echo "❌ Timeout waiting for webhook pods"
        exit 1
    }
    echo "✅ cert-manager installed successfully"
fi

# 5. Install main chart
echo "📦 Installing main CDP Forge chart..."
if helm list -n $NAMESPACE | grep -q "$RELEASE_NAME"; then
    echo "🔄 Updating existing release..."
    helm upgrade $RELEASE_NAME . -f "$VALUES_FILE" -n $NAMESPACE
else
    echo "🆕 Installing new release..."
    helm install $RELEASE_NAME . -f "$VALUES_FILE" -n $NAMESPACE
fi


echo "✅ Installation completed successfully!"
echo ""
echo "📊 To check status:"
echo "   kubectl get pods -n $NAMESPACE"
echo ""
echo "🔧 To update in the future:"
echo "   $0 -r $RELEASE_NAME -f $VALUES_FILE -n $NAMESPACE"
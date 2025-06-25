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

# Strimzi repository (Kafka)
helm repo add strimzi https://strimzi.io/charts/ || true

# Bitnami repository (MySQL)
helm repo add bitnami https://charts.bitnami.com/bitnami || true

# OpenSearch repository
helm repo add opensearch https://opensearch-project.github.io/helm-charts/ || true

# Update all repositories
helm repo update

# 2. Install Strimzi operator (if not already present)
echo "🔧 Installing Strimzi operator..."
if helm list -n $NAMESPACE | grep -q "strimzi-kafka-operator"; then
    echo "✅ Strimzi operator already installed"
else
    echo "📥 Installing Strimzi operator..."
    helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator -n $NAMESPACE --create-namespace --wait --timeout 5m
    echo "✅ Strimzi operator installed successfully"
fi

# 3. Wait for Strimzi CRDs to be available
echo "⏳ Waiting for Strimzi CRDs to be available..."
kubectl wait --for=condition=established --timeout=120s crd/kafkas.kafka.strimzi.io || {
    echo "❌ Timeout waiting for Kafka CRDs"
    exit 1
}
kubectl wait --for=condition=established --timeout=120s crd/kafkanodepools.kafka.strimzi.io || {
    echo "❌ Timeout waiting for KafkaNodePool CRDs"
    exit 1
}
echo "✅ Strimzi CRDs available"

# 4. Install main chart
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
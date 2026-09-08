#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

NR_K8S_VALUES_PATH="${NR_K8S_VALUES_PATH:-newrelic/k8s/helm/nr-k8s-otel-collector.yaml}"
NR_K8S_RENDERED_PATH="${NR_K8S_RENDERED_PATH:-newrelic/k8s/rendered/nr-k8s-otel-collector.yaml}"

echo "Validating NR K8s chart configuration..."

# Render chart
echo ""
echo "[1/3] Rendering nr-k8s-otel-collector ($NR_K8S_CHART_VERSION)..."

RENDERED=$(mktemp)
CONFIG=$(mktemp)
trap 'rm -f "$RENDERED" "$CONFIG"' EXIT

helm template nr-k8s-otel-collector newrelic/nr-k8s-otel-collector \
    --version "$NR_K8S_CHART_VERSION" \
    -n opentelemetry-demo \
    --create-namespace \
    -f "$NR_K8S_VALUES_PATH" > "$RENDERED"

# Extract collector config from ConfigMap
yq -r 'select(.kind == "ConfigMap" and (.metadata.name | contains("deployment-config"))) | .data | to_entries | .[] | select(.key | contains("config")) | .value' "$RENDERED" > "$CONFIG"

if [ ! -s "$CONFIG" ]; then
    echo "ERROR: Could not extract collector config"
    exit 1
fi

echo "✓ Chart rendered and config extracted"

# Validate with otelcol if available
echo ""
echo "[2/3] Validating config..."

# Runtime-only values the config checks eagerly - stub them so validation
# reflects the config, not the environment it's run in.
export POSTGRES_USERNAME="stub"
export POSTGRES_PASSWORD="stub"
sudo mkdir -p /var/run/secrets/kubernetes.io/serviceaccount
echo "stub" | sudo tee /var/run/secrets/kubernetes.io/serviceaccount/token > /dev/null

if command -v otelcol-contrib &> /dev/null; then
    if ! otelcol-contrib validate --config "$CONFIG" > /dev/null 2>&1; then
        echo "ERROR: otelcol validation failed"
        otelcol-contrib validate --config "$CONFIG"
        exit 1
    fi
    echo "✓ Config valid (otelcol-contrib)"
else
    echo "⊘ otelcol-contrib not available (validation skipped)"
fi

# Verify custom extraConfig present
echo ""
echo "[3/3] Checking custom demo config..."

MISSING=()

# Quick grep checks for required components
grep -q "spanmetrics:" "$CONFIG" || MISSING+=("spanmetrics connector")
grep -q "prometheus/ad:" "$CONFIG" || MISSING+=("prometheus/ad receiver")
grep -q "postgresql:" "$CONFIG" || MISSING+=("postgresql receiver")
grep -q "kafka_metrics:" "$CONFIG" || MISSING+=("kafka_metrics receiver")
grep -q "metrics/spanmetrics:" "$CONFIG" || MISSING+=("metrics/spanmetrics pipeline")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: Missing custom demo config:"
    for item in "${MISSING[@]}"; do
        echo "  ✗ $item"
    done
    exit 1
fi

echo "✓ Custom config present"

# Check rendered file is current
if ! diff -q <(sed 's/[[:space:]]*$//' "$RENDERED" | sed '/^$/d') \
             <(sed 's/[[:space:]]*$//' "$NR_K8S_RENDERED_PATH" | sed '/^$/d') > /dev/null 2>&1; then
    echo ""
    echo "ERROR: Rendered manifest differs from committed"
    echo "Fix: Run newrelic/scripts/update-k8s.sh to re-render"
    exit 1
fi

echo ""
echo "✓ All validations passed"

#!/usr/bin/env bash
set -euo pipefail

NR_K8S_CHART_VERSION="${NR_K8S_CHART_VERSION:-}"
NR_K8S_VALUES_PATH="${NR_K8S_VALUES_PATH:-newrelic/k8s/helm/nr-k8s-otel-collector.yaml}"
NR_K8S_RENDERED_PATH="${NR_K8S_RENDERED_PATH:-newrelic/k8s/rendered/nr-k8s-otel-collector.yaml}"

if [ -z "$NR_K8S_CHART_VERSION" ]; then
    echo "ERROR: NR_K8S_CHART_VERSION not set"
    exit 1
fi

echo "Validating NR K8s chart configuration..."

# Render chart
echo ""
echo "[1/2] Rendering nr-k8s-otel-collector ($NR_K8S_CHART_VERSION)..."

RENDERED=$(mktemp)
CONFIG=$(mktemp)
trap 'rm -f "$RENDERED" "$CONFIG"' EXIT

helm template nr-k8s-otel-collector newrelic/nr-k8s-otel-collector \
    --version "$NR_K8S_CHART_VERSION" \
    -n opentelemetry-demo \
    --create-namespace \
    -f "$NR_K8S_VALUES_PATH" > "$RENDERED"

# Extract collector config from ConfigMap
yq -r 'select(.kind == "ConfigMap" and (.metadata.name | test("otel-collector"))) | .data | to_entries | .[] | select(.key | test("config")) | .value' "$RENDERED" > "$CONFIG"

if [ ! -s "$CONFIG" ]; then
    echo "ERROR: Could not extract collector config"
    exit 1
fi

echo "✓ Chart rendered"

# Validate with otelcol if available (optional)
if command -v otelcol &> /dev/null; then
    if ! otelcol validate --config "$CONFIG" > /dev/null 2>&1; then
        echo "ERROR: Config validation failed"
        otelcol validate --config "$CONFIG"
        exit 1
    fi
    echo "✓ Config syntax valid"
fi

# Compare rendered vs committed
echo ""
echo "[2/2] Checking for stale rendered manifest..."

DIFF=$(diff -u <(sed 's/[[:space:]]*$//' "$NR_K8S_RENDERED_PATH" | sed '/^$/d') \
               <(sed 's/[[:space:]]*$//' "$RENDERED" | sed '/^$/d') || true)

if [ -n "$DIFF" ]; then
    echo "ERROR: Rendered manifest differs from committed"
    echo "This means:"
    echo "  - Chart version changed"
    echo "  - Values changed (including custom extraConfig)"
    echo "  - Something is broken"
    echo ""
    echo "--- committed ($NR_K8S_RENDERED_PATH)"
    echo "+++ freshly rendered"
    echo "$DIFF"
    echo ""
    echo "Fix: Run newrelic/scripts/update-k8s.sh to re-render"
    exit 1
fi

echo "✓ Rendered manifest is current"

echo ""
echo "✓ All validations passed"

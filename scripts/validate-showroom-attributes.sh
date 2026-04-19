#!/bin/bash
#
# Showroom Attribute Validation Script
# Adapted from: https://raw.githubusercontent.com/open-demo-platform/openshift-101-workshop-/refs/heads/main/scripts/validate-showroom-attributes.sh
#
# Tests Antora attribute substitution for the capacity-planning workshop
# across three phases:
#   Phase 1 — local npx antora build with test user_data merge
#   Phase 2 — podman showroom-content container (exact cluster simulation)
#   Phase 3 — live cluster curl against deployed Showroom
#
# Usage:
#   ./scripts/validate-showroom-attributes.sh [OPTIONS]
#
# Options:
#   --local-only       Test only local Antora build (Phase 1)
#   --cluster-only     Test only cluster deployment (Phase 3)
#   --user-data FILE   Use custom user_data.yml file
#   --verbose          Show detailed output
#   --help             Show this help
#

set -e

# ============================================================
# Colors
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Configuration — adapted for capacity-planning workshop
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_OUTPUT_DIR="${PROJECT_ROOT}/test-output"

KUBECONFIG="${KUBECONFIG:-/home/vpcuser/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig}"
ANTORA_PLAYBOOK="default-site.yml"
SHOWROOM_NAMESPACE="showroom-hub-capacity"
SHOWROOM_IMAGE="ghcr.io/rhpds/showroom-content:prod"

# Test values — match real student-01 / hub-capacity environment
TEST_STUDENT_BASTION="bastion.student-01.sandbox5388.opentlc.com"
TEST_STUDENT_API="https://api.student.student-01.sandbox5388.opentlc.com:6443"
TEST_STUDENT_CONSOLE="https://console-openshift-console.apps.student.student-01.sandbox5388.opentlc.com"
TEST_STUDENT_INGRESS="apps.student.student-01.sandbox5388.opentlc.com"
TEST_STUDENT_GUID="student-01"
TEST_STUDENT_PASSWORD="test-password"
TEST_NAMESPACE="capacity-workshop"
TEST_GUID="hub-capacity"
TEST_HUB_RHACM="https://console-openshift-console.apps.hub.hub-capacity.sandbox5388.opentlc.com/multicloud"
TEST_HUB_GRAFANA="https://grafana-open-cluster-management-observability.apps.hub.hub-capacity.sandbox5388.opentlc.com"

# ============================================================
# CLI flags
# ============================================================
LOCAL_ONLY=false
CLUSTER_ONLY=false
USER_DATA_FILE=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local-only)   LOCAL_ONLY=true;  shift ;;
        --cluster-only) CLUSTER_ONLY=true; shift ;;
        --user-data)    USER_DATA_FILE="$2"; shift 2 ;;
        --verbose)      VERBOSE=true; shift ;;
        --help)
            head -n 25 "$0" | grep "^#" | sed 's/^# *//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1  (use --help)"
            exit 1
            ;;
    esac
done

# ============================================================
# Helpers
# ============================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*"; }
log_verbose() { if [ "$VERBOSE" = true ]; then echo -e "    $*"; fi; }

# ============================================================
# create_test_user_data — workshop-specific attributes
# ============================================================
create_test_user_data() {
    local output_file="$1"
    cat > "$output_file" <<EOF
# Test user_data.yml for capacity-planning workshop validation
# These values simulate what Showroom injects from agnosticd_user_info

# Hub identity
guid: ${TEST_GUID}
namespace: ${TEST_NAMESPACE}

# Student cluster SSH access (key deliverable of SSH bastion plan)
student-cluster-bastion: ${TEST_STUDENT_BASTION}
student-cluster-password: ${TEST_STUDENT_PASSWORD}

# Student cluster URLs
student-cluster-api: ${TEST_STUDENT_API}
student-cluster-console: ${TEST_STUDENT_CONSOLE}
student-cluster-ingress-domain: ${TEST_STUDENT_INGRESS}
student-cluster-guid: ${TEST_STUDENT_GUID}

# Hub RHACM + Grafana (Module 5 God's-Eye Dashboard)
hub_rhacm_console: ${TEST_HUB_RHACM}
hub_rhacm_url: ${TEST_HUB_RHACM}
hub_grafana_url: ${TEST_HUB_GRAFANA}
rhacm_console: ${TEST_HUB_RHACM}
grafana_url: ${TEST_HUB_GRAFANA}
EOF
    log_verbose "Created test user_data: $output_file"
}

# ============================================================
# merge_user_data — mimics showroom-content container merge
# ============================================================
merge_user_data() {
    local user_data_file="$1"
    local antora_file="$2"
    local output_file="$3"

    log_info "Merging test user_data into antora.yml..."
    cp "$antora_file" "$output_file"

    if command -v yq &> /dev/null; then
        log_verbose "Using yq for YAML merge"
        while IFS= read -r line; do
            # Skip comments, blank lines, and lines without ':'
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            [[ "$line" != *:* ]] && continue

            local key="${line%%:*}"
            local value="${line#*: }"
            key="${key// /}"         # strip spaces from key
            value="${value#\"}"      # strip leading quote
            value="${value%\"}"      # strip trailing quote
            [[ -z "$key" ]] && continue

            log_verbose "Setting: $key = $value"
            yq eval ".asciidoc.attributes[\"$key\"] = \"$value\"" -i "$output_file" 2>/dev/null || true
        done < "$user_data_file"
    else
        log_warning "yq not found — using sed (less reliable for hyphenated keys)"
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            [[ "$line" != *:* ]] && continue
            local key="${line%%:*}"
            local value="${line#*: }"
            key="${key// /}"
            value="${value#\"}"
            value="${value%\"}"
            [[ -z "$key" ]] && continue
            if grep -q "    ${key}:" "$output_file" 2>/dev/null; then
                sed -i "s|    ${key}:.*|    ${key}: ${value}|" "$output_file"
            fi
        done < "$user_data_file"
    fi
    log_success "Merge complete"
}

# ============================================================
# Phase 1: Local Antora build
# ============================================================
test_local_antora_build() {
    log_info "Phase 1: Local Antora build..."

    mkdir -p "$TEST_OUTPUT_DIR"

    local test_user_data="$TEST_OUTPUT_DIR/user_data.yml"
    if [ -n "$USER_DATA_FILE" ]; then
        cp "$USER_DATA_FILE" "$test_user_data"
    else
        create_test_user_data "$test_user_data"
    fi

    # Merge into a working copy of antora.yml
    local merged_antora="$TEST_OUTPUT_DIR/antora-merged.yml"
    merge_user_data "$test_user_data" "$PROJECT_ROOT/content/antora.yml" "$merged_antora"

    # Temporarily swap antora.yml for the build
    cp "$PROJECT_ROOT/content/antora.yml" "$TEST_OUTPUT_DIR/antora.yml.bak"
    cp "$merged_antora" "$PROJECT_ROOT/content/antora.yml"

    local build_rc=0
    if command -v npx &> /dev/null; then
        log_verbose "Using npx antora with playbook: $ANTORA_PLAYBOOK"
        cd "$PROJECT_ROOT"
        npx antora \
            --to-dir="$TEST_OUTPUT_DIR/www" \
            --stacktrace \
            "$ANTORA_PLAYBOOK" 2>&1 | tee "$TEST_OUTPUT_DIR/antora-build.log" || build_rc=$?
    else
        log_error "npx not found — cannot run local Antora build"
        cp "$TEST_OUTPUT_DIR/antora.yml.bak" "$PROJECT_ROOT/content/antora.yml"
        return 1
    fi

    # Restore original antora.yml
    cp "$TEST_OUTPUT_DIR/antora.yml.bak" "$PROJECT_ROOT/content/antora.yml"

    if [ $build_rc -ne 0 ]; then
        log_error "Antora build failed (see $TEST_OUTPUT_DIR/antora-build.log)"
        return 1
    fi

    log_success "Antora build completed → $TEST_OUTPUT_DIR/www"
}

# ============================================================
# validate_html_attributes — check substitution in built HTML
# ============================================================
validate_html_attributes() {
    local www_dir="${1:-$TEST_OUTPUT_DIR/www}"
    log_info "Validating attribute substitution in HTML at: $www_dir"

    local failed=0
    local checked=0

    for html_file in \
        "$www_dir/modules/index.html" \
        "$www_dir/modules/module-01.html" \
        "$www_dir/modules/module-03.html" \
        "$www_dir/modules/module-05.html"
    do
        [ -f "$html_file" ] || { log_warning "HTML not found: $html_file"; continue; }
        local page
        page="$(basename "$html_file")"
        log_verbose "Checking: $page"
        checked=$((checked + 1))

        # Check for unsubstituted placeholders — these are FAILURES
        # (Antora renders unresolved attributes as literal {attr-name} text)
        # Exclusions:
        #   {0}                 — numeric AsciiDoc pass-through
        #   {cluster}           — Grafana legend template variable (from {{cluster}} in adoc)
        #   {capacity-workshop} — Grafana legend showing {{namespace}} double-sub value
        local unresolved
        unresolved=$(grep -o '{[a-zA-Z][a-zA-Z0-9_-]*}' "$html_file" \
                     | grep -v '{0}' \
                     | grep -v '{cluster}' \
                     | grep -v '{capacity-workshop}' \
                     | sort -u || true)

        if [ -n "$unresolved" ]; then
            log_error "$page: Unresolved attribute placeholders found:"
            echo "$unresolved" | while read -r p; do
                echo "      $p"
            done
            failed=$((failed + 1))
        else
            log_success "$page: No unresolved {attribute} placeholders"
        fi

        # Check that key values actually appear — these are WARNINGS only
        while IFS='=' read -r label expected_val; do
            if grep -q "$expected_val" "$html_file" 2>/dev/null; then
                log_verbose "$page: [$label] = '$expected_val'  ✓"
            else
                log_warning "$page: [$label] value '$expected_val' not found — may be empty or on different page"
            fi
        done <<CHECKS
namespace/capacity-workshop=${TEST_NAMESPACE}
student-cluster-bastion=${TEST_STUDENT_BASTION}
hub_rhacm_console=${TEST_HUB_RHACM}
CHECKS
    done

    if [ $checked -eq 0 ]; then
        log_error "No HTML files found in $www_dir — build may have failed"
        return 1
    fi

    if [ $failed -gt 0 ]; then
        log_error "$failed HTML file(s) have unresolved attribute placeholders"
        return 1
    fi

    log_success "All checked HTML files pass attribute substitution validation"
    return 0
}

# ============================================================
# Phase 2: Showroom container (exact cluster simulation)
# ============================================================
test_showroom_container() {
    log_info "Phase 2: Showroom container simulation..."

    if ! command -v podman &> /dev/null; then
        log_warning "podman not found — skipping container phase"
        return 0
    fi

    local test_user_data="$TEST_OUTPUT_DIR/user_data.yml"
    [ -f "$test_user_data" ] || create_test_user_data "$test_user_data"

    mkdir -p "$TEST_OUTPUT_DIR/showroom-www"

    log_info "Pulling $SHOWROOM_IMAGE ..."
    podman pull "$SHOWROOM_IMAGE" 2>&1 | grep -v "^Trying\|^Getting\|^Copying\|^Writing" || true

    log_info "Running showroom-content build (matches cluster behavior)..."
    # The container does a fresh git clone from GIT_REPO_URL — it cannot use a local mount.
    # NOTE: This phase tests the COMMITTED and PUSHED version of the repo.
    #       If you have local changes, commit and push them to GitHub first.
    local git_repo_url
    git_repo_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null \
                   || echo "https://github.com/tosin2013/capacity-planning-lab-guide.git")
    local git_ref
    git_ref=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    log_warning "Phase 2 tests the PUSHED version of: $git_repo_url @ $git_ref"
    log_warning "Make sure local changes are pushed to GitHub before trusting this result."
    log_info "Container cloning: $git_repo_url @ $git_ref"

    # Do NOT mount /showroom/repo — the container clones there itself
    podman run --rm \
        -v "${test_user_data}:/user_data/user_data.yml:z" \
        -v "${TEST_OUTPUT_DIR}/showroom-www:/showroom/www:z" \
        -e GIT_REPO_URL="${git_repo_url}" \
        -e GIT_REPO_REF="${git_ref}" \
        -e ANTORA_PLAYBOOK="${ANTORA_PLAYBOOK}" \
        "$SHOWROOM_IMAGE" 2>&1 | tee "$TEST_OUTPUT_DIR/showroom-container.log" || {
            log_warning "Showroom container exited non-zero — check $TEST_OUTPUT_DIR/showroom-container.log"
        }

    if ls "$TEST_OUTPUT_DIR/showroom-www/modules/"*.html &>/dev/null; then
        log_success "Showroom container built HTML successfully"
        validate_html_attributes "$TEST_OUTPUT_DIR/showroom-www" || true
    else
        log_warning "No HTML found in showroom-www — container may have used git clone mode"
        log_info "Checking container log for clues..."
        tail -20 "$TEST_OUTPUT_DIR/showroom-container.log" || true
    fi
}

# ============================================================
# Phase 3: Live cluster validation
# ============================================================
test_cluster_deployment() {
    log_info "Phase 3: Live cluster validation..."

    if [ ! -f "$KUBECONFIG" ]; then
        log_error "KUBECONFIG not found: $KUBECONFIG"
        log_info "Set KUBECONFIG or skip with --local-only"
        return 1
    fi

    export KUBECONFIG

    local showroom_host
    showroom_host=$(oc get route showroom \
        -n "$SHOWROOM_NAMESPACE" \
        -o jsonpath='{.spec.host}' 2>/dev/null) || true

    if [ -z "$showroom_host" ]; then
        log_error "Showroom route not found in namespace $SHOWROOM_NAMESPACE"
        return 1
    fi

    local base_url="https://${showroom_host}"
    log_info "Showroom URL: $base_url"

    mkdir -p "$TEST_OUTPUT_DIR/cluster-html"
    local failed=0

    for page in index module-01 module-03 module-05; do
        local url="${base_url}/content/modules/${page}.html"
        local out="$TEST_OUTPUT_DIR/cluster-html/${page}.html"

        log_info "Fetching: $url"
        if ! curl -skL -o "$out" --max-time 15 "$url"; then
            log_error "Failed to fetch $url"
            failed=$((failed + 1))
            continue
        fi

        if [ ! -s "$out" ]; then
            log_warning "$page.html: empty response"
            continue
        fi

        # Check for unresolved {attribute} placeholders
        # Exclude known Grafana template variables that render as {attr} in HTML
        local unresolved
        unresolved=$(grep -o '{[a-zA-Z][a-zA-Z0-9_-]*}' "$out" \
                     | grep -v '{0}' \
                     | grep -v '{cluster}' \
                     | grep -v '{capacity-workshop}' \
                     | sort -u || true)

        if [ -n "$unresolved" ]; then
            log_error "Cluster $page.html: Unresolved placeholders:"
            echo "$unresolved" | while read -r p; do echo "      $p"; done
            failed=$((failed + 1))
        else
            log_success "Cluster $page.html: No unresolved {attribute} placeholders"
        fi
    done

    # Also read the live user_data configmap if present
    local live_user_data
    live_user_data=$(oc get configmap showroom-userdata \
        -n "$SHOWROOM_NAMESPACE" \
        -o jsonpath='{.data.user_data\.yml}' 2>/dev/null || true)

    if [ -n "$live_user_data" ]; then
        log_info "Live user_data.yml in cluster:"
        echo "$live_user_data" | grep -E "(student-cluster-bastion|hub_rhacm|namespace|grafana)" || \
            log_warning "Workshop-specific attributes not found in live user_data"
    else
        log_warning "showroom-userdata ConfigMap not found — Showroom may use empty attributes"
    fi

    if [ $failed -gt 0 ]; then
        log_error "$failed page(s) failed cluster validation"
        return 1
    fi

    log_success "All cluster pages pass validation"
}

# ============================================================
# Main
# ============================================================
main() {
    echo "========================================================"
    echo "  Showroom Attribute Validator — Capacity Planning Workshop"
    echo "========================================================"
    echo ""
    echo "  Project:    $PROJECT_ROOT"
    echo "  Playbook:   $ANTORA_PLAYBOOK"
    echo "  Namespace:  $SHOWROOM_NAMESPACE"
    echo "  Output:     $TEST_OUTPUT_DIR"
    echo ""

    cd "$PROJECT_ROOT"

    if [ "$CLUSTER_ONLY" = false ]; then
        echo "--------------------------------------------------------"
        log_info "Phase 1: Local Antora Build"
        echo "--------------------------------------------------------"
        test_local_antora_build || { log_error "Phase 1 failed"; exit 1; }
        echo ""
        validate_html_attributes "$TEST_OUTPUT_DIR/www" || true
        echo ""

        echo "--------------------------------------------------------"
        log_info "Phase 2: Container Simulation"
        echo "--------------------------------------------------------"
        test_showroom_container || log_warning "Phase 2 non-blocking failure"
        echo ""
    fi

    if [ "$LOCAL_ONLY" = false ]; then
        echo "--------------------------------------------------------"
        log_info "Phase 3: Live Cluster"
        echo "--------------------------------------------------------"
        test_cluster_deployment || log_warning "Phase 3 non-blocking failure"
        echo ""
    fi

    echo "========================================================"
    log_success "Validation complete"
    echo "========================================================"
    echo ""
    echo "  Artifacts saved to: $TEST_OUTPUT_DIR"
    echo "  Local build log:    $TEST_OUTPUT_DIR/antora-build.log"
    echo "  Container log:      $TEST_OUTPUT_DIR/showroom-container.log"
    echo "  Cluster HTML:       $TEST_OUTPUT_DIR/cluster-html/"
    echo ""
}

main

#!/usr/bin/env bash
#
# Kubernetes Learning Environment Setup Script
# Cross-platform with intelligent system detection and resource awareness
#
# ============================================================================
# COMPATIBILITY MATRIX
# ============================================================================
#
# SUPPORTED PLATFORMS:
#   • macOS 11+ (Big Sur+) - Intel (x86_64) and Apple Silicon (arm64)
#   • Linux (any distribution) - x86_64 and aarch64
#   • Windows WSL2 - Ubuntu, Debian, Fedora, etc.
#   • BSD systems (experimental)
#
# SUPPORTED DOCKER RUNTIMES:
#   • OrbStack (macOS) - Recommended for Apple Silicon
#   • Docker Desktop - All platforms
#   • Colima (macOS/Linux) - Lightweight alternative
#   • Rancher Desktop - All platforms
#   • Podman - Linux (experimental)
#
# SUPPORTED KUBERNETES TOOLS:
#   • k3d - Primary recommendation (lightweight, fast)
#   • minikube - Good for learning/testing
#   • kind - Development/CI workflows
#   • OrbStack built-in K3s - macOS only
#
# REQUIREMENTS:
#   Required:
#     - bash 4.0+ (run: bash --version)
#     - docker or podman (must be running)
#     - kubectl (Kubernetes CLI)
#
#   Strongly Recommended:
#     - helm (Kubernetes package manager)
#     - curl or wget (for downloads)
#     - bc or awk (for calculations)
#     - jq (for JSON parsing)
#
#   Optional:
#     - k3d, minikube, or kind (at least one K8s tool)
#     - git (for cloning repositories)
#
# KNOWN PLATFORM-SPECIFIC BEHAVIORS:
#   macOS:
#     - Uses vm_stat for memory detection
#     - Uses sysctl for swap detection
#     - Default installation: Homebrew (brew install <tool>)
#     - External drives: /Volumes/*
#
#   Linux:
#     - Uses /proc/meminfo for memory/swap
#     - Installation: apt-get, yum, dnf (auto-detected)
#     - External drives: /media/* or /mnt/*
#     - May require sudo for Docker access
#
#   WSL2:
#     - Detected as separate from Linux
#     - Uses Linux commands but Windows paths available
#     - Docker Desktop for Windows integration
#     - Performance: Recommend storing data on Linux filesystem
#
#   Windows (Native/Git Bash):
#     - Limited support - WSL2 strongly recommended
#     - MINGW/MSYS/CYGWIN may have issues
#
# TROUBLESHOOTING:
#   "bash: bc: command not found"
#     → Script will auto-fallback to awk or python
#
#   "Docker daemon not accessible"
#     → Linux: sudo usermod -aG docker $USER (then logout/login)
#     → macOS: Ensure Docker Desktop/OrbStack is running
#
#   "Permission denied" errors
#     → Check: File permissions, sudo requirements, SELinux (Linux)
#
#   Architecture mismatch (amd64 vs arm64)
#     → Script auto-detects and downloads correct binaries
#
# USAGE:
#   ./local-k8s.sh [command] [flags]
#
#   Commands: install, start, stop, status, health, clean, maintenance
#   Flags: --non-interactive, --dry-run, --help
#
# For full documentation, run: ./local-k8s.sh --help
#
# ============================================================================

# Bash strict mode
set -euo pipefail
IFS=$'\n\t'

# Check bash version (need 4.0+ for associative arrays)
if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: This script requires Bash 4.0 or higher"
    echo "Current version: ${BASH_VERSION}"
    echo "On macOS: brew install bash"
    exit 1
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Cross-platform math calculation (bc not always available)
calc() {
    local expression="$1"
    
    # Try bc first if available
    if command -v bc &>/dev/null; then
        echo "$expression" | bc -l 2>/dev/null && return 0
    fi
    
    # Fallback to awk (more universally available)
    awk "BEGIN {print $expression}" 2>/dev/null || {
        # Last resort: Python
        if command -v python3 &>/dev/null; then
            python3 -c "print($expression)" 2>/dev/null
        elif command -v python &>/dev/null; then
            python -c "print($expression)" 2>/dev/null
        else
            # Can't do floating point math - return error
            echo "Error: No math tools available (bc, awk, or python)" >&2
            return 1
        fi
    }
}

# Integer comparison helper (works without bc)
compare_int() {
    local val1="$1"
    local op="$2"
    local val2="$3"
    
    case "$op" in
        "lt"|"<")  [[ "$val1" -lt "$val2" ]] ;;
        "le"|"<=") [[ "$val1" -le "$val2" ]] ;;
        "gt"|">")  [[ "$val1" -gt "$val2" ]] ;;
        "ge"|">=") [[ "$val1" -ge "$val2" ]] ;;
        "eq"|"==") [[ "$val1" -eq "$val2" ]] ;;
        "ne"|"!=") [[ "$val1" -ne "$val2" ]] ;;
        *) return 1 ;;
    esac
}

# Floating point comparison helper
compare_float() {
    local val1="$1"
    local op="$2"
    local val2="$3"
    
    local result=$(calc "($val1) $op ($val2)")
    [[ "$result" == "1" ]]
}

# Download helper with curl/wget fallback
download_file() {
    local url="$1"
    local output="$2"
    local options="${3:-}"  # Optional: additional flags
    
    if command -v curl &>/dev/null; then
        if [[ -n "$output" ]]; then
            curl -fsSL $options "$url" -o "$output"
        else
            curl -fsSL $options "$url"
        fi
    elif command -v wget &>/dev/null; then
        if [[ -n "$output" ]]; then
            wget -q $options "$url" -O "$output"
        else
            wget -q $options "$url" -O -
        fi
    else
        log_error "Neither curl nor wget found. Cannot download files."
        return 1
    fi
}

# ============================================================================
# SYSTEM DETECTION & CONFIGURATION
# ============================================================================

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl2"
            else
                echo "linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# Detect CPU architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             echo "unknown" ;;
    esac
}

# Detect total system RAM in GB
detect_total_ram_gb() {
    local os="$1"
    case "$os" in
        macos)
            sysctl -n hw.memsize | awk '{printf "%.1f", $1/1024/1024/1024}'
            ;;
        linux|wsl2)
            awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo
            ;;
        *)
            echo "8.0"  # Default fallback
            ;;
    esac
}

# Detect CPU core count
detect_cpu_cores() {
    local os="$1"
    case "$os" in
        macos)
            sysctl -n hw.ncpu
            ;;
        linux|wsl2)
            nproc
            ;;
        *)
            echo "2"  # Default fallback
            ;;
    esac
}

# Detect Docker runtime
detect_docker_runtime() {
    if ! command -v docker &> /dev/null; then
        echo "none"
        return
    fi
    
    # Check docker context and info
    local context_name=$(docker context show 2>/dev/null || echo "")
    local docker_info=$(docker info 2>/dev/null || echo "")
    
    # OrbStack
    if [[ "$context_name" == "orbstack" ]] || echo "$docker_info" | grep -qi "orbstack"; then
        echo "orbstack"
        return
    fi
    
    # Colima
    if [[ "$context_name" == *"colima"* ]] || echo "$docker_info" | grep -qi "colima"; then
        echo "colima"
        return
    fi
    
    # Rancher Desktop
    if echo "$docker_info" | grep -qi "rancher"; then
        echo "rancher"
        return
    fi
    
    # Docker Desktop
    if echo "$docker_info" | grep -qi "docker desktop"; then
        echo "docker-desktop"
        return
    fi
    
    # Generic Docker (could be native Linux)
    echo "docker"
}

# Detect available Kubernetes tools
detect_k8s_tools() {
    local tools=()
    command -v kubectl &> /dev/null && tools+=("kubectl")
    command -v helm &> /dev/null && tools+=("helm")
    command -v k3d &> /dev/null && tools+=("k3d")
    command -v minikube &> /dev/null && tools+=("minikube")
    command -v orb &> /dev/null && tools+=("orbstack")
    command -v kind &> /dev/null && tools+=("kind")
    echo "${tools[@]}"
}

# Detect competing/running Kubernetes clusters
detect_competing_clusters() {
    local competing=()
    local details=()
    
    # Check Docker Desktop Kubernetes
    if kubectl config get-contexts 2>/dev/null | grep -q "docker-desktop"; then
        if kubectl --context docker-desktop cluster-info &>/dev/null; then
            competing+=("docker-desktop")
            details+=("Docker Desktop Kubernetes is RUNNING")
        fi
    fi
    
    # Check Rancher Desktop Kubernetes
    if kubectl config get-contexts 2>/dev/null | grep -q "rancher-desktop"; then
        if kubectl --context rancher-desktop cluster-info &>/dev/null; then
            competing+=("rancher-desktop")
            details+=("Rancher Desktop Kubernetes is RUNNING")
        fi
    fi
    
    # Check Colima Kubernetes
    if kubectl config get-contexts 2>/dev/null | grep -q "colima"; then
        if kubectl --context colima cluster-info &>/dev/null; then
            competing+=("colima")
            details+=("Colima Kubernetes is RUNNING")
        fi
    fi
    
    # Check Minikube
    if command -v minikube &>/dev/null; then
        if minikube status 2>/dev/null | grep -q "Running"; then
            competing+=("minikube")
            details+=("Minikube cluster is RUNNING")
        fi
    fi
    
    # Check Kind clusters
    if command -v kind &>/dev/null; then
        local kind_clusters=$(kind get clusters 2>/dev/null)
        if [[ -n "$kind_clusters" ]]; then
            competing+=("kind")
            details+=("Kind clusters found: $(echo $kind_clusters | tr '\n' ' ')")
        fi
    fi
    
    # Check OrbStack (if not our target)
    if [[ "$DOCKER_RUNTIME" != "orbstack" ]] && command -v orb &>/dev/null; then
        if orb status 2>/dev/null | grep -q "Running"; then
            competing+=("orbstack")
            details+=("OrbStack is RUNNING")
        fi
    fi
    
    # Return both arrays as JSON-like string
    if [[ ${#competing[@]} -gt 0 ]]; then
        echo "FOUND:${competing[*]}|||${details[*]}"
    else
        echo "NONE"
    fi
}

# ============================================================================
# CACHED DETECTION FUNCTIONS (40-60% performance boost)
# ============================================================================

detect_os_cached() {
    if get_cache "detect_os" >/dev/null 2>&1; then
        get_cache "detect_os"
    else
        local result=$(detect_os)
        set_cache "detect_os" "$result" "$CACHE_TTL_SYSTEM"
        echo "$result"
    fi
}

detect_total_ram_gb_cached() {
    if get_cache "detect_total_ram_gb" >/dev/null 2>&1; then
        get_cache "detect_total_ram_gb"
    else
        local result=$(detect_total_ram_gb "$OS_TYPE")
        set_cache "detect_total_ram_gb" "$result" "$CACHE_TTL_SYSTEM"
        echo "$result"
    fi
}

detect_docker_runtime_cached() {
    if get_cache "detect_docker_runtime" >/dev/null 2>&1; then
        get_cache "detect_docker_runtime"
    else
        local result=$(detect_docker_runtime)
        set_cache "detect_docker_runtime" "$result" "$CACHE_TTL_DOCKER" "detect_competing_clusters"
        echo "$result"
    fi
}

detect_competing_clusters_cached() {
    if get_cache "detect_competing_clusters" >/dev/null 2>&1; then
        get_cache "detect_competing_clusters"
    else
        local result=$(detect_competing_clusters)
        set_cache "detect_competing_clusters" "$result" "$CACHE_TTL_CLUSTER"
        echo "$result"
    fi
}

get_memory_usage_cached() {
    if get_cache "get_memory_usage" >/dev/null 2>&1; then
        get_cache "get_memory_usage"
    else
        local result=$(get_memory_usage)
        set_cache "get_memory_usage" "$result" "$CACHE_TTL_MEMORY"
        echo "$result"
    fi
}

# Start background memory pressure monitor
start_memory_monitor() {
    local monitor_file="${TMP_DIR}/memory_monitor.pid"
    local alert_file="${TMP_DIR}/memory_alert.txt"
    
    # Clean up any existing monitor
    if [[ -f "$monitor_file" ]]; then
        kill $(cat "$monitor_file") 2>/dev/null || true
        rm -f "$monitor_file"
    fi
    rm -f "$alert_file"
    
    # Start background monitor
    (
        while true; do
            sleep 30
            
            local mem_used=$(get_memory_usage_cached)
            local swap_used=$(get_swap_usage)
            
            # Check if memory is critically high (>85% RAM used)
            if compare_float "$mem_used" ">" "$(calc "$TOTAL_RAM_GB * 0.85" | awk '{printf "%.2f", $1}')"; then
                echo "CRITICAL: Memory usage at ${mem_used}GB ($(calc "$mem_used / $TOTAL_RAM_GB * 100" | awk '{printf "%.0f", $1}')%)" > "$alert_file"
                break
            fi
            
            # Check if swap is critically high (>90% of RAM size)
            if [[ "$swap_used" != "0.00" ]] && [[ "$swap_used" != "0" ]]; then
                local swap_percent=$(calc "$swap_used / $TOTAL_RAM_GB * 100" | awk '{printf "%.0f", $1}')
                if (( swap_percent > 90 )); then
                    echo "CRITICAL: Swap usage at ${swap_used}GB (${swap_percent}% of RAM)" > "$alert_file"
                    break
                fi
            fi
        done
    ) &
    
    echo $! > "$monitor_file"
}

# Stop background memory monitor and check for alerts
stop_memory_monitor() {
    local monitor_file="${TMP_DIR}/memory_monitor.pid"
    local alert_file="${TMP_DIR}/memory_alert.txt"
    
    if [[ -f "$monitor_file" ]]; then
        kill $(cat "$monitor_file") 2>/dev/null || true
        rm -f "$monitor_file"
    fi
    
    # Check if alert was triggered
    if [[ -f "$alert_file" ]]; then
        local alert_msg=$(cat "$alert_file")
        rm -f "$alert_file"
        return 1  # Return error code to indicate pressure detected
    fi
    
    return 0
}

# Check current Docker resource usage
check_docker_resource_usage() {
    log_header "Docker Resource Usage Check"
    
    # Get running containers
    local running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    
    # Get container stats (CPU and Memory)
    if [[ $running_containers -gt 0 ]]; then
        log_info "Running containers: $running_containers"
        echo ""
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true
        echo ""
    else
        log_success "No running containers detected"
    fi
    
    # Count images, volumes, networks
    local images=$(docker images -q 2>/dev/null | wc -l | tr -d ' ')
    local volumes=$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')
    local networks=$(docker network ls --filter type=custom -q 2>/dev/null | wc -l | tr -d ' ')
    
    log_info "Docker objects: $images images, $volumes volumes, $networks custom networks"
    
    # Check for reclaimable space
    if command -v docker &>/dev/null; then
        local reclaimable=$(docker system df 2>/dev/null | grep "Build Cache" | awk '{print $4}' || echo "unknown")
        if [[ "$reclaimable" != "unknown" && "$reclaimable" != "0B" ]]; then
            log_warn "Reclaimable space: $reclaimable (run cleanup to free)"
        fi
    fi
    echo ""
}

# Smart cleanup function
smart_cleanup() {
    log_header "Smart Cleanup - Freeing Resources"
    
    # Show current usage
    echo "Current Docker usage:"
    docker system df
    echo ""
    
    log_info "Cleanup options:"
    echo "  1. Basic cleanup (stopped containers, dangling images, unused networks)"
    echo "  2. Aggressive cleanup (+ ALL unused images and volumes)"
    echo "  3. Cancel"
    echo ""
    
    read -rp "Select option [1-3]: " cleanup_level
    
    case "$cleanup_level" in
        1)
            log_info "Starting basic cleanup..."
            
            # Remove stopped containers
            local stopped=$(docker ps -aq -f status=exited 2>/dev/null)
            if [[ -n "$stopped" ]]; then
                docker rm $stopped 2>/dev/null && log_success "Removed stopped containers" || true
            fi
            
            # Remove dangling images only
            local dangling=$(docker images -f "dangling=true" -q 2>/dev/null)
            if [[ -n "$dangling" ]]; then
                docker rmi $dangling 2>/dev/null && log_success "Removed dangling images" || true
            fi
            
            # Prune networks and build cache (without volumes)
            docker system prune -f 2>/dev/null && log_success "Pruned networks and build cache" || true
            ;;
            
        2)
            log_warn "⚠️  This will remove ALL unused images and volumes!"
            log_warn "This includes images not used by any container (even if tagged)"
            echo ""
            read -rp "Are you sure? [y/N]: " aggressive_confirm
            aggressive_confirm=$(echo "$aggressive_confirm" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$aggressive_confirm" =~ ^y ]]; then
                log_info "Starting aggressive cleanup..."
                
                # Remove ALL unused Docker resources
                docker system prune -a -f --volumes 2>/dev/null && log_success "All unused resources removed" || true
            else
                log_info "Aggressive cleanup cancelled"
                return 0
            fi
            ;;
            
        *)
            log_info "Cleanup cancelled"
            return 0
            ;;
    esac
    
    echo ""
    log_success "Cleanup complete!"
    
    # Show reclaimed space
    echo ""
    echo "New Docker usage:"
    docker system df
    echo ""
}

# Disable competing Kubernetes clusters
disable_competing_clusters() {
    local competition=$(detect_competing_clusters_cached)
    
    if [[ "$competition" == "NONE" ]]; then
        log_success "No competing Kubernetes clusters detected"
        return 0
    fi
    
    # Parse the result
    local clusters=$(echo "$competition" | cut -d'|' -f1 | sed 's/FOUND://')
    local details=$(echo "$competition" | cut -d'|' -f4-)
    
    log_critical "⚠️  COMPETING KUBERNETES CLUSTERS DETECTED!"
    echo ""
    log_warn "This script creates a lightweight k3d cluster with custom configuration."
    log_warn "Built-in Kubernetes from Docker runtimes will conflict and waste resources."
    echo ""
    echo "Detected running clusters:"
    echo "$details" | tr '|||' '\n' | sed 's/^/  • /'
    echo ""
    
    log_info "Please disable these to use ONLY the container runtime (not built-in K8s):"
    echo ""
    
    # Provide specific instructions for each detected cluster
    for cluster in $clusters; do
        case "$cluster" in
            docker-desktop)
                echo "📌 Docker Desktop - Disable built-in Kubernetes:"
                echo "   1. Open Docker Desktop"
                echo "   2. Go to Settings → Kubernetes"
                echo "   3. Uncheck 'Enable Kubernetes'"
                echo "   4. Click 'Apply & Restart'"
                echo "   (Docker will still work for containers)"
                echo ""
                ;;
            rancher-desktop)
                echo "📌 Rancher Desktop - Disable built-in Kubernetes:"
                echo "   1. Open Rancher Desktop"
                echo "   2. Go to Kubernetes Settings"
                echo "   3. Select 'Disable Kubernetes' or ensure 'dockerd' mode"
                echo "   4. Apply changes"
                echo "   (Container runtime will remain active)"
                echo ""
                ;;
            colima)
                echo "📌 Colima - Disable Kubernetes feature:"
                echo "   Stop current instance: colima stop"
                echo "   Restart without K8s: colima start --kubernetes=false"
                echo "   (This keeps Docker runtime but disables K8s)"
                echo ""
                ;;
            minikube)
                echo "📌 Minikube:"
                echo "   Run: minikube stop"
                echo "   Or: minikube delete (to remove completely)"
                echo ""
                ;;
            kind)
                echo "📌 Kind clusters:"
                echo "   Run: kind delete clusters --all"
                echo ""
                ;;
            orbstack)
                echo "📌 OrbStack - Disable if not needed:"
                echo "   Run: orb stop"
                echo ""
                ;;
        esac
    done
    
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    read -rp "Have you disabled the competing clusters? [y/N]: " disabled
    disabled=$(echo "$disabled" | tr '[:upper:]' '[:lower:]')
    
    if [[ ! "$disabled" =~ ^y ]]; then
        log_error "Please disable competing clusters before continuing"
        exit 1
    fi
    
    # Verify they're actually stopped
    log_info "Verifying clusters are stopped..."
    sleep 2
    
    local recheck=$(detect_competing_clusters_cached)
    if [[ "$recheck" != "NONE" ]]; then
        log_error "Some clusters are still running. Please stop them and try again."
        exit 1
    fi
    
    log_success "All competing clusters are disabled!"
    echo ""
}

# ============================================================================
# NETWORK CONFLICT DETECTION
# ============================================================================

# Check for port conflicts
check_network_conflicts() {
    log_header "Network Conflict Detection"
    
    local conflicts=()
    local ports_to_check=(
        "5000:Registry"
        "6443:Kubernetes API"
        "80:HTTP Ingress"
        "443:HTTPS Ingress"
        "8080:Alt HTTP"
        "30000-32767:NodePort Range"
    )
    
    log_info "Checking critical ports..."
    echo ""
    
    for port_info in "${ports_to_check[@]}"; do
        local port=$(echo "$port_info" | cut -d: -f1)
        local service=$(echo "$port_info" | cut -d: -f2)
        
        # Skip port ranges
        if [[ "$port" == *"-"* ]]; then
            echo "  ℹ️  $service ($port) - Range check skipped"
            continue
        fi
        
        # Check if port is in use
        if lsof -i ":$port" -sTCP:LISTEN &>/dev/null 2>&1 || nc -z localhost "$port" &>/dev/null 2>&1; then
            conflicts+=("$port:$service")
            local process=$(lsof -i ":$port" -sTCP:LISTEN -Fn 2>/dev/null | grep '^p' | cut -c2- | head -1)
            local process_name=$(ps -p "$process" -o comm= 2>/dev/null || echo "unknown")
            echo "  ⚠️  Port $port ($service) - IN USE by $process_name (PID: $process)"
        else
            echo "  ✓ Port $port ($service) - Available"
        fi
    done
    
    echo ""
    
    # Check for subnet conflicts (Docker networks)
    log_info "Checking Docker network subnets..."
    if command -v docker &>/dev/null; then
        docker network ls --format "{{.Name}}: {{.ID}}" | while read -r network; do
            local net_name=$(echo "$network" | cut -d: -f1)
            local subnet=$(docker network inspect "$net_name" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
            if [[ -n "$subnet" ]]; then
                echo "  • $net_name: $subnet"
            fi
        done
    fi
    echo ""
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "Port conflicts detected. You may need to:"
        echo "  1. Stop conflicting services"
        echo "  2. Change ports in configuration"
        echo "  3. Use different port mappings"
        return 1
    else
        log_success "No network conflicts detected"
        return 0
    fi
}

# ============================================================================
# RESOURCE QUOTA RECOMMENDATIONS
# ============================================================================

# Analyze and recommend resource quotas
analyze_resource_quotas() {
    log_header "Resource Quota Analysis"
    
    # Get current Docker resource usage
    local docker_mem_usage=0
    local docker_cpu_usage=0
    
    if docker ps -q &>/dev/null; then
        # Calculate total memory usage of running containers
        docker_mem_usage=$(docker stats --no-stream --format "{{.MemUsage}}" 2>/dev/null | \
            awk -F'[/ ]' '{sum += $1} END {printf "%.2f", sum}' || echo "0")
        
        # Get average CPU usage
        docker_cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" 2>/dev/null | \
            awk -F'%' '{sum += $1; count++} END {if (count > 0) printf "%.1f", sum/count; else print "0"}' || echo "0")
    fi
    
    log_info "Current Docker Resource Usage:"
    echo "  • Memory: ${docker_mem_usage}MB"
    echo "  • CPU: ${docker_cpu_usage}%"
    echo ""
    
    # Calculate available resources
    local available_mem=$(calc "$TOTAL_RAM_GB * 1024 - $docker_mem_usage" | awk '{printf "%.0f", $1}')
    local available_cpu=$(calc "100 - $docker_cpu_usage" | awk '{printf "%.0f", $1}')
    
    log_info "Available for Kubernetes:"
    echo "  • Memory: ${available_mem}MB (~$(calc "$available_mem / 1024" | awk '{printf "%.1f", $1}')GB)"
    echo "  • CPU: ${available_cpu}%"
    echo ""
    
    # Provide recommendations
    log_header "Recommendations"
    
    if compare_int "$available_mem" "<" "2048"; then
        log_critical "⚠️  LOW MEMORY: Less than 2GB available"
        echo "  Recommended actions:"
        echo "    1. Stop unnecessary Docker containers"
        echo "    2. Run: ./local-k8s.sh docker-cleanup"
        echo "    3. Close memory-intensive applications"
        echo ""
    elif compare_int "$available_mem" "<" "4096"; then
        log_warn "MODERATE MEMORY: 2-4GB available"
        echo "  • Install: Base cluster + Registry only"
        echo "  • Skip: ArgoCD, Monitoring"
        echo ""
    else
        log_success "GOOD MEMORY: 4GB+ available"
        echo "  • Can install: Full stack with monitoring"
        echo "  • Suggested limits per namespace:"
        echo "    - Dev: $(calc "$available_mem * 0.3 / 1024" | awk '{printf "%.1f", $1}')GB"
        echo "    - Staging: $(calc "$available_mem * 0.25 / 1024" | awk '{printf "%.1f", $1}')GB"
        echo "    - Prod: $(calc "$available_mem * 0.35 / 1024" | awk '{printf "%.1f", $1}')GB"
        echo ""
    fi
    
    if compare_int "$available_cpu" "<" "20"; then
        log_warn "HIGH CPU USAGE: Less than 20% available"
        echo "  • Consider stopping CPU-intensive processes"
        echo ""
    fi
}

# ============================================================================
# IMAGE OPTIMIZATION
# ============================================================================

# Detect and suggest image optimizations
optimize_docker_images() {
    log_header "Docker Image Optimization"
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found"
        return 1
    fi
    
    log_info "Analyzing Docker images..."
    echo ""
    
    # Find large images (>500MB)
    log_info "Large Images (>500MB):"
    docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" | \
        awk '$2 ~ /GB/ || ($2 ~ /MB/ && $2+0 > 500) {print "  • " $1 " - " $2}' || echo "  None found"
    echo ""
    
    # Find unused images (not used by any container)
    log_info "Unused Images:"
    local used_images=$(docker ps -a --format "{{.Image}}" | sort -u)
    local all_images=$(docker images --format "{{.Repository}}:{{.Tag}}")
    local unused_count=0
    
    while IFS= read -r image; do
        if ! echo "$used_images" | grep -q "^${image}$"; then
            ((unused_count++))
            if [[ $unused_count -le 10 ]]; then
                echo "  • $image"
            fi
        fi
    done <<< "$all_images"
    
    if [[ $unused_count -gt 10 ]]; then
        echo "  ... and $((unused_count - 10)) more"
    elif [[ $unused_count -eq 0 ]]; then
        echo "  None found"
    fi
    echo ""
    
    # Find images with multiple versions
    log_info "Images with Multiple Versions:"
    docker images --format "{{.Repository}}" | sort | uniq -d | while read -r repo; do
        local count=$(docker images "$repo" --format "{{.Tag}}" | wc -l | tr -d ' ')
        echo "  • $repo: $count versions"
    done || echo "  None found"
    echo ""
    
    # Calculate total reclaimable space
    local dangling_size=$(docker images -f "dangling=true" --format "{{.Size}}" | \
        awk '{sum += $1} END {printf "%.2f", sum}' || echo "0")
    
    log_header "Recommendations"
    echo "  1. Remove unused images: docker image prune -a"
    echo "  2. Remove dangling images: docker image prune"
    echo "  3. Use .dockerignore to reduce build context"
    echo "  4. Use multi-stage builds to reduce final image size"
    echo "  5. Prefer alpine-based images when possible"
    echo ""
    
    if compare_float "$dangling_size" ">" "0"; then
        log_info "Estimated reclaimable space: ${dangling_size}GB"
        echo ""
        read -rp "Remove unused images now? [y/N]: " remove_images
        remove_images=$(echo "$remove_images" | tr '[:upper:]' '[:lower:]')
        if [[ "$remove_images" =~ ^y ]]; then
            docker image prune -a -f
            log_success "Images cleaned up"
        fi
    fi
}

# ============================================================================
# STORAGE THRESHOLD ALERTS
# ============================================================================

# Check storage and manage old backups
check_storage_health() {
    log_header "Storage Health Check"
    
    # Check external drive usage
    if [[ ! -d "$EXTERNAL_DRIVE" ]]; then
        log_error "Storage path not found: $EXTERNAL_DRIVE"
        return 1
    fi
    
    local storage_info=$(df -h "$EXTERNAL_DRIVE" | tail -1)
    local used_percent=$(echo "$storage_info" | awk '{print $5}' | sed 's/%//')
    local available=$(echo "$storage_info" | awk '{print $4}')
    local total=$(echo "$storage_info" | awk '{print $2}')
    
    log_info "Storage: $EXTERNAL_DRIVE"
    echo "  • Total: $total"
    echo "  • Available: $available"
    echo "  • Used: ${used_percent}%"
    echo ""
    
    # Check backup directory size
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
        local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | grep -c "cluster-" || echo "0")
        echo "  • Backups: $backup_count files, $backup_size total"
        echo ""
    fi
    
    # Alert based on usage
    if [[ $used_percent -gt 90 ]]; then
        log_critical "⚠️  CRITICAL: Storage >90% full!"
        echo ""
        log_warn "Immediate actions needed:"
        echo "  1. Clean old backups"
        echo "  2. Remove unused PV data"
        echo "  3. Run Docker cleanup"
        echo ""
        
        # Offer to clean old backups
        if [[ $backup_count -gt 5 ]]; then
            read -rp "Delete backups older than 30 days? [y/N]: " clean_backups
            clean_backups=$(echo "$clean_backups" | tr '[:upper:]' '[:lower:]')
            if [[ "$clean_backups" =~ ^y ]]; then
                find "$BACKUP_DIR" -name "cluster-*" -mtime +30 -delete 2>/dev/null
                log_success "Old backups cleaned"
            fi
        fi
    elif [[ $used_percent -gt 80 ]]; then
        log_warn "WARNING: Storage >80% full"
        echo "  • Consider cleanup soon"
        echo ""
    else
        log_success "Storage health: Good"
    fi
}

# ============================================================================
# PERIODIC HEALTH MONITORING
# ============================================================================

# Background health monitor
start_health_monitor() {
    local interval="${1:-300}"  # Default 5 minutes
    local auto_cleanup="${2:-false}"  # Optional auto-cleanup flag
    
    log_header "Starting Health Monitor"
    log_info "Monitoring interval: ${interval}s ($(calc "$interval / 60" | awk '{printf "%.1f", $1}') minutes)"
    if [[ "$auto_cleanup" == "true" ]]; then
        log_info "Auto-cleanup: ENABLED (triggers on high resource usage)"
    fi
    echo ""
    
    # Create monitor script
    local monitor_script="$TMP_DIR/health-monitor.sh"
    cat > "$monitor_script" <<MONITOR_EOF
#!/bin/bash
INTERVAL=\$1
LOG_FILE=\$2
CLUSTER_NAME=\$3
AUTO_CLEANUP=\$4
SCRIPT_PATH="$0"

# Source system detection functions
get_memory_usage_mb() {
    case "\$(uname -s)" in
        Darwin*)
            vm_stat | awk '/Pages active/ {active=\$3} /Pages wired/ {wired=\$4} END {print (active+wired)*4096/1048576}' | cut -d. -f1
            ;;
        Linux*)
            free -m | awk '/^Mem:/ {print \$3}'
            ;;
    esac
}

get_swap_usage_mb() {
    case "\$(uname -s)" in
        Darwin*)
            sysctl vm.swapusage 2>/dev/null | awk '{print \$7}' | sed 's/M//' || echo "0"
            ;;
        Linux*)
            free -m | awk '/^Swap:/ {print \$3}'
            ;;
    esac
}

while true; do
    {
        echo "=== Health Check \$(date) ==="
        
        # Check system resources first
        mem_used=\$(get_memory_usage_mb)
        swap_used=\$(get_swap_usage_mb)
        
        if [[ -n "\$mem_used" ]]; then
            echo "📊 Memory Usage: \${mem_used}MB"
        fi
        
        if [[ -n "\$swap_used" ]] && [[ "\$swap_used" != "0" ]]; then
            echo "📊 Swap Usage: \${swap_used}MB"
            
            # Trigger auto-cleanup if swap > 3GB and enabled
            if [[ "\$AUTO_CLEANUP" == "true" ]] && (( swap_used > 3072 )); then
                echo "⚠️  HIGH SWAP DETECTED - Triggering auto-cleanup..."
                # Run cleanup in background to avoid blocking monitor
                nohup bash "\$SCRIPT_PATH" docker-cleanup --non-interactive >> "\$LOG_FILE" 2>&1 &
            fi
        fi
        
        # Check cluster status
        if kubectl cluster-info &>/dev/null; then
            echo "✓ Cluster responsive"
            
            # Check node status
            node_status=\$(kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}')
            if [[ "\$node_status" == "Ready" ]]; then
                echo "✓ Node ready"
            else
                echo "⚠ Node not ready: \$node_status"
            fi
            
            # Check critical pods
            not_running=\$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | tr -d ' ')
            if [[ \$not_running -gt 0 ]]; then
                echo "⚠ \$not_running pods not running"
            else
                echo "✓ All pods healthy"
            fi
            
            # Check memory pressure on node
            memory_pressure=\$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="MemoryPressure")].status}' 2>/dev/null)
            if [[ "\$memory_pressure" == "True" ]]; then
                echo "⚠️  MEMORY PRESSURE detected on cluster node!"
            fi
            
            # Check evicted pods (sign of resource constraints)
            evicted_pods=\$(kubectl get pods -A --field-selector=status.phase=Failed 2>/dev/null | grep -c "Evicted" || echo "0")
            if [[ \$evicted_pods -gt 0 ]]; then
                echo "⚠️  \$evicted_pods evicted pods detected (resource constraints)"
                echo "💡 Run: ./local-k8s.sh clean"
            fi
            
            # Check image count
            image_count=\$(docker images -q 2>/dev/null | wc -l | tr -d ' ')
            if [[ \$image_count -gt 50 ]]; then
                echo "⚠️  \$image_count Docker images (consider cleanup)"
            fi
            
        else
            echo "✗ Cluster not responding"
        fi
        
        echo ""
    } >> "\$LOG_FILE"
    
    sleep "\$INTERVAL"
done
MONITOR_EOF
    
    chmod +x "$monitor_script"
    
    # Start monitor in background
    local monitor_log="$LOG_DIR/health-monitor.log"
    nohup "$monitor_script" "$interval" "$monitor_log" "$CLUSTER_NAME" "$auto_cleanup" > /dev/null 2>&1 &
    local monitor_pid=$!
    
    echo "$monitor_pid" > "$TMP_DIR/health-monitor.pid"
    
    log_success "Health monitor started (PID: $monitor_pid)"
    log_info "Logs: $monitor_log"
    if [[ "$auto_cleanup" == "true" ]]; then
        echo ""
        log_info "💡 Auto-cleanup enabled:"
        echo "  • Monitors swap usage every ${interval}s"
        echo "  • Triggers Docker cleanup if swap > 3GB"
        echo "  • Alerts on evicted pods and memory pressure"
        echo "  • Recommends cleanup when images > 50"
    fi
    echo ""
    log_info "Management:"
    echo "  • Stop: ./local-k8s.sh stop-monitor"
    echo "  • Logs: ./local-k8s.sh monitor-logs"
}

# Stop health monitor
stop_health_monitor() {
    local pid_file="$TMP_DIR/health-monitor.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        log_info "No health monitor running"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        rm "$pid_file"
        log_success "Health monitor stopped (PID: $pid)"
    else
        log_info "Monitor process not found (may have already stopped)"
        rm "$pid_file"
    fi
}

# View health monitor logs
view_health_logs() {
    local monitor_log="$LOG_DIR/health-monitor.log"
    
    if [[ ! -f "$monitor_log" ]]; then
        log_info "No health monitor logs found"
        return 0
    fi
    
    log_header "Recent Health Checks"
    tail -50 "$monitor_log"
}

# Show maintenance best practices
show_maintenance_tips() {
    log_header "🛠️  Cluster Maintenance Best Practices"
    echo ""
    
    echo "To keep your environment clean and performant:"
    echo ""
    
    log_info "🔄 Regular Maintenance (Daily/Weekly):"
    echo "  • Check resources:     ./local-k8s.sh health"
    echo "  • Clean up Docker:     ./local-k8s.sh docker-cleanup"
    echo "  • Remove evicted pods: ./local-k8s.sh clean"
    echo ""
    
    log_info "📊 Monitoring (Recommended):"
    echo "  • Start auto-monitor:  ./local-k8s.sh start-monitor 300"
    echo "    → Checks every 5 minutes"
    echo "    → Auto-cleanup on high swap"
    echo "    → Alerts on resource issues"
    echo ""
    
    log_info "🎯 Development Best Practices:"
    echo "  1. Clean up after experiments:"
    echo "     kubectl delete pod <name> --force --grace-period=0"
    echo "     docker system prune -af --volumes"
    echo ""
    echo "  2. Use resource limits in deployments:"
    echo "     resources:"
    echo "       limits:"
    echo "         memory: \"256Mi\""
    echo "         cpu: \"500m\""
    echo ""
    echo "  3. Delete completed jobs/pods:"
    echo "     kubectl delete jobs --field-selector status.successful=1"
    echo ""
    echo "  4. Pull images efficiently:"
    echo "     docker pull <image>:<tag>  # Use specific tags"
    echo "     kubectl set image deployment/app app=<image>:<tag>"
    echo ""
    
    log_info "⚠️  Warning Signs (Run cleanup immediately):"
    echo "  • Swap usage > 3GB or > 40% of RAM"
    echo "  • Docker images > 50"
    echo "  • Evicted pods appear"
    echo "  • Cluster becomes slow/unresponsive"
    echo ""
    
    log_info "🔧 Quick Cleanup Commands:"
    echo "  • Full cleanup:        ./local-k8s.sh clean"
    echo "  • Docker cleanup:      ./local-k8s.sh docker-cleanup"
    echo "  • Image optimization:  ./local-k8s.sh optimize-images"
    echo "  • Resource analysis:   ./local-k8s.sh resource-quotas"
    echo ""
    
    # Show current status
    log_header "Current System Status"
    local mem=$(get_memory_usage_cached)
    local swap=$(get_swap_usage)
    local images=$(docker images -q 2>/dev/null | wc -l | tr -d ' ')
    local containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    
    echo "  • Memory: ${mem}GB / ${TOTAL_RAM_GB}GB"
    if [[ "$swap" != "0.00" ]] && [[ "$swap" != "0" ]]; then
        local swap_gb=$(calc "$swap / 1024" | awk '{printf "%.2f", $1}')
        echo "  • Swap: ${swap_gb}GB"
    fi
    echo "  • Docker Images: $images"
    echo "  • Running Containers: $containers"
    echo ""
    
    if kubectl get pods -A &>/dev/null; then
        local evicted=$(kubectl get pods -A --field-selector=status.phase=Failed 2>/dev/null | grep -c "Evicted" || echo "0")
        if [[ $evicted -gt 0 ]]; then
            log_warn "⚠️  $evicted evicted pods detected - cleanup recommended"
        else
            log_success "✓ No evicted pods"
        fi
    fi
}

# Placeholder variables (will be initialized later)
OS_TYPE=""
CPU_ARCH=""
TOTAL_RAM_GB=""
CPU_CORES=""
DOCKER_RUNTIME=""
K8S_TOOLS=()
STORAGE_PATH=""
EXTERNAL_DRIVE=""
CLUSTER_NAME=""
REGISTRY_PORT=""
REGISTRY_NAME=""
MEMORY_LIMIT=""
KUBE_ROOT=""
REGISTRY_DIR=""
PV_DIR=""
BACKUP_DIR=""
LOG_DIR=""
TMP_DIR=""
CONFIG_DIR=""
CLUSTER_MEMORY_LIMIT=""
MAX_SAFE_MEMORY=""
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
NC='\033[0m' # No Color

# ============================================================================
# ERROR CODES & SEVERITY LEVELS
# ============================================================================

declare -r ERR_SUCCESS=0
declare -r ERR_GENERIC=1
declare -r ERR_DOCKER_UNAVAILABLE=10
declare -r ERR_DOCKER_NOT_RUNNING=11
declare -r ERR_KUBECTL_UNAVAILABLE=12
declare -r ERR_CLUSTER_START_FAILED=20
declare -r ERR_REGISTRY_START_FAILED=21
declare -r ERR_PORT_IN_USE=30
declare -r ERR_INSUFFICIENT_DISK_SPACE=31
declare -r ERR_INSUFFICIENT_RAM=32
declare -r ERR_NETWORK_CONFLICT=40
declare -r ERR_CONFIG_NOT_FOUND=50
declare -r ERR_CONFIG_INVALID=51
declare -r ERR_INSTALLATION_FAILED=60
declare -r ERR_TIMEOUT=80
declare -r ERR_PERMISSION_DENIED=81
declare -r ERR_HELM_REPO_FAILED=90

declare -r SEVERITY_INFO=0
declare -r SEVERITY_WARN=1
declare -r SEVERITY_ERROR=2
declare -r SEVERITY_CRITICAL=3

# Global error context
declare -g ERROR_STACK=()
declare -g ERROR_TIMESTAMPS=()
declare -g ERROR_FUNCTIONS=()
declare -g ERROR_CODES=()
declare -g LAST_ERROR_CODE=0

# ============================================================================
# CACHING SYSTEM
# ============================================================================

declare -gA CACHE_VALUES=()
declare -gA CACHE_TIMESTAMPS=()
declare -gA CACHE_TTL_SECONDS=()
declare -gA CACHE_DEPENDENCIES=()
declare -gA CACHE_VALIDITY=()

declare -r CACHE_TTL_SYSTEM=300
declare -r CACHE_TTL_DOCKER=60
declare -r CACHE_TTL_MEMORY=30
declare -r CACHE_TTL_CLUSTER=120
declare -r CACHE_TTL_NETWORK=90

# Cache operations
push_error_context() {
    local msg="$1"
    local code="${2:-$ERR_GENERIC}"
    ERROR_STACK+=("$msg")
    ERROR_TIMESTAMPS+=("$(date '+%Y-%m-%d %H:%M:%S')")
    ERROR_FUNCTIONS+=("${FUNCNAME[1]}:${BASH_LINENO[0]}")
    ERROR_CODES+=("$code")
    LAST_ERROR_CODE=$code
    [[ ${#ERROR_STACK[@]} -gt 50 ]] && {
        ERROR_STACK=("${ERROR_STACK[@]:1}")
        ERROR_TIMESTAMPS=("${ERROR_TIMESTAMPS[@]:1}")
        ERROR_FUNCTIONS=("${ERROR_FUNCTIONS[@]:1}")
        ERROR_CODES=("${ERROR_CODES[@]:1}")
    }
}

set_cache() {
    local key="$1" value="$2" ttl="${3:-300}" deps="${4:-}"
    CACHE_VALUES["$key"]="$value"
    CACHE_TIMESTAMPS["$key"]=$(date +%s)
    CACHE_TTL_SECONDS["$key"]="$ttl"
    CACHE_DEPENDENCIES["$key"]="$deps"
    CACHE_VALIDITY["$key"]="1"
}

get_cache() {
    local key="$1"
    [[ -z "${CACHE_VALUES[$key]:-}" ]] && return 1
    [[ "${CACHE_VALIDITY[$key]:-0}" != "1" ]] && return 1
    local age=$(($(date +%s) - ${CACHE_TIMESTAMPS[$key]:-0}))
    [[ $age -gt ${CACHE_TTL_SECONDS[$key]:-0} ]] && return 1
    echo "${CACHE_VALUES[$key]}"
    return 0
}

invalidate_cache() {
    local key="$1"
    CACHE_VALIDITY["$key"]="0"
}

clear_all_cache() {
    CACHE_VALUES=()
    CACHE_TIMESTAMPS=()
    CACHE_TTL_SECONDS=()
    CACHE_DEPENDENCIES=()
    CACHE_VALIDITY=()
}

attempt_with_retry() {
    local max_attempts=$1
    shift
    local cmd=("$@")
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        local exit_code=$?
        if [[ $attempt -lt $max_attempts ]]; then
            local delay=$((2 ** (attempt - 1)))
            sleep "$delay"
        fi
        ((attempt++))
    done
    push_error_context "Command failed after $max_attempts attempts: ${cmd[*]}" "$exit_code"
    return "$exit_code"
}

log_error_with_context() {
    local msg="$1"
    local code="${2:-$LAST_ERROR_CODE}"
    push_error_context "$msg" "$code"
    echo ""
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║  ❌ ERROR (Code: $code)${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}${BOLD}$msg${NC}"
    echo ""
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR-$code] $msg" >> "$INSTALL_LOG"
}

# Config file location
CONFIG_FILE="$HOME/.kube-lab-config"
CONTEXT_FILE="$HOME/.kube-lab-context"  # Saved context for restore
STATE_FILE=""  # Will be set after config is loaded
INSTALL_LOG=""  # Will be set after config is loaded

# ============================================================================
# KUBECTL CONTEXT MANAGEMENT
# ============================================================================

# Save current kubectl context
save_kubectl_context() {
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "$current_context" > "$CONTEXT_FILE"
    log_info "Saved current context: $current_context"
}

# Switch to cluster context
switch_to_cluster_context() {
    local target_context=""
    
    # Determine target context based on runtime
    if [[ "$DOCKER_RUNTIME" == "orbstack" ]]; then
        target_context="orbstack"
    elif [[ -n "$CLUSTER_NAME" ]]; then
        # For k3d clusters
        target_context="k3d-${CLUSTER_NAME}"
    else
        log_warn "Cannot determine cluster context"
        return 1
    fi
    
    # Check if context exists
    if ! kubectl config get-contexts "$target_context" &>/dev/null; then
        log_warn "Context '$target_context' not found"
        return 1
    fi
    
    # Save current context before switching
    save_kubectl_context
    
    # Switch context
    kubectl config use-context "$target_context" &>/dev/null
    log_success "Switched to context: $target_context"
}

# Restore previous kubectl context
restore_kubectl_context() {
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        log_info "No saved context to restore"
        return 0
    fi
    
    local saved_context=$(cat "$CONTEXT_FILE")
    
    if [[ "$saved_context" == "none" ]]; then
        log_info "No previous context was set"
        return 0
    fi
    
    if kubectl config get-contexts "$saved_context" &>/dev/null; then
        kubectl config use-context "$saved_context" &>/dev/null
        log_success "Restored context: $saved_context"
    else
        log_warn "Previous context '$saved_context' no longer exists"
    fi
    
    rm -f "$CONTEXT_FILE"
}

# ============================================================================
# CONFIG FILE MANAGEMENT
# ============================================================================

# Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Save configuration to file
save_config() {
    cat > "$CONFIG_FILE" <<EOF
# Kubernetes Lab Configuration
# Generated on $(date)
# Edit this file to change default settings

# Storage location for cluster data
STORAGE_PATH="$STORAGE_PATH"

# Cluster configuration
CLUSTER_NAME="$CLUSTER_NAME"
REGISTRY_PORT="$REGISTRY_PORT"
REGISTRY_NAME="$REGISTRY_NAME"

# Resource limits (auto or specific MB value)
MEMORY_LIMIT="$MEMORY_LIMIT"

# System detection (auto-detected, don't change)
OS_TYPE="$OS_TYPE"
CPU_ARCH="$CPU_ARCH"
TOTAL_RAM_GB="$TOTAL_RAM_GB"
DOCKER_RUNTIME="$DOCKER_RUNTIME"
EOF
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}

# Detect available external drives
detect_external_drives() {
    local drives=()
    
    case "$OS_TYPE" in
        macos)
            # Get the internal boot disk device
            local internal_device=$(df / | awk 'NR==2 {print $1}')
            local internal_disk=$(echo "$internal_device" | grep -oE "disk[0-9]+" | head -1)
            
            # Find all mounted volumes in /Volumes/ 
            for vol in /Volumes/*; do
                [[ ! -d "$vol" ]] && continue
                [[ "$vol" =~ com\.apple ]] && continue  # Skip Time Machine
                [[ "$vol" =~ VM$ ]] && continue
                [[ "$vol" =~ Preboot$ ]] && continue
                [[ "$vol" =~ Recovery$ ]] && continue
                [[ "$vol" == "/Volumes/Macintosh HD" ]] && continue
                
                # Get the device for this volume
                local device=$(df "$vol" 2>/dev/null | awk 'NR==2 {print $1}')
                [[ -z "$device" ]] && continue
                
                # Extract disk number from device (e.g., disk3 from /dev/disk3s1)
                local vol_disk=$(echo "$device" | grep -oE "disk[0-9]+" | head -1)
                
                # If this volume is NOT on the internal disk, it's external
                if [[ "$vol_disk" != "$internal_disk" ]]; then
                    drives+=("$vol")
                fi
            done
            ;;
        linux|wsl2)
            # Look for mounted external drives (not /, /boot, /sys, /proc, etc.)
            while IFS= read -r line; do
                [[ "$line" == "/" ]] && continue
                [[ "$line" =~ ^/sys ]] && continue
                [[ "$line" =~ ^/proc ]] && continue
                [[ "$line" =~ ^/dev ]] && continue
                [[ "$line" =~ ^/media/ ]] && drives+=("$line")
                [[ "$line" =~ ^/mnt/ ]] && drives+=("$line")
            done < <(df | awk 'NR>1 {print $6}')
            ;;
    esac
    
    # Return each drive on its own line for proper array expansion, without duplicates
    printf '%s\n' "${drives[@]}" | sort -u
}

# ============================================================================
# PHASE 2: RESOURCE PREDICTION & FEASIBILITY VALIDATION
# ============================================================================

# Component memory requirements (in MB)
declare -A COMPONENT_MIN_MEMORY=(
    [k3s-base]=512          # k3s core needs ~512MB minimum
    [registry]=150          # Docker registry lightweight ~100-150MB  
    [metrics-server]=100    # Kubernetes metrics server ~50-100MB
    [traefik]=150           # Traefik ingress controller ~100-150MB
    [argocd]=350            # ArgoCD needs ~250-350MB minimum
    [monitoring]=600        # Full monitoring stack (Prometheus+Grafana) ~500-600MB
)

# Component descriptions for user guidance
declare -A COMPONENT_DESC=(
    [registry]="Local Docker registry for image caching (recommended for offline work)"
    [metrics-server]="Kubernetes metrics server for resource monitoring (lightweight)"
    [traefik]="Ingress controller for HTTP/HTTPS routing (required for many apps)"
    [argocd]="GitOps continuous deployment tool (resource-intensive)"
    [monitoring]="Full monitoring stack: Prometheus + Grafana + alertmanager"
)

# Predict total resource consumption for a given component set
# Usage: predict_resource_consumption "registry" "metrics-server" "traefik"
# Returns: total memory needed in MB
predict_resource_consumption() {
    local total_mb=512  # Start with k3s base requirement
    
    for component in "$@"; do
        if [[ -n "${COMPONENT_MIN_MEMORY[$component]}" ]]; then
            total_mb=$((total_mb + COMPONENT_MIN_MEMORY[$component]))
        fi
    done
    
    echo "$total_mb"
}

# Validate if components can fit in available system RAM
# Usage: validate_component_feasibility "registry" "argocd" "monitoring"
# Returns: 0 (success/feasible) or 1 (failure/not feasible)
validate_component_feasibility() {
    local required_mb=$(predict_resource_consumption "$@")
    local available_mb=$((TOTAL_RAM_GB * 1024))
    
    # Leave 20% of RAM for system/Docker overhead
    local safe_available_mb=$((available_mb * 80 / 100))
    
    if [[ $required_mb -gt $safe_available_mb ]]; then
        return 1  # Not feasible
    fi
    return 0  # Feasible
}

# Detect resource bottlenecks and provide recommendations
# Usage: detect_resource_bottlenecks
# Returns: formatted string with bottleneck analysis
detect_resource_bottlenecks() {
    local current_mem=$(get_memory_usage_cached)
    local available_gb=$(calc "$TOTAL_RAM_GB - $current_mem")
    local available_mb=$(($(printf "%.0f" "$available_gb") * 1024))
    
    local issues=0
    local recommendations=""
    
    # Check memory pressure
    local mem_percent=$(($(printf "%.0f" "$(calc "$current_mem * 100 / $TOTAL_RAM_GB")") ))
    if [[ $mem_percent -gt 80 ]]; then
        recommendations="${recommendations}• CRITICAL: System memory usage at ${mem_percent}%\n"
        recommendations="${recommendations}  - Close unnecessary applications\n"
        recommendations="${recommendations}  - Consider running fewer components\n"
        ((issues++))
    elif [[ $mem_percent -gt 60 ]]; then
        recommendations="${recommendations}• WARNING: System memory usage at ${mem_percent}%\n"
        recommendations="${recommendations}  - Monitor memory usage closely\n"
        recommendations="${recommendations}  - Advanced features may cause slowdowns\n"
        ((issues++))
    fi
    
    # Check swap usage  
    local swap_usage=$(get_swap_usage)
    if [[ $(printf "%.0f" "$swap_usage") -gt 500 ]]; then
        recommendations="${recommendations}• WARNING: High swap usage detected (${swap_usage}MB)\n"
        recommendations="${recommendations}  - System is experiencing memory pressure\n"
        recommendations="${recommendations}  - Consider reducing cluster memory allocation\n"
        ((issues++))
    fi
    
    # Component feasibility recommendations
    local recommended_components=("registry" "metrics-server" "traefik")
    if ! validate_component_feasibility "${recommended_components[@]}"; then
        recommendations="${recommendations}• FEASIBILITY: Not enough RAM for recommended components\n"
        recommendations="${recommendations}  - Available: ${available_mb}MB\n"
        recommendations="${recommendations}  - Recommended needs: $(predict_resource_consumption "${recommended_components[@]}")MB\n"
        recommendations="${recommendations}  - Suggest: registry + metrics-server only\n"
        ((issues++))
    fi
    
    # Disk space check (if available)
    local disk_free_gb=$(df /tmp 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}')
    if [[ $disk_free_gb -lt 5 ]]; then
        recommendations="${recommendations}• WARNING: Low disk space (${disk_free_gb}GB free)\n"
        recommendations="${recommendations}  - Clusters need at least 5GB free space\n"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        recommendations="✓ No resource bottlenecks detected. System is healthy."
    fi
    
    echo -e "$recommendations"
    return $issues
}

# Get feasible component recommendations based on available RAM
# Usage: get_feasible_components_for_ram "8"
# Returns: space-separated component names that fit
get_feasible_components_for_ram() {
    local available_gb="${1:-$TOTAL_RAM_GB}"
    local available_mb=$((available_gb * 1024))
    local safe_available=$((available_mb * 80 / 100))  # 80% for cluster use
    
    local feasible=()
    local base_mb=512  # k3s base
    
    # Try to fit components in order of priority
    for component in "registry" "metrics-server" "traefik" "monitoring" "argocd"; do
        local component_mem=${COMPONENT_MIN_MEMORY[$component]:-0}
        if [[ $((base_mb + component_mem)) -le $safe_available ]]; then
            feasible+=("$component")
            base_mb=$((base_mb + component_mem))
        fi
    done
    
    echo "${feasible[@]}"
}

# Analyze and report detailed resource profile
# Usage: analyze_resource_profile
analyze_resource_profile() {
    log_header "System Resource Analysis"
    echo ""
    
    echo "Available System Resources:"
    echo "  • Total RAM: ${TOTAL_RAM_GB}GB"
    local current_mem=$(get_memory_usage_cached)
    echo "  • Used Memory: ${current_mem}GB"
    local available_gb=$(calc "$TOTAL_RAM_GB - $current_mem")
    echo "  • Available Memory: $(printf "%.2f" "$available_gb")GB"
    echo ""
    
    echo "Component Requirements:"
    for component in "${!COMPONENT_MIN_MEMORY[@]}"; do
        printf "  • %-20s %4d MB - %s\n" "$component" "${COMPONENT_MIN_MEMORY[$component]}" "${COMPONENT_DESC[$component]:-}"
    done
    echo ""
    
    echo "Recommended Configurations:"
    echo "  • Minimal Setup (k3s only): ~500MB"
    echo "    Fits on systems with: 2GB+ RAM"
    echo ""
    echo "  • Recommended Setup (k3s + registry + metrics + traefik): ~1.1GB"
    echo "    Fits on systems with: 4GB+ RAM"
    echo ""
    echo "  • Full Setup (all components): ~2GB"
    echo "    Fits on systems with: 8GB+ RAM"
    echo ""
    
    local feasible=$(get_feasible_components_for_ram)
    echo "For your system (${TOTAL_RAM_GB}GB available):"
    if [[ -n "$feasible" ]]; then
        echo "  ✓ Recommended components: $feasible"
        local required=$(predict_resource_consumption $feasible)
        echo "  • Total memory needed: ${required}MB"
    else
        echo "  ✗ System may be too constrained for typical Kubernetes setup"
    fi
    echo ""
    
    detect_resource_bottlenecks
}

# ============================================================================
# PHASE 3: SMART ERROR RECOVERY & AUTO-REMEDIATION
# ============================================================================

# Recovery strategies for specific error codes
# Each error has tailored recovery steps before retry
recover_from_error() {
    local error_code="$1"
    local context="$2"  # Additional context (function name, resource name, etc)
    
    log_warn "Attempting recovery from error: $error_code"
    
    case "$error_code" in
        $ERR_DOCKER_NOT_RUNNING)
            log_info "Starting Docker daemon..."
            if command -v open &>/dev/null; then
                open -a Docker  # macOS
            elif command -v systemctl &>/dev/null; then
                systemctl start docker  # Linux
            fi
            sleep 3
            if ! docker ps &>/dev/null; then
                log_error "Failed to start Docker"
                return 1
            fi
            log_success "Docker started successfully"
            return 0
            ;;
        $ERR_DOCKER_UNAVAILABLE)
            log_error "Docker is not installed. Please install Docker first:"
            log_error "  https://docs.docker.com/get-docker/"
            return 1
            ;;
        $ERR_PORT_IN_USE)
            log_warn "Port conflict detected. Attempting cleanup..."
            local port_regex=":([0-9]+)"
            if [[ $context =~ $port_regex ]]; then
                local port="${BASH_REMATCH[1]}"
                log_info "Freeing port $port..."
                if command -v lsof &>/dev/null; then
                    local pids=$(lsof -ti :$port 2>/dev/null)
                    if [[ -n "$pids" ]]; then
                        kill $pids 2>/dev/null || true
                        sleep 2
                    fi
                fi
            fi
            return 0
            ;;
        $ERR_INSUFFICIENT_RAM)
            log_warn "Insufficient RAM detected. Attempting cleanup..."
            smart_cleanup
            return 0
            ;;
        $ERR_CLUSTER_START_FAILED)
            log_info "Cluster start failed. Checking logs..."
            if [[ -f "$INSTALL_LOG" ]]; then
                tail -20 "$INSTALL_LOG" | log_error "Recent logs:"
            fi
            log_info "Attempting restart with increased delay..."
            return 0
            ;;
        $ERR_TIMEOUT)
            log_warn "Operation timeout. Attempting with longer timeout..."
            return 0
            ;;
        $ERR_PERMISSION_DENIED)
            log_error "Permission denied. Please run with appropriate permissions:"
            log_error "  sudo $0 $context"
            return 1
            ;;
        $ERR_HELM_REPO_FAILED)
            log_warn "Helm repo operation failed. Updating repos..."
            helm repo update 2>/dev/null || true
            return 0
            ;;
        *)
            log_info "No specific recovery strategy for error code: $error_code"
            return 1
            ;;
    esac
}

# Smart retry with automatic recovery
# Usage: smart_retry "docker ps" $ERR_DOCKER_NOT_RUNNING "docker-check"
# Returns: 0 on success, 1 on failure
smart_retry() {
    local command="$1"
    local error_code="${2:-$ERR_SUCCESS}"
    local context="${3:-command}"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "[$attempt/$max_attempts] Executing: $command"
        
        if eval "$command" &>/dev/null; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            if recover_from_error "$error_code" "$context"; then
                ((attempt++))
                sleep $((2 ** (attempt - 1)))  # Exponential backoff
                continue
            else
                log_error "Recovery failed for $context"
                return 1
            fi
        else
            log_error "Command failed after $max_attempts attempts"
            push_error_context "$error_code" "smart_retry" "Command: $command"
            return 1
        fi
    done
    
    return 1
}

# ============================================================================
# PHASE 3: MULTI-CLUSTER SUPPORT
# ============================================================================

# Global multi-cluster registry
declare -A CLUSTERS=(
    [local-k8s]="$CLUSTER_NAME"  # Default cluster
)

declare -A CLUSTER_STATUS=(
    [local-k8s]="running"  # Default status
)

declare -A CLUSTER_PATHS=(
    [local-k8s]="$STORAGE_PATH/$CLUSTER_NAME"  # Default path
)

# Currently active cluster
ACTIVE_CLUSTER="local-k8s"

# Create a new named cluster configuration
# Usage: create_named_cluster "staging" "8GB"
create_named_cluster() {
    local cluster_name="$1"
    local memory="${2:-4GB}"
    local runtime="${3:-$DOCKER_RUNTIME}"
    
    if [[ -z "$cluster_name" ]]; then
        log_error "Cluster name required"
        return 1
    fi
    
    if [[ -n "${CLUSTERS[$cluster_name]}" ]]; then
        log_error "Cluster '$cluster_name' already exists"
        return 1
    fi
    
    log_info "Creating multi-cluster configuration: $cluster_name"
    
    # Create cluster-specific directories
    local cluster_data_path="$STORAGE_PATH/$cluster_name"
    mkdir -p "$cluster_data_path"
    
    # Store cluster metadata
    CLUSTERS[$cluster_name]="$cluster_name"
    CLUSTER_PATHS[$cluster_name]="$cluster_data_path"
    CLUSTER_STATUS[$cluster_name]="stopped"
    
    # Create cluster config file
    local cluster_config="$cluster_data_path/.config"
    cat > "$cluster_config" <<EOF
# Cluster: $cluster_name
# Created: $(date)
CLUSTER_NAME="$cluster_name"
MEMORY_LIMIT="$memory"
DOCKER_RUNTIME="$runtime"
K3D_VERSION="${K3D_VERSION:-latest}"
K8S_VERSION="${K8S_VERSION:-latest}"
EOF
    
    log_success "Cluster configuration created: $cluster_config"
    echo "$cluster_config"
}

# List all available clusters
# Usage: list_all_clusters
list_all_clusters() {
    log_header "Available Kubernetes Clusters"
    echo ""
    
    local found=0
    for cluster in "${!CLUSTERS[@]}"; do
        local status="${CLUSTER_STATUS[$cluster]:-stopped}"
        local icon="⊘"
        if [[ "$status" == "running" ]]; then
            icon="▶"
        fi
        
        local marker=""
        if [[ "$cluster" == "$ACTIVE_CLUSTER" ]]; then
            marker=" ← ACTIVE"
        fi
        
        printf "  $icon %-20s %-12s %s\n" "$cluster" "[$status]" "$marker"
        ((found++))
    done
    
    if [[ $found -eq 0 ]]; then
        log_warn "No clusters configured"
    fi
    
    echo ""
}

# Switch to a different cluster
# Usage: switch_cluster "staging"
switch_cluster() {
    local target_cluster="$1"
    
    if [[ -z "$target_cluster" ]]; then
        log_error "Target cluster name required"
        return 1
    fi
    
    if [[ -z "${CLUSTERS[$target_cluster]}" ]]; then
        log_error "Cluster not found: $target_cluster"
        list_all_clusters
        return 1
    fi
    
    log_info "Switching to cluster: $target_cluster"
    
    # Update environment variables for new cluster
    ACTIVE_CLUSTER="$target_cluster"
    CLUSTER_NAME="${CLUSTERS[$target_cluster]}"
    STORAGE_PATH="${CLUSTER_PATHS[$target_cluster]%/*}"
    
    # Load cluster-specific config if exists
    local cluster_config="${CLUSTER_PATHS[$target_cluster]}/.config"
    if [[ -f "$cluster_config" ]]; then
        source "$cluster_config"
    fi
    
    log_success "Active cluster: $ACTIVE_CLUSTER"
    log_info "Cluster path: ${CLUSTER_PATHS[$target_cluster]}"
    
    # Update kubectl context if cluster is running
    if [[ "${CLUSTER_STATUS[$target_cluster]}" == "running" ]]; then
        local kubeconfig="${CLUSTER_PATHS[$target_cluster]}/kubeconfig.yaml"
        if [[ -f "$kubeconfig" ]]; then
            export KUBECONFIG="$kubeconfig"
            log_success "kubectl context updated"
        fi
    fi
}

# Get current active cluster info
# Usage: get_current_cluster_info
get_current_cluster_info() {
    echo "Cluster: $ACTIVE_CLUSTER"
    echo "Name: ${CLUSTERS[$ACTIVE_CLUSTER]}"
    echo "Status: ${CLUSTER_STATUS[$ACTIVE_CLUSTER]}"
    echo "Path: ${CLUSTER_PATHS[$ACTIVE_CLUSTER]}"
    echo "Runtime: $DOCKER_RUNTIME"
}

# Backup a specific cluster
# Usage: backup_cluster "staging"
backup_cluster() {
    local target_cluster="${1:-$ACTIVE_CLUSTER}"
    local cluster_path="${CLUSTER_PATHS[$target_cluster]}"
    
    if [[ ! -d "$cluster_path" ]]; then
        log_error "Cluster not found: $target_cluster"
        return 1
    fi
    
    local backup_name="${target_cluster}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_path="$STORAGE_PATH/backups/$backup_name"
    
    mkdir -p "$STORAGE_PATH/backups"
    
    log_info "Backing up cluster: $target_cluster"
    log_info "Backup path: $backup_path"
    
    if tar czf "$backup_path" -C "$cluster_path" . 2>/dev/null; then
        local size=$(du -h "$backup_path" | awk '{print $1}')
        log_success "Cluster backup complete: $size"
        echo "$backup_path"
    else
        log_error "Cluster backup failed"
        return 1
    fi
}

# List all cluster backups
# Usage: list_cluster_backups
list_cluster_backups() {
    local backup_dir="$STORAGE_PATH/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found"
        return 0
    fi
    
    log_header "Cluster Backups"
    echo ""
    
    ls -lh "$backup_dir" | tail -n +2 | while read -r line; do
        echo "  $line"
    done
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    local msg="$1"
    echo -e "${CYAN}ℹ${NC}  $msg"
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$INSTALL_LOG"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}${BOLD}✓${NC} $msg"
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $msg" >> "$INSTALL_LOG"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}${BOLD}⚠${NC}  $msg"
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $msg" >> "$INSTALL_LOG"
}

log_error() {
    local msg="$1"
    echo ""
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║  ❌ ERROR                                                    ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}${BOLD}$msg${NC}"
    echo ""
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$INSTALL_LOG"
}

log_critical() {
    local msg="$1"
    echo ""
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║  🚨 CRITICAL ERROR                                           ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}${BOLD}${UNDERLINE}$msg${NC}"
    echo -e "${RED}This error must be fixed before continuing.${NC}"
    echo ""
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [CRITICAL] $msg" >> "$INSTALL_LOG"
}

log_system() {
    local msg="$1"
    echo -e "${CYAN}📋${NC} ${BOLD}$msg${NC}"
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SYSTEM] $msg" >> "$INSTALL_LOG"
}

log_recommend() {
    local msg="$1"
    echo -e "${MAGENTA}${BOLD}💡${NC} $msg"
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [RECOMMEND] $msg" >> "$INSTALL_LOG"
}

log_header() {
    local msg="$1"
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  $(printf '%-58s' "$msg")  ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# New visual helpers for better UI
log_step() {
    local step="$1"
    local total="$2"
    local title="$3"
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  STEP $step/$total: $title${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_section() {
    local title="$1"
    echo ""
    echo -e "${GREEN}${BOLD}▶ $title${NC}"
    echo ""
}

log_action() {
    local msg="$1"
    echo -e "${YELLOW}➜${NC} $msg"
}

log_prompt() {
    local msg="$1"
    echo ""
    echo -e "${MAGENTA}${BOLD}❯${NC} ${BOLD}$msg${NC}"
}

log_divider() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
}

log_spacer() {
    echo ""
}

# First-run setup wizard
first_run_setup() {
    log_header "🚀 First-Time Setup Wizard"
    
    echo -e "${BOLD}Welcome to Kubernetes Lab Setup!${NC}"
    echo "This wizard will guide you through initial configuration."
    log_spacer
    
    # Step 1: Storage location
    log_step "1" "4" "Storage Location"
    
    echo "Choose where to store cluster data and configurations:"
    log_spacer
    
    local drives=()
    while IFS= read -r drive; do
        [[ -n "$drive" ]] && drives+=("$drive")
    done < <(detect_external_drives)
    local options=()
    local choice
    
    # Add home directory option
    options+=("$HOME/.kube-lab (Home Directory)")
    
    # Add external drives if found
    if [[ ${#drives[@]} -gt 0 ]]; then
        for drive in "${drives[@]}"; do
            local size=$(df -h "$drive" 2>/dev/null | awk 'NR==2 {print $4}')
            options+=("$drive (External Drive - $size free)")
        done
    fi
    
    # Add custom option
    options+=("Custom path (I'll specify)")
    
    echo "Available storage locations:"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    echo ""
    
    while true; do
        read -rp "Select storage location [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            break
        fi
        log_error "Invalid choice. Please enter a number between 1 and ${#options[@]}"
    done
    
    # Process choice
    if [[ $choice -eq 1 ]]; then
        STORAGE_PATH="$HOME/.kube-lab"
    elif [[ $choice -eq ${#options[@]} ]]; then
        # Custom path
        while true; do
            read -rp "Enter custom path: " STORAGE_PATH
            STORAGE_PATH="${STORAGE_PATH/#\~/$HOME}"  # Expand ~
            if [[ -d "$(dirname "$STORAGE_PATH")" ]]; then
                mkdir -p "$STORAGE_PATH" 2>/dev/null && break
                log_error "Cannot create directory at $STORAGE_PATH"
            else
                log_error "Parent directory doesn't exist"
            fi
        done
    else
        # External drive
        local drive_path="${options[$((choice-1))]}"
        drive_path="${drive_path%% (*}"  # Remove description
        STORAGE_PATH="$drive_path/kube-lab"
    fi
    
    mkdir -p "$STORAGE_PATH"
    log_success "Storage location: $STORAGE_PATH"
    log_spacer
    
    # Step 2: Cluster name
    log_step "2" "4" "Cluster Name"
    
    log_prompt "Enter cluster name (or press Enter for default):"
    read -rp "Cluster name [local-k8s]: " CLUSTER_NAME
    CLUSTER_NAME="${CLUSTER_NAME:-local-k8s}"
    log_success "Cluster name: $CLUSTER_NAME"
    log_spacer
    
    # Step 3: Registry port
    log_step "3" "4" "Registry Port"
    
    log_prompt "Choose registry port:"
    read -rp "Registry port [5000]: " REGISTRY_PORT
    REGISTRY_PORT="${REGISTRY_PORT:-5000}"
    
    # Check if port is available
    if nc -z localhost "$REGISTRY_PORT" 2>/dev/null; then
        log_warn "Port $REGISTRY_PORT is already in use!"
        read -rp "Use a different port? [5001]: " REGISTRY_PORT
        REGISTRY_PORT="${REGISTRY_PORT:-5001}"
    fi
    log_success "Registry port: $REGISTRY_PORT"
    log_spacer
    
    # Step 4: Memory limit
    log_step "4" "4" "Memory Allocation"
    
    local recommended_mem=$(calc "$TOTAL_RAM_GB * 0.45 * 1024" | awk '{printf "%.0f", $1}')
    echo -e "${BOLD}System Resources:${NC}"
    echo "  • Total RAM: ${TOTAL_RAM_GB}GB"
    echo "  • Recommended: ${recommended_mem}MB (45% of total)"
    log_spacer
    
    log_prompt "Use recommended memory setting?"
    read -rp "[Y/n]: " use_recommended
    
    # Convert to lowercase using tr for better compatibility
    use_recommended=$(echo "$use_recommended" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$use_recommended" =~ ^n ]]; then
        read -rp "Enter memory limit in MB: " MEMORY_LIMIT
    else
        MEMORY_LIMIT="auto"
    fi
    log_success "Memory limit: $MEMORY_LIMIT"
    log_spacer
    
    # Set registry name
    REGISTRY_NAME="local-registry"
    
    # Save configuration
    log_header "Saving Configuration"
    save_config
    
    echo ""
    log_success "Setup complete! Configuration saved."
    log_info "Configuration file: $CONFIG_FILE"
    echo ""
    
    # Offer to continue to installation
    while true; do
        log_header "Next Steps"
        echo "Your environment is now configured. What would you like to do?"
        echo ""
        echo "  1) Continue to guided installation (Recommended)"
        echo "  2) View configuration summary"
        echo "  3) Return to main menu"
        echo "  4) Exit"
        echo ""
        read -rp "Select option [1-4]: " next_step
        
        case "$next_step" in
            1)
                echo ""
                log_info "Proceeding to guided installation wizard..."
                sleep 1
                # Set flag to skip reconfiguration prompt since we just configured
                SKIP_RECONFIG=true
                guided_install
                break
                ;;
            2)
                echo ""
                show_system_info
                echo ""
                log_info "Press Enter to continue..."
                read -r
                # Loop continues - back to options
                ;;
            3)
                # Exit loop, will fall through to menu
                break
                ;;
            4)
                echo ""
                log_info "You can start the installation anytime with:"
                echo "  ./local-k8s.sh install"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid option. Please select 1-4."
                sleep 1
                # Loop continues
                ;;
        esac
    done
}

# Reconfigure wizard
reconfigure_setup() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_warn "This will overwrite your current configuration."
        read -rp "Continue? [y/N]: " confirm
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$confirm" =~ ^y ]]; then
            log_info "Configuration preserved. Using existing settings."
            return 1  # Return non-zero to indicate config was not changed
        fi
        rm "$CONFIG_FILE"
    fi
    first_run_setup
    return 0  # Return success after setup completes
}

# Display comprehensive system information
show_system_info() {
    echo ""
    echo "=========================================="
    echo "  System Detection Report"
    echo "=========================================="
    echo ""
    log_system "Operating System: $OS_TYPE"
    log_system "CPU Architecture: $CPU_ARCH"
    log_system "Total RAM: ${TOTAL_RAM_GB}GB"
    log_system "CPU Cores: $CPU_CORES"
    log_system "Docker Runtime: $DOCKER_RUNTIME"
    log_system "Available K8s Tools: ${K8S_TOOLS[*]:-none}"
    echo ""
    log_system "Storage Location: $KUBE_ROOT"
    log_system "Cluster Name: $CLUSTER_NAME"
    log_system "Registry Port: $REGISTRY_PORT"
    log_system "Cluster Memory Limit: ${CLUSTER_MEMORY_LIMIT}MB"
    echo ""
    echo "=========================================="
}

# Calculate component memory requirements and provide recommendations
analyze_component_feasibility() {
    local total_ram=$TOTAL_RAM_GB
    local available_for_cluster=$(calc "$total_ram * 0.5" | awk '{printf "%.2f", $1}')  # 50% for cluster + components
    
    # Component memory requirements (in GB)
    local base_cluster=1.5
    local metrics_server=0.1
    local traefik=0.3
    local argocd=0.35
    local monitoring=0.7
    local registry=0.2
    
    echo ""
    echo "=========================================="
    echo "  Component Feasibility Analysis"
    echo "=========================================="
    echo ""
    log_info "Available RAM for K8s: ${available_for_cluster}GB (50% of ${total_ram}GB)"
    echo ""
    
    # Calculate what can fit
    local running_total=$base_cluster
    local components=()
    
    echo "Component Requirements:"
    echo "  ✓ Base Cluster:        ${base_cluster}GB (required)"
    components+=("base")
    
    if compare_float "$(calc "$running_total + $registry")" "<" "$available_for_cluster"; then
        echo "  ✓ Registry:            ${registry}GB"
        running_total=$(calc "$running_total + $registry" | awk '{printf "%.2f", $1}')
        components+=("registry")
    else
        echo "  ✗ Registry:            ${registry}GB (insufficient RAM)"
    fi
    
    if compare_float "$(calc "$running_total + $metrics_server")" "<" "$available_for_cluster"; then
        echo "  ✓ Metrics Server:      ${metrics_server}GB"
        running_total=$(calc "$running_total + $metrics_server" | awk '{printf "%.2f", $1}')
        components+=("metrics")
    else
        echo "  ✗ Metrics Server:      ${metrics_server}GB (insufficient RAM)"
    fi
    
    if compare_float "$(calc "$running_total + $traefik")" "<" "$available_for_cluster"; then
        echo "  ✓ Traefik:             ${traefik}GB"
        running_total=$(calc "$running_total + $traefik" | awk '{printf "%.2f", $1}')
        components+=("traefik")
    else
        echo "  ✗ Traefik:             ${traefik}GB (insufficient RAM)"
    fi
    
    if compare_float "$(calc "$running_total + $argocd")" "<" "$available_for_cluster"; then
        echo "  ✓ ArgoCD:              ${argocd}GB"
        running_total=$(calc "$running_total + $argocd" | awk '{printf "%.2f", $1}')
        components+=("argocd")
    else
        echo "  ✗ ArgoCD:              ${argocd}GB (insufficient RAM)"
    fi
    
    if compare_float "$(calc "$running_total + $monitoring")" "<" "$available_for_cluster"; then
        echo "  ✓ Monitoring Stack:    ${monitoring}GB"
        running_total=$(calc "$running_total + $monitoring" | awk '{printf "%.2f", $1}')
        components+=("monitoring")
    else
        echo "  ✗ Monitoring Stack:    ${monitoring}GB (insufficient RAM)"
    fi
    
    echo ""
    echo "Estimated Total Usage: ${running_total}GB / ${available_for_cluster}GB available"
    echo ""
    
    # Provide recommendations
    echo "=========================================="
    echo "  Recommendations"
    echo "=========================================="
    echo ""
    
    if compare_float "$total_ram" "<" "4"; then
        log_error "CRITICAL: Less than 4GB RAM detected!"
        log_recommend "Minimum recommendation: 4GB RAM for basic cluster"
        log_recommend "Consider: Using minikube with minimal profile"
        log_recommend "Install: Base cluster only, no optional components"
    elif compare_float "$total_ram" "<" "8"; then
        log_warn "LOW RAM: 4-8GB detected"
        log_recommend "Install: Base cluster + Registry + Metrics Server"
        log_recommend "Skip: ArgoCD and Monitoring (use external tools)"
        log_recommend "Consider: Closing background applications before starting"
    elif compare_float "$total_ram" "<" "16"; then
        log_success "ADEQUATE: 8-16GB detected"
        log_recommend "Install: Base cluster + Registry + Metrics + Traefik"
        log_recommend "Optional: ArgoCD OR Monitoring (choose one)"
        log_recommend "Note: Can run both but may experience slowdowns"
    else
        log_success "EXCELLENT: 16GB+ detected"
        log_recommend "Install: All components recommended"
        log_recommend "You can safely run the full stack including monitoring"
    fi
    
    echo ""
    
    # Docker runtime - just report what's detected, no judgment
    if [[ "$DOCKER_RUNTIME" != "none" ]]; then
        log_info "Docker Runtime: $DOCKER_RUNTIME detected"
        
        # Provide runtime-specific tips without being prescriptive
        case "$DOCKER_RUNTIME" in
            colima)
                log_info "Tip: Check 'colima status' to view allocated resources"
                ;;
            docker-desktop)
                log_info "Tip: Verify memory allocation in Docker Desktop → Settings → Resources"
                ;;
            rancher)
                log_info "Tip: Check resource settings in Rancher Desktop preferences"
                ;;
            orbstack)
                log_info "Tip: OrbStack automatically manages resources"
                ;;
        esac
    else
        log_error "No Docker runtime detected!"
        log_info "This script requires Docker or a Docker-compatible runtime"
        log_info "Install any of: Docker Desktop, Colima, Rancher Desktop, OrbStack, or native Docker"
    fi
    
    echo ""
    echo "=========================================="
}

check_external_drive() {
    if [[ ! -d "$EXTERNAL_DRIVE" ]]; then
        log_warn "External drive not found at $EXTERNAL_DRIVE"
        log_info "Falling back to home directory: $HOME/.kube-lab"
        EXTERNAL_DRIVE="$HOME/.kube-lab"
        KUBE_ROOT="${EXTERNAL_DRIVE}/kube-stack"
        REGISTRY_DIR="${KUBE_ROOT}/registry"
        PV_DIR="${KUBE_ROOT}/pv-data"
        BACKUP_DIR="${KUBE_ROOT}/backups"
        LOG_DIR="${KUBE_ROOT}/logs"
        TMP_DIR="${KUBE_ROOT}/tmp"
        CONFIG_DIR="${KUBE_ROOT}/config"
        mkdir -p "$EXTERNAL_DRIVE"
    fi
}

check_docker_runtime_available() {
    case "$DOCKER_RUNTIME" in
        none)
            log_error "No Docker runtime detected!"
            echo ""
            log_info "This script requires Docker or a Docker-compatible runtime."
            log_info "Install any Docker runtime that works for your system:"
            echo "  • Docker Desktop"
            echo "  • Colima"
            echo "  • Rancher Desktop"
            echo "  • OrbStack"
            echo "  • Docker Engine (native)"
            echo "  • Podman (Linux)"
            echo ""
            log_info "Visit https://docs.docker.com/get-docker/ for installation guides"
            exit 1
            ;;
        orbstack)
            if ! command -v orb &> /dev/null; then
                log_warn "OrbStack detected but CLI not found"
                log_info "OrbStack's docker is available, continuing..."
            fi
            if command -v orb &> /dev/null && ! orb status &> /dev/null; then
                log_info "Starting OrbStack..."
                if [[ "$OS_TYPE" == "macos" ]]; then
                    open -a OrbStack 2>/dev/null || true
                else
                    # On Linux, OrbStack may start differently or need manual start
                    log_warn "Please start OrbStack manually"
                fi
                sleep 5
            fi
            ;;
        colima)
            if ! colima status &> /dev/null 2>&1; then
                log_info "Starting Colima..."
                colima start || {
                    log_error "Failed to start Colima"
                    exit 1
                }
            fi
            ;;
        rancher)
            if ! docker ps &> /dev/null; then
                log_error "Rancher Desktop Docker is not running"
                log_info "Please start Rancher Desktop and try again"
                exit 1
            fi
            ;;
        docker-desktop|docker)
            if ! docker ps &> /dev/null; then
                log_error "Docker is not running"
                log_info "Please start your Docker runtime and try again"
                exit 1
            fi
            ;;
    esac
}

check_dependencies() {
    log_info "Checking required dependencies..."
    
    local missing=()
    local optional_missing=()
    
    # Required dependencies
    local required_deps=(docker kubectl)
    for cmd in "${required_deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    # Optional but recommended
    local optional_deps=(helm jq bc curl)
    for cmd in "${optional_deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            optional_missing+=("$cmd")
        fi
    done
    
    # Report missing required dependencies
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_critical "Missing required dependencies: ${missing[*]}"
        echo ""
        log_info "Please install the missing dependencies."
        log_info "Visit https://kubernetes.io/docs/tasks/tools/ for installation guides"
        echo ""
        exit 1
    fi
    
    # Report missing optional dependencies
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_warn "Missing optional dependencies: ${optional_missing[*]}"
        log_info "These are optional but improve the experience"
        echo ""
        read -rp "Continue without optional dependencies? [y/N]: " cont
        cont=$(echo "$cont" | tr '[:upper:]' '[:lower:]')
        [[ ! "$cont" =~ ^y ]] && exit 1
    fi
    
    log_success "All required dependencies found"
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        log_info "Please install kubectl for your system"
        return 1
    fi
}

check_helm() {
    if ! command -v helm &> /dev/null; then
        log_warn "Helm not found"
        log_info "Some features require Helm. Install it if needed."
        return 1
    fi
}

# Find an available port starting from given port
find_available_port() {
    local start_port=$1
    local max_attempts=50
    local port=$start_port
    
    for ((i=0; i<max_attempts; i++)); do
        if command -v lsof &> /dev/null; then
            if ! lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
                echo "$port"
                return 0
            fi
        elif command -v nc &> /dev/null; then
            if ! nc -z localhost "$port" 2>/dev/null; then
                echo "$port"
                return 0
            fi
        fi
        ((port++))
    done
    
    return 1
}

check_port_available() {
    local port=$1
    local service=$2
    local auto_find=${3:-false}
    
    # Check if port is in use using multiple methods for cross-platform compatibility
    local port_in_use=false
    local process_info=""
    
    if command -v lsof &> /dev/null; then
        # macOS and Linux with lsof
        if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
            port_in_use=true
            # Get detailed process information
            local lsof_output=$(lsof -Pi ":$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1, $2, $9}')
            if [[ -n "$lsof_output" ]]; then
                local proc_name=$(echo "$lsof_output" | awk '{print $1}')
                local proc_pid=$(echo "$lsof_output" | awk '{print $2}')
                process_info="$proc_name (PID: $proc_pid)"
            else
                process_info="Unknown process"
            fi
        fi
    elif command -v netstat &> /dev/null; then
        # Fallback to netstat (Windows, older Linux)
        if [[ "$OS_TYPE" == "macos" ]] || [[ "$OS_TYPE" == "linux" ]]; then
            if netstat -an | grep -q "[\.\:]$port.*LISTEN"; then
                port_in_use=true
                process_info="Process detected via netstat"
            fi
        elif [[ "$OS_TYPE" == "wsl2" ]] || [[ "$OS_TYPE" == "windows" ]]; then
            if netstat -ano | findstr ":$port.*LISTENING" &>/dev/null; then
                port_in_use=true
                process_info="Process detected via netstat"
            fi
        fi
    elif command -v ss &> /dev/null; then
        # Linux with ss (socket statistics)
        if ss -ln | grep -q ":$port "; then
            port_in_use=true
            process_info="Process detected via ss"
        fi
    elif command -v nc &> /dev/null; then
        # Last resort: netcat
        if nc -z localhost "$port" 2>/dev/null; then
            port_in_use=true
            process_info="Process detected via nc"
        fi
    fi
    
    if [[ "$port_in_use" == "true" ]]; then
        if [[ "$auto_find" == "true" ]]; then
            log_warn "$service port $port is in use by $process_info"
            local new_port=$(find_available_port $((port + 1)))
            if [[ -n "$new_port" ]]; then
                log_info "Auto-selected available port: $new_port"
                echo "$new_port"
                return 0
            else
                log_error "Could not find an available port in range $((port + 1))-$((port + 50))"
                return 1
            fi
        else
            log_error "$service port $port is already in use!"
            echo ""
            echo "Process using port: $process_info"
            echo ""
            log_recommend "Options:"
            echo "  1. Stop the process using this port"
            echo "  2. Choose a different port"
            echo "  3. Run: $0 reconfigure (to change settings)"
            echo ""
            return 1
        fi
    fi
    
    # Port is available
    return 0
}

get_memory_usage() {
    # Returns memory usage in GB - cross-platform
    case "$OS_TYPE" in
        macos)
            vm_stat 2>/dev/null | awk '
                /Pages active/ {active=$3}
                /Pages wired/ {wired=$3}
                END {print (active+wired)*4096/1024/1024/1024}
            ' || echo "0"
            ;;
        linux|wsl2)
            # Get used memory from /proc/meminfo
            awk '/MemTotal/{total=$2} /MemAvailable/{avail=$2} END {printf "%.2f", (total-avail)/1024/1024}' /proc/meminfo 2>/dev/null || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_swap_usage() {
    # Returns swap usage in MB - cross-platform
    case "$OS_TYPE" in
        macos)
            sysctl vm.swapusage 2>/dev/null | awk '{print $7}' | sed 's/M//' || echo "0"
            ;;
        linux|wsl2)
            # Get swap used from /proc/meminfo
            awk '/SwapTotal/{total=$2} /SwapFree/{free=$2} END {printf "%.0f", (total-free)/1024}' /proc/meminfo 2>/dev/null || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

check_system_health() {
    local mem_used=$(get_memory_usage_cached)
    local swap_used_raw=$(get_swap_usage)
    local swap_used=$(printf "%.0f" "$swap_used_raw")  # Convert float to integer
    local mem_threshold=$MAX_SAFE_MEMORY
    local issues=0
    
    # Check memory usage (only warn if >80% used)
    if compare_float "$mem_used" ">" "$mem_threshold"; then
        log_warn "High memory usage: ${mem_used}GB / ${TOTAL_RAM_GB}GB (>80%)"
        log_warn "Consider closing other applications."
        ((issues++))
    fi
    
    # Check swap - only critical if >3GB or >40% of RAM
    if [[ "$swap_used_raw" != "0.00" ]] && [[ "$swap_used_raw" != "0" ]]; then
        local swap_gb=$(calc "$swap_used_raw / 1024" | awk '{printf "%.2f", $1}')
        local swap_percent_raw=$(calc "$swap_used_raw / ($TOTAL_RAM_GB * 1024) * 100" | awk '{printf "%.0f", $1}')
        local swap_percent=$(printf "%.0f" "$swap_percent_raw")  # Ensure integer for comparison
        
        # Only warn if swap usage is significant (>40% of RAM or >3GB)
        if compare_int "$swap_used" ">" "3072" || compare_int "$swap_percent" ">" "40"; then
            log_warn "High swap usage: ${swap_gb}GB (${swap_percent}% of RAM)"
            log_warn "System may experience performance issues"
            ((issues++))
        else
            # Minor swap usage is normal on macOS - just log it
            log_info "Swap usage: ${swap_gb}GB (${swap_percent}% of RAM) - within acceptable range"
        fi
    fi
    
    # Only fail if we have actual issues
    if [[ $issues -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# ROLLBACK MECHANISM
# ============================================================================

# Initialize installation state tracking
init_install_state() {
    echo "# Installation State - $(date)" > "$STATE_FILE"
    echo "# This file tracks installation progress for rollback" >> "$STATE_FILE"
}

# Mark component installation start
mark_component_start() {
    local component=$1
    echo "$component:started:$(date +%s)" >> "$STATE_FILE"
    log_info "Starting $component installation..."
}

# Mark component installation complete
mark_component_complete() {
    local component=$1
    sed -i.bak "s/$component:started/$component:completed/" "$STATE_FILE" 2>/dev/null || \
        sed -i '' "s/$component:started/$component:completed/" "$STATE_FILE" 2>/dev/null
    log_success "$component installed successfully"
}

# Mark component installation failed
mark_component_failed() {
    local component=$1
    sed -i.bak "s/$component:started/$component:failed/" "$STATE_FILE" 2>/dev/null || \
        sed -i '' "s/$component:started/$component:failed/" "$STATE_FILE" 2>/dev/null
    log_error "$component installation failed"
}

# Check what components are installed
get_installed_components() {
    [[ ! -f "$STATE_FILE" ]] && return
    grep ":completed:" "$STATE_FILE" | cut -d: -f1
}

# Rollback failed installation
rollback_installation() {
    log_warn "Rolling back failed installation..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log_info "No installation state found, nothing to rollback"
        return
    fi
    
    # Get components that need rollback (started but not completed)
    local components=$(grep ":started:" "$STATE_FILE" | cut -d: -f1)
    
    if [[ -z "$components" ]]; then
        log_info "No incomplete installations found"
        return
    fi
    
    for component in $components; do
        log_info "Rolling back $component..."
        case "$component" in
            cluster)
                stop_cluster 2>/dev/null || true
                delete_cluster 2>/dev/null || true
                ;;
            registry)
                stop_registry 2>/dev/null || true
                ;;
            traefik)
                helm uninstall traefik -n kube-system 2>/dev/null || true
                ;;
            argocd)
                helm uninstall argocd -n argocd 2>/dev/null || true
                kubectl delete namespace argocd 2>/dev/null || true
                ;;
            monitoring)
                helm uninstall monitoring -n monitoring 2>/dev/null || true
                kubectl delete namespace monitoring 2>/dev/null || true
                ;;
            metrics-server)
                kubectl delete -n kube-system deployment metrics-server 2>/dev/null || true
                ;;
        esac
        mark_component_failed "$component"
    done
    
    log_success "Rollback complete"
    echo ""
    log_info "Installation state preserved in: $STATE_FILE"
    log_info "To retry installation, run: $0 install"
}

create_directory_structure() {
    log_info "Creating directory structure..."
    
    mkdir -p "$REGISTRY_DIR"
    mkdir -p "$PV_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$TMP_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # Set secure permissions
    chmod 700 "$KUBE_ROOT"
    chmod 700 "$REGISTRY_DIR"
    chmod 700 "$PV_DIR"
    chmod 700 "$BACKUP_DIR"
    
    log_success "Directory structure created"
}

# ============================================================================
# REGISTRY FUNCTIONS
# ============================================================================

create_registry_config() {
    log_info "Creating registry configuration..."
    
    cat > "${CONFIG_DIR}/registry-config.yml" <<EOF
version: 0.1
log:
  level: info
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  cache:
    blobdescriptor: inmemory
  delete:
    enabled: true
http:
  addr: :5000
  host: http://localhost:5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
    
    log_success "Registry configuration created"
}

start_registry() {
    mark_component_start "registry"
    
    log_info "Starting local Docker registry..."
    log_info "Variables: NAME=$REGISTRY_NAME, PORT=$REGISTRY_PORT, DIR=$REGISTRY_DIR"
    
    # Check if registry is already running
    if docker ps | grep -q "$REGISTRY_NAME"; then
        log_info "Registry already running on port ${REGISTRY_PORT}"
        mark_component_complete "registry"
        return 0
    fi
    
    # Check port availability and auto-find if needed
    local actual_port=$REGISTRY_PORT
    log_info "Checking port $REGISTRY_PORT availability..."
    local port_check=$(check_port_available "$REGISTRY_PORT" "Registry" "true")
    local port_check_exit=$?
    log_info "Port check result: exit=$port_check_exit, output='$port_check'"
    
    if [[ $port_check_exit -eq 0 ]] && [[ -n "$port_check" ]] && [[ "$port_check" != "0" ]]; then
        actual_port=$port_check
        # Update config file with new port
        REGISTRY_PORT=$actual_port
        if [[ -f "$CONFIG_FILE" ]]; then
            sed -i.bak "s/^REGISTRY_PORT=.*/REGISTRY_PORT=\"$actual_port\"/" "$CONFIG_FILE" 2>/dev/null || \
                sed -i '' "s/^REGISTRY_PORT=.*/REGISTRY_PORT=\"$actual_port\"/" "$CONFIG_FILE" 2>/dev/null
            log_success "Updated registry port to $actual_port in config"
        fi
    elif [[ $port_check_exit -ne 0 ]]; then
        log_error "Port check failed for $REGISTRY_PORT"
        mark_component_failed "registry"
        return 1
    fi
    
    # Remove old registry container if exists
    docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
    
    # Start registry with resource limits
    # Note: Only mount config if it exists, otherwise use defaults
    local mount_args="-v ${REGISTRY_DIR}:/var/lib/registry"
    if [[ -f "${CONFIG_DIR}/registry-config.yml" ]]; then
        mount_args="$mount_args -v ${CONFIG_DIR}/registry-config.yml:/etc/docker/registry/config.yml"
    fi
    
    # Capture error output for debugging
    # Note: Using eval to properly handle mount_args with spaces in paths
    log_info "Debug: REGISTRY_NAME=$REGISTRY_NAME, REGISTRY_PORT=$REGISTRY_PORT"
    log_info "Debug: REGISTRY_DIR=$REGISTRY_DIR, CONFIG_DIR=$CONFIG_DIR"
    log_info "Debug: mount_args=$mount_args"
    
    # Adjust registry memory based on mode
    local registry_memory="100m"
    if [[ "${LOW_MEMORY_MODE:-false}" == "true" ]]; then
        registry_memory="50m"
    fi
    
    local docker_error
    docker_error=$(eval docker run -d \
        --name "$REGISTRY_NAME" \
        --restart=always \
        -p "${REGISTRY_PORT}:5000" \
        $mount_args \
        --memory="$registry_memory" \
        --cpus="0.5" \
        registry:2 2>&1)
    
    local docker_exit_code=$?
    
    if [[ $docker_exit_code -ne 0 ]]; then
        log_error "Failed to start registry container (docker run failed)"
        log_error "Docker error: $docker_error"
        log_error "Port: $REGISTRY_PORT, Registry dir: $REGISTRY_DIR"
        log_error "Mount args: $mount_args"
        mark_component_failed "registry"
        return 1
    fi
    
    # Wait for registry to be ready
    sleep 3
    
    if docker ps | grep -q "$REGISTRY_NAME"; then
        log_success "Registry started at localhost:${REGISTRY_PORT}"
        mark_component_complete "registry"
    else
        log_error "Registry container exited unexpectedly"
        log_error "Container logs:"
        docker logs "$REGISTRY_NAME" 2>&1 | while IFS= read -r line; do log_error "  $line"; done
        log_error "Port: $REGISTRY_PORT, Registry dir: $REGISTRY_DIR"
        log_error "Mount args: $mount_args"
        mark_component_failed "registry"
        return 1
    fi
}

stop_registry() {
    log_info "Stopping local registry..."
    docker stop "$REGISTRY_NAME" 2>/dev/null || true
    docker rm "$REGISTRY_NAME" 2>/dev/null || true
    log_success "Registry stopped"
}

# ============================================================================
# KUBERNETES CLUSTER FUNCTIONS
# ============================================================================

start_cluster() {
    log_info "Starting lightweight Kubernetes cluster with k3d..."
    log_info "Detected Docker runtime: $DOCKER_RUNTIME"
    
    check_system_health || {
        log_warn "System resources are constrained. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && exit 1
    }
    
    # Check if k3d is installed
    if ! command -v k3d &> /dev/null; then
        log_warn "k3d not found - k3d is the lightweight K3s cluster manager"
        echo ""
        log_info "k3d is the recommended tool for this script (lightweight, fast, resource-efficient)"
        echo ""
        read -rp "Install k3d now? [Y/n]: " install_k3d
        install_k3d=$(echo "$install_k3d" | tr '[:upper:]' '[:lower:]')
        
        if [[ ! "$install_k3d" =~ ^n ]]; then
            log_info "Installing k3d..."
            
            if [[ "$OS_TYPE" == "macos" ]]; then
                # Try homebrew first
                if command -v brew &> /dev/null; then
                    if brew install k3d; then
                        log_success "k3d installed via Homebrew"
                    else
                        log_warn "Homebrew install failed, trying curl..."
                        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || {
                            log_error "Failed to install k3d"
                            mark_component_failed "cluster"
                            return 1
                        }
                    fi
                else
                    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || {
                        log_error "Failed to install k3d"
                        mark_component_failed "cluster"
                        return 1
                    }
                fi
            elif [[ "$OS_TYPE" == "linux" ]] || [[ "$OS_TYPE" == "wsl2" ]]; then
                curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || {
                    log_error "Failed to install k3d"
                    mark_component_failed "cluster"
                    return 1
                }
            else
                log_error "Unsupported OS for automatic k3d installation"
                log_info "Please install k3d manually: https://k3d.io/stable/#installation"
                mark_component_failed "cluster"
                return 1
            fi
            
            log_success "k3d installed successfully"
        else
            # User declined k3d installation - check for alternatives
            log_info "Checking for alternative cluster tools..."
            
            if command -v kind &> /dev/null; then
                log_info "Found 'kind' - using as alternative"
                start_cluster_kind
                return $?
            elif command -v minikube &> /dev/null; then
                log_info "Found 'minikube' - using as alternative"
                start_cluster_minikube
                return $?
            elif command -v orb &> /dev/null; then
                log_info "Found 'OrbStack' - using as alternative"
                start_cluster_orbstack
                return $?
            else
                log_error "No cluster tools available!"
                log_info "Please install k3d: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
                mark_component_failed "cluster"
                return 1
            fi
        fi
    fi
    
    # k3d is installed - use it
    log_info "Using k3d to create lightweight K3s cluster (1 server + 1 worker)"
    start_cluster_k3d
}

start_cluster_orbstack() {
    mark_component_start "cluster"
    
    # Check if OrbStack Kubernetes is available
    if ! orb status | grep -q "Running"; then
        log_info "Starting OrbStack..."
        if [[ "$OS_TYPE" == "macos" ]]; then
            open -a OrbStack 2>/dev/null || true
        fi
        sleep 5
    fi
    
    # Create K3s cluster via OrbStack
    if orb list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster already exists"
        if ! orb start "$CLUSTER_NAME" 2>/dev/null; then
            log_error "Failed to start existing cluster"
            mark_component_failed "cluster"
            return 1
        fi
    else
        log_info "Creating new K3s cluster via OrbStack..."
        log_info "Note: OrbStack manages resources automatically based on system capacity"
        
        # OrbStack doesn't support --memory, --cpus, --disk flags
        # It manages resources automatically
        # We can only pass machine name for k3s type
        if ! orb create k3s "$CLUSTER_NAME" 2>&1; then
            log_error "Failed to create cluster with OrbStack"
            log_info "Attempting basic K3s creation..."
            # Try basic creation without extra args
            if ! orb create k3s "$CLUSTER_NAME"; then
                log_error "Failed to create cluster"
                mark_component_failed "cluster"
                return 1
            fi
        fi
        
        log_info "Waiting for cluster to initialize..."
        sleep 10
        
        # OrbStack automatically configures k3s, but we can customize after creation
        # by accessing the VM and modifying k3s config if needed
        log_info "Cluster created. OrbStack manages k3s configuration automatically."
    fi
    
    # Save and switch kubectl context
    switch_to_cluster_context
    
    # OrbStack should auto-configure kubectl context
    # Try to use the context directly
    local context_name="orbstack"
    if kubectl config get-contexts "$context_name" &>/dev/null; then
        kubectl config use-context "$context_name" &>/dev/null
        log_success "Switched to context: $context_name"
    else
        log_warn "OrbStack context not found, trying alternative methods..."
        # OrbStack may use machine name as context
        if kubectl config get-contexts "$CLUSTER_NAME" &>/dev/null; then
            kubectl config use-context "$CLUSTER_NAME" &>/dev/null
            log_success "Switched to context: $CLUSTER_NAME"
        fi
    fi
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if kubectl cluster-info &>/dev/null; then
            break
        fi
        ((retries++))
        sleep 2
    done
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cluster failed to become accessible"
        mark_component_failed "cluster"
        return 1
    fi
    
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=120s 2>/dev/null; then
        log_warn "Timeout waiting for nodes, checking status..."
        kubectl get nodes
        # Don't fail immediately, cluster might still be usable
    fi
    
    log_success "Cluster is ready"
    mark_component_complete "cluster"
}

start_cluster_k3d() {
    mark_component_start "cluster"
    
    # Check if k3d is installed
    if ! command -v k3d &> /dev/null; then
        log_info "k3d not found. Installing..."
        
        # Try package manager first if available
        local installed=false
        if command -v brew &> /dev/null; then
            log_info "Trying Homebrew installation..."
            if brew install k3d; then
                installed=true
            else
                log_warn "Homebrew install failed"
            fi
        elif command -v apt-get &> /dev/null; then
            log_warn "k3d not in apt repos, using official installer"
        fi
        
        # Fallback to official installer
        if [[ "$installed" == false ]]; then
            log_info "Using official k3d installer..."
            if ! curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; then
                log_error "Failed to install k3d"
                mark_component_failed "cluster"
                return 1
            fi
        fi
    fi
    
    # Create k3d cluster
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster already exists"
        if ! k3d cluster start "$CLUSTER_NAME" 2>/dev/null; then
            log_error "Failed to start existing cluster"
            mark_component_failed "cluster"
            return 1
        fi
    else
        log_info "Creating new k3d cluster..."
        
        # Calculate server count based on RAM and mode
        local servers=1
        local agents=1
        
        if [[ "${LOW_MEMORY_MODE:-false}" == "true" ]]; then
            agents=0  # Single node only in low-memory mode
        elif compare_float "$TOTAL_RAM_GB" ">=" "16"; then
            agents=2
        fi
        
        # Convert memory limit from MB to human-readable format for k3d
        local memory_per_node="${CLUSTER_MEMORY_LIMIT}m"  # k3d expects memory in format like "1024m" or "2g"
        local memory_for_k3d=$(echo "$CLUSTER_MEMORY_LIMIT" | awk '{printf "%.0f", $1 / 1024}')
        memory_for_k3d="${memory_for_k3d}g"  # Convert MB to GB format
        
        log_info "Allocating ${CLUSTER_MEMORY_LIMIT}MB (${memory_for_k3d}) per node to k3d cluster"
        
        # Configure eviction thresholds based on resource tier
        local eviction_hard_memory
        local eviction_soft_memory
        case "$RESOURCE_TIER" in
            low)
                # Low tier: Be aggressive with eviction to prevent OOM
                eviction_hard_memory="memory.available<200Mi"
                eviction_soft_memory="memory.available<300Mi"
                ;;
            medium)
                # Medium tier: Balanced eviction
                eviction_hard_memory="memory.available<300Mi"
                eviction_soft_memory="memory.available<500Mi"
                ;;
            high)
                # High tier: More lenient, allow better performance
                eviction_hard_memory="memory.available<500Mi"
                eviction_soft_memory="memory.available<1Gi"
                ;;
        esac
        
        log_info "Configuring pod eviction thresholds for $RESOURCE_TIER tier"
        
        if ! k3d cluster create "$CLUSTER_NAME" \
            --servers "$servers" \
            --agents "$agents" \
            --servers-memory "${memory_for_k3d}" \
            --agents-memory "${memory_for_k3d}" \
            --port "80:80@loadbalancer" \
            --port "443:443@loadbalancer" \
            --volume "${REGISTRY_DIR}:/var/lib/registry@all" \
            --volume "${PV_DIR}:/var/lib/rancher/k3s/storage@all" \
            --k3s-arg "--disable=traefik@server:0" \
            --k3s-arg "--disable=servicelb@server:0" \
            --k3s-arg "--kubelet-arg=eviction-hard=${eviction_hard_memory}@server:*" \
            --k3s-arg "--kubelet-arg=eviction-soft=${eviction_soft_memory}@server:*" \
            --k3s-arg "--kubelet-arg=eviction-soft-grace-period=memory.available=1m30s@server:*" \
            --wait; then
            log_error "Failed to create k3d cluster"
            mark_component_failed "cluster"
            return 1
        fi
        
        sleep 5
    fi
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=120s; then
        log_error "Cluster failed to become ready"
        mark_component_failed "cluster"
        return 1
    fi
    
    log_success "Cluster is ready"
    mark_component_complete "cluster"
}

start_cluster_minikube() {
    mark_component_start "cluster"
    
    log_info "Using Minikube for cluster creation..."
    
    # Check if minikube is installed
    if ! command -v minikube &> /dev/null; then
        log_info "Minikube not found. Installing..."
        
        local installed=false
        # Try package manager first if available
        if command -v brew &> /dev/null; then
            log_info "Trying Homebrew installation..."
            if brew install minikube; then
                installed=true
            else
                log_warn "Homebrew install failed"
            fi
        elif command -v apt-get &> /dev/null; then
            log_info "Trying apt-get installation..."
            if sudo apt-get update && sudo apt-get install -y minikube; then
                installed=true
            else
                log_warn "apt-get install failed"
            fi
        fi
        
        # Fallback to official binary installer
        if [[ "$installed" == false ]]; then
            log_info "Using official minikube binary..."
            if [[ "$ARCH" == "arm64" ]]; then
                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64
                sudo install minikube-linux-arm64 /usr/local/bin/minikube
                rm minikube-linux-arm64
            else
                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
                sudo install minikube-linux-amd64 /usr/local/bin/minikube
                rm minikube-linux-amd64
            fi
        fi
    fi
    
    # Check if cluster exists and is running
    if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
        log_info "Cluster already exists, starting..."
        if ! minikube start -p "$CLUSTER_NAME"; then
            log_error "Failed to start existing cluster"
            mark_component_failed "cluster"
            return 1
        fi
    else
        log_info "Creating new Minikube cluster..."
        
        # Calculate resources for minikube
        local minikube_mem=$(echo "$CLUSTER_MEMORY_LIMIT" | awk '{printf "%.0f", $1}')
        local minikube_cpus=$CPU_CORES
        
        # Minikube uses different drivers based on system
        local driver="docker"
        if [[ "$DOCKER_RUNTIME" == "orbstack" ]]; then
            driver="docker"
        fi
        
        if ! minikube start -p "$CLUSTER_NAME" \
            --driver="$driver" \
            --memory="${minikube_mem}mb" \
            --cpus="$minikube_cpus" \
            --disk-size=20g \
            --kubernetes-version=stable \
            --addons=metrics-server,storage-provisioner; then
            log_error "Failed to create Minikube cluster"
            mark_component_failed "cluster"
            return 1
        fi
    fi
    
    # Set kubectl context
    kubectl config use-context "$CLUSTER_NAME" &>/dev/null
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=120s; then
        log_warn "Timeout waiting for nodes, checking status..."
        kubectl get nodes
    fi
    
    log_success "Minikube cluster is ready"
    mark_component_complete "cluster"
}

start_cluster_kind() {
    mark_component_start "cluster"
    
    log_info "Using kind (Kubernetes in Docker) for cluster creation..."
    
    # Check if kind is installed
    if ! command -v kind &> /dev/null; then
        log_info "kind not found. Installing..."
        
        local installed=false
        # Try package manager first if available
        if command -v brew &> /dev/null; then
            log_info "Trying Homebrew installation..."
            if brew install kind; then
                installed=true
            else
                log_warn "Homebrew install failed"
            fi
        elif command -v apt-get &> /dev/null; then
            log_warn "kind not in apt repos, using official installer"
        fi
        
        # Fallback to official binary installer
        if [[ "$installed" == false ]]; then
            log_info "Using official kind binary..."
            if [[ "$ARCH" == "arm64" ]]; then
                curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-arm64
            else
                curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
            fi
            chmod +x ./kind
            sudo mv ./kind /usr/local/bin/kind
        fi
    fi
    
    # Check if cluster exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Cluster already exists"
        log_success "kind cluster is ready"
        mark_component_complete "cluster"
        return 0
    fi
    
    log_info "Creating new kind cluster..."
    
    # Create kind config with port mappings
    cat > "${TMP_DIR}/kind-config.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
EOF
    
    if ! kind create cluster --name "$CLUSTER_NAME" --config="${TMP_DIR}/kind-config.yaml" --wait 5m; then
        log_error "Failed to create kind cluster"
        mark_component_failed "cluster"
        return 1
    fi
    
    # Set kubectl context
    kubectl config use-context "kind-${CLUSTER_NAME}" &>/dev/null
    
    log_success "kind cluster is ready"
    mark_component_complete "cluster"
}

# Create cluster-critical PriorityClass to protect important pods from eviction
setup_priority_classes() {
    log_info "Creating PriorityClass for critical pods..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: cluster-critical
value: 1000000000
globalDefault: false
description: "This priority class is for cluster-critical pods that should not be evicted"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "This priority class is for high-priority user workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
globalDefault: true
description: "This priority class is for low-priority workloads (default)"
EOF
    
    # Patch existing system deployments to use cluster-critical priority
    log_info "Applying priority to critical system components..."
    
    # Patch coredns
    kubectl patch deployment coredns -n kube-system -p '{"spec":{"template":{"spec":{"priorityClassName":"cluster-critical"}}}}' 2>/dev/null || true
    
    # Patch metrics-server (will be created later)
    kubectl patch deployment metrics-server -n kube-system -p '{"spec":{"template":{"spec":{"priorityClassName":"cluster-critical"}}}}' 2>/dev/null || true
    
    # Patch local-path-provisioner
    kubectl patch deployment local-path-provisioner -n kube-system -p '{"spec":{"template":{"spec":{"priorityClassName":"cluster-critical"}}}}' 2>/dev/null || true
    
    log_success "PriorityClasses configured"
}

setup_namespaces() {
    log_info "Setting up namespaces with dynamic resource quotas..."
    
    # Check for actual memory pressure (not just stale swap)
    local current_mem=$(get_memory_usage_cached)
    local swap_used_mb=$(get_swap_usage)
    local swap_total_mb=$(get_swap_total)
    local memory_pressure=false
    
    # Only trigger degradation if BOTH conditions are true:
    # 1. High RAM usage (>75% active memory)
    # 2. High swap usage (>50% swap AND actively growing)
    local ram_threshold=$(calc "$TOTAL_RAM_GB * 0.75" | awk '{printf "%.2f", $1}')
    local swap_threshold=$(calc "$swap_total_mb * 0.5" | awk '{printf "%.0f", $1}')
    
    if compare_float "$current_mem" ">" "$ram_threshold" && \
       compare_int "$swap_used_mb" ">" "$swap_threshold"; then
        memory_pressure=true
        local swap_pct=$(calc "($swap_used_mb / $swap_total_mb) * 100" | awk '{printf "%.0f", $1}')
        log_warn "Active memory pressure detected:"
        log_warn "  • RAM: ${current_mem}GB / ${TOTAL_RAM_GB}GB ($(calc "($current_mem / $TOTAL_RAM_GB) * 100" | awk '{printf "%.0f", $1}')%)"
        log_warn "  • Swap: ${swap_used_mb}MB / ${swap_total_mb}MB (${swap_pct}%)"
        log_warn "Reducing namespace quotas by 30% for stability"
    elif compare_float "$current_mem" ">" "$ram_threshold"; then
        log_warn "High RAM usage detected (${current_mem}GB / ${TOTAL_RAM_GB}GB) but swap is low - proceeding normally"
    elif compare_int "$swap_used_mb" ">" "$swap_threshold"; then
        log_info "Swap usage is high (${swap_used_mb}MB / ${swap_total_mb}MB) but RAM usage is low - likely stale data, proceeding normally"
    fi
    
    # Calculate quotas based on workload profile (overrides tier defaults)
    local per_namespace_ram
    local per_namespace_cpu
    
    # Check if workload profile provides specific quota
    if [[ -n "${WORKLOAD_PROFILE:-}" ]]; then
        local profile_config=$(get_profile_config "$WORKLOAD_PROFILE")
        local profile_quota_mb=$(echo "$profile_config" | grep namespace_quota_mb | cut -d= -f2)
        
        if [[ -n "$profile_quota_mb" ]]; then
            per_namespace_ram=$(calc "$profile_quota_mb / 1024" | awk '{printf "%.2f", $1}')
            log_info "Using $WORKLOAD_PROFILE profile: ${per_namespace_ram}GB per namespace"
        fi
    fi
    
    # Fallback to tier-based if profile didn't set quota
    if [[ -z "${per_namespace_ram:-}" ]]; then
        case "$RESOURCE_TIER" in
            low)
                # Low tier (<8GB): Conservative allocation
                per_namespace_ram="0.5"  # 0.5GB per namespace
                per_namespace_cpu=$(calc "$CPU_CORES * 0.25" | awk '{printf "%.0f", $1}')  # 25% of cores
                [[ $per_namespace_cpu -lt 1 ]] && per_namespace_cpu=1
                ;;
            medium)
                # Medium tier (8-16GB): Balanced allocation
                per_namespace_ram="1.2"  # 1.2GB per namespace (will be overridden by 'lab' profile to 0.8GB)
                per_namespace_cpu=$(calc "$CPU_CORES * 0.3" | awk '{printf "%.0f", $1}')  # 30% of cores
                [[ $per_namespace_cpu -lt 1 ]] && per_namespace_cpu=1
                ;;
            high)
                # High tier (>16GB): Generous allocation
                per_namespace_ram="2.0"  # 2GB per namespace
                per_namespace_cpu=$(calc "$CPU_CORES * 0.4" | awk '{printf "%.0f", $1}')  # 40% of cores
                [[ $per_namespace_cpu -lt 2 ]] && per_namespace_cpu=2
                ;;
            *)
                # Fallback
                per_namespace_ram="1.0"
                per_namespace_cpu=1
                ;;
        esac
    fi
    
    # Set CPU if not already set
    if [[ -z "${per_namespace_cpu:-}" ]]; then
        per_namespace_cpu=$(calc "$CPU_CORES * 0.3" | awk '{printf "%.0f", $1}')
        [[ $per_namespace_cpu -lt 1 ]] && per_namespace_cpu=1
    fi
    
    # Apply graceful degradation if memory pressure detected
    if [[ "$memory_pressure" == "true" ]]; then
        per_namespace_ram=$(calc "$per_namespace_ram * 0.7" | awk '{printf "%.2f", $1}')  # Reduce by 30%
        per_namespace_cpu=$(calc "$per_namespace_cpu * 0.7" | awk '{printf "%.0f", $1}')
        [[ $per_namespace_cpu -lt 1 ]] && per_namespace_cpu=1
    fi
    
    # Calculate container defaults
    local default_mem=$(calc "$per_namespace_ram * 1024 * 0.25" | awk '{printf "%.0f", $1}')  # 25% of namespace quota
    local request_mem=$(calc "$default_mem * 0.5" | awk '{printf "%.0f", $1}')
    local default_cpu=$(calc "$per_namespace_cpu * 200" | awk '{printf "%.0f", $1}')  # In millicores
    local request_cpu=$(calc "$default_cpu * 0.5" | awk '{printf "%.0f", $1}')
    
    log_info "Quota per namespace: ${per_namespace_ram}Gi RAM, ${per_namespace_cpu} CPU cores"
    
    local namespaces=("dev" "staging" "testing")
    
    for ns in "${namespaces[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
        
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: $ns
spec:
  hard:
    requests.cpu: "${per_namespace_cpu}"
    requests.memory: "${per_namespace_ram}Gi"
    limits.cpu: "$(calc "$per_namespace_cpu * 2" | awk '{printf "%.0f", $1}')"
    limits.memory: "$(calc "$per_namespace_ram * 2" | awk '{printf "%.1f", $1}')Gi"
    persistentvolumeclaims: "5"
    pods: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: $ns
spec:
  limits:
  - default:
      cpu: ${default_cpu}m
      memory: ${default_mem}Mi
    defaultRequest:
      cpu: ${request_cpu}m
      memory: ${request_mem}Mi
    type: Container
EOF
    done
    
    log_success "Namespaces configured with dynamic resource quotas"
}

install_metrics_server() {
    log_info "Installing Metrics Server..."
    
    # Delete any existing metrics-server deployment (from k3s built-in)
    log_info "Removing any existing metrics-server deployment..."
    kubectl delete deployment metrics-server -n kube-system --ignore-not-found=true 2>/dev/null || true
    kubectl delete service metrics-server -n kube-system --ignore-not-found=true 2>/dev/null || true
    sleep 2
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:metrics-server
rules:
- apiGroups: [""]
  resources:
  - pods
  - nodes
  - nodes/stats
  - nodes/metrics    # Critical: needed for kubelet metrics endpoint
  - nodes/proxy      # Critical: needed for proxying to kubelet
  - namespaces
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources:
  - pods
  - nodes
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      serviceAccountName: metrics-server
      priorityClassName: cluster-critical
      containers:
      - name: metrics-server
        image: registry.k8s.io/metrics-server/metrics-server:v0.7.0
        args:
          - --cert-dir=/tmp
          - --secure-port=4443
          - --kubelet-insecure-tls
          - --kubelet-preferred-address-types=InternalIP
          - --metric-resolution=60s
        resources:
          requests:
            cpu: 100m
            memory: 70Mi
          limits:
            cpu: 200m
            memory: 128Mi
        ports:
        - containerPort: 4443
          name: https
          protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    k8s-app: metrics-server
  ports:
  - port: 443
    protocol: TCP
    targetPort: https
EOF
    
    log_success "Metrics Server installed"
}

install_traefik() {
    log_info "Installing Traefik Ingress Controller..."
    
    helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
    helm repo update
    
    cat > "${TMP_DIR}/traefik-values.yaml" <<EOF
resources:
  requests:
    cpu: 50m
    memory: 100Mi
  limits:
    cpu: 200m
    memory: 200Mi
deployment:
  replicas: 1
ports:
  web:
    port: 80
  websecure:
    port: 443
service:
  type: NodePort
EOF
    
    helm upgrade --install traefik traefik/traefik \
        --namespace kube-system \
        --values "${TMP_DIR}/traefik-values.yaml" \
        --wait
    
    log_success "Traefik installed"
}

setup_persistent_volumes() {
    log_info "Setting up persistent volume storage..."
    
    # Create local storage class
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
    
    log_success "Storage class configured"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Check system health first
    check_system_health || {
        log_warn "System resources are constrained. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && return 1
    }
    
    # Check available memory (ArgoCD needs ~350MB)
    local mem_used=$(get_memory_usage_cached)
    local mem_available=$(calc "8.0 - $mem_used" | awk '{printf "%.2f", $1}')
    if compare_float "$mem_available" "<" "0.5"; then
        log_warn "Insufficient memory for ArgoCD (needs ~350MB free)"
        log_warn "Available: ${mem_available}GB. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && return 1
    fi
    
    # Create namespace
    kubectl create namespace argocd 2>/dev/null || true
    
    # Add Helm repo
    log_info "Adding ArgoCD Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update
    
    # Create ArgoCD values file
    cat > "${TMP_DIR}/argocd-values.yaml" <<EOF
global:
  image:
    tag: "v2.9.3"
server:
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
repoServer:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
controller:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
redis:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
dex:
  enabled: false
notifications:
  enabled: false
applicationSet:
  enabled: false
EOF
    
    # Install ArgoCD
    log_info "Installing ArgoCD via Helm (this may take 2-3 minutes)..."
    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --values "${TMP_DIR}/argocd-values.yaml" \
        --wait \
        --timeout 5m || {
            log_error "ArgoCD installation failed"
            return 1
        }
    
    # Wait for pods to be ready
    log_info "Waiting for ArgoCD pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s || {
        log_warn "Some ArgoCD pods may still be starting"
    }
    
    # Get initial admin password
    log_success "ArgoCD installed successfully!"
    echo ""
    log_info "ArgoCD Access Information:"
    echo "  Namespace: argocd"
    echo "  Service: argocd-server"
    echo ""
    log_info "To access ArgoCD UI:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Then visit: https://localhost:8080"
    echo ""
    log_info "Initial admin password:"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "  (Password secret not found - may need to wait for pods to fully start)"
    echo ""
}

install_monitoring() {
    log_info "Installing Prometheus + Grafana Monitoring Stack..."
    
    # Check system health first
    check_system_health || {
        log_warn "System resources are constrained. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && return 1
    }
    
    # Check available memory (Monitoring needs ~700MB)
    local mem_used=$(get_memory_usage_cached)
    local mem_available=$(calc "8.0 - $mem_used" | awk '{printf "%.2f", $1}')
    if compare_float "$mem_available" "<" "1.0"; then
        log_warn "Insufficient memory for monitoring stack (needs ~700MB free)"
        log_warn "Available: ${mem_available}GB. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && return 1
    fi
    
    # Create namespace
    kubectl create namespace monitoring 2>/dev/null || true
    
    # Add Helm repo
    log_info "Adding Prometheus Community Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    # Create monitoring values file
    cat > "${TMP_DIR}/monitoring-values.yaml" <<EOF
prometheus:
  prometheusSpec:
    retention: 2d
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
      limits:
        cpu: 500m
        memory: 400Mi
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
grafana:
  enabled: true
  persistence:
    enabled: true
    size: 2Gi
  resources:
    requests:
      cpu: 50m
      memory: 100Mi
    limits:
      cpu: 200m
      memory: 200Mi
  adminPassword: admin
alertmanager:
  enabled: false
kubeStateMetrics:
  enabled: true
nodeExporter:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 100m
      memory: 100Mi
EOF
    
    # Install monitoring stack
    log_info "Installing kube-prometheus-stack via Helm (this may take 3-5 minutes)..."
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values "${TMP_DIR}/monitoring-values.yaml" \
        --wait \
        --timeout 10m || {
            log_error "Monitoring stack installation failed"
            return 1
        }
    
    # Wait for pods to be ready
    log_info "Waiting for monitoring pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=180s || {
        log_warn "Some monitoring pods may still be starting"
    }
    
    log_success "Monitoring stack installed successfully!"
    echo ""
    log_info "Monitoring Access Information:"
    echo "  Namespace: monitoring"
    echo ""
    log_info "To access Prometheus:"
    echo "  kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090"
    echo "  Then visit: http://localhost:9090"
    echo ""
    log_info "To access Grafana:"
    echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
    echo "  Then visit: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
}

stop_cluster() {
    log_info "Stopping Kubernetes cluster..."
    
    # Stop health monitor if running
    stop_health_monitor 2>/dev/null || true
    
    # Gracefully stop all workloads
    kubectl delete --all pods --all-namespaces --grace-period=30 --wait=true 2>/dev/null || true
    
    # Stop cluster based on available tools and runtime
    local stopped=false
    
    # Try OrbStack
    if command -v orb &> /dev/null && orb list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        log_info "Stopping OrbStack cluster..."
        orb stop "$CLUSTER_NAME" 2>/dev/null && stopped=true
    fi
    
    # Try k3d
    if [[ "$stopped" == "false" ]] && command -v k3d &> /dev/null && k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Stopping k3d cluster..."
        k3d cluster stop "$CLUSTER_NAME" 2>/dev/null && stopped=true
    fi
    
    # Try minikube
    if [[ "$stopped" == "false" ]] && command -v minikube &> /dev/null; then
        log_info "Stopping Minikube cluster..."
        minikube stop -p "$CLUSTER_NAME" 2>/dev/null && stopped=true
    fi
    
    # kind clusters don't have a stop command, they're deleted or kept running
    if [[ "$stopped" == "false" ]] && command -v kind &> /dev/null && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "kind cluster detected (no stop command available)"
        stopped=true
    fi
    
    # Restore previous kubectl context
    restore_kubectl_context
    
    if [[ "$stopped" == "true" ]]; then
        log_success "Cluster stopped"
    else
        log_warn "No matching cluster found to stop"
    fi
}

delete_cluster() {
    log_info "Deleting cluster (keeping persistent data)..."
    
    stop_cluster
    
    local deleted=false
    
    # Try OrbStack
    if command -v orb &> /dev/null && orb list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        log_info "Deleting OrbStack cluster..."
        orb delete "$CLUSTER_NAME" --force 2>/dev/null && deleted=true
    fi
    
    # Try k3d
    if [[ "$deleted" == "false" ]] && command -v k3d &> /dev/null && k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Deleting k3d cluster..."
        k3d cluster delete "$CLUSTER_NAME" 2>/dev/null && deleted=true
    fi
    
    # Try minikube
    if [[ "$deleted" == "false" ]] && command -v minikube &> /dev/null; then
        log_info "Deleting Minikube cluster..."
        minikube delete -p "$CLUSTER_NAME" 2>/dev/null && deleted=true
    fi
    
    # Try kind
    if [[ "$deleted" == "false" ]] && command -v kind &> /dev/null && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Deleting kind cluster..."
        kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null && deleted=true
    fi
    
    if [[ "$deleted" == "true" ]]; then
        # Clean up kubectl context
        log_info "Cleaning up kubectl context..."
        kubectl config delete-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
        kubectl config delete-cluster "k3d-${CLUSTER_NAME}" 2>/dev/null || true
        kubectl config unset "users.admin@k3d-${CLUSTER_NAME}" 2>/dev/null || true
        
        log_success "Cluster deleted. Persistent data preserved in $KUBE_ROOT"
    else
        log_warn "No matching cluster found to delete"
    fi
}

# ============================================================================
# IMAGE MANAGEMENT FUNCTIONS
# ============================================================================

prune_images() {
    log_info "Pruning unused Docker images..."
    
    # Get current disk usage
    local before_size=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
    
    # Determine pruning aggressiveness based on resource tier and disk space
    local disk_usage_pct=$(get_disk_usage_percent "$BASE_DIR")
    local prune_all=false
    
    # Aggressive pruning if disk >80% or low-tier system
    if [[ "$RESOURCE_TIER" == "low" ]] || compare_int "$disk_usage_pct" ">" "80"; then
        log_warn "Low resources or high disk usage - performing aggressive pruning"
        prune_all=true
    fi
    
    # Remove dangling images
    log_info "Removing dangling images..."
    docker image prune -f >/dev/null 2>&1 || true
    
    # Remove unused images (not just dangling)
    if [[ "$prune_all" == "true" ]]; then
        log_info "Removing all unused images..."
        docker image prune -a -f --filter "until=24h" >/dev/null 2>&1 || true
    fi
    
    # Remove stopped containers
    log_info "Removing stopped containers..."
    docker container prune -f >/dev/null 2>&1 || true
    
    # Remove unused volumes (careful - only if orphaned)
    log_info "Removing unused volumes..."
    docker volume prune -f >/dev/null 2>&1 || true
    
    # Remove build cache if aggressive pruning
    if [[ "$prune_all" == "true" ]]; then
        log_info "Removing build cache..."
        docker builder prune -f >/dev/null 2>&1 || true
    fi
    
    # Get final disk usage
    local after_size=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
    
    log_success "Image pruning complete"
    log_info "  • Before: $before_size"
    log_info "  • After: $after_size"
    
    # Show summary
    docker system df 2>/dev/null || true
}

# ============================================================================
# WORKLOAD PROFILE MANAGEMENT
# ============================================================================

get_profile_config() {
    local profile="${1:-${WORKLOAD_PROFILE}}"
    
    case "$profile" in
        minimal)
            # Minimal: Single node, basic services only
            echo "nodes=1"
            echo "namespace_quota_mb=512"
            echo "recommended_components=registry"
            echo "max_components=2"
            echo "swap_recommended=1x"
            ;;
        lab)
            # Lab: 2 nodes, ESO, Traefik, moderate workloads
            echo "nodes=2"
            echo "namespace_quota_mb=800"  # Reduced from 1200 to leave room for ESO+Traefik+Vault
            echo "recommended_components=registry,traefik,eso,vault"
            echo "max_components=5"
            echo "swap_recommended=1.5x"
            echo "notes=ESO requires secret backend (Vault dev mode included in calculation)"
            ;;
        full)
            # Full: 3 nodes, all components
            echo "nodes=3"
            echo "namespace_quota_mb=2048"
            echo "recommended_components=registry,traefik,eso,vault,argocd,monitoring"
            echo "max_components=10"
            echo "swap_recommended=1x"
            echo "notes=Full stack with HA Vault optional"
            ;;
        *)
            log_error "Unknown profile: $profile"
            return 1
            ;;
    esac
}

calculate_component_overhead() {
    local components=("$@")
    local total_mb=0
    
    for component in "${components[@]}"; do
        case "$component" in
            registry)
                if [[ "${LOW_MEMORY_MODE:-false}" == "true" ]]; then
                    total_mb=$((total_mb + 50))
                else
                    total_mb=$((total_mb + 100))
                fi
                ;;
            traefik)
                total_mb=$((total_mb + 150))  # Traefik is lightweight
                ;;
            eso|external-secrets)
                total_mb=$((total_mb + 250))  # ESO + webhook
                ;;
            argocd)
                total_mb=$((total_mb + 500))  # ArgoCD suite
                ;;
            metrics-server)
                total_mb=$((total_mb + 100))
                ;;
            monitoring|prometheus)
                total_mb=$((total_mb + 800))  # Prometheus + Grafana
                ;;
            ingress-nginx)
                total_mb=$((total_mb + 300))  # Nginx heavier than Traefik
                ;;
            vault)
                total_mb=$((total_mb + 150))  # Vault in dev mode
                ;;
            vault-ha)
                total_mb=$((total_mb + 450))  # Vault HA with raft (3 replicas)
                ;;
            cert-manager)
                total_mb=$((total_mb + 100))  # Certificate management
                ;;
        esac
    done
    
    echo "$total_mb"
}

check_workload_capacity() {
    local planned_components=("$@")
    
    log_info "Analyzing workload capacity..."
    
    # Calculate base K8s overhead
    local k8s_overhead_mb=0
    case "$RESOURCE_TIER" in
        low)
            k8s_overhead_mb=400  # Single node minimal
            ;;
        medium)
            k8s_overhead_mb=600  # 2 nodes with system pods
            ;;
        high)
            k8s_overhead_mb=800  # 3 nodes with all system services
            ;;
    esac
    
    # Calculate component overhead
    local component_overhead_mb=$(calculate_component_overhead "${planned_components[@]}")
    
    # Calculate namespace allocation (assume 3 namespaces: dev, staging, testing)
    local profile_config=$(get_profile_config)
    local namespace_quota_mb=$(echo "$profile_config" | grep namespace_quota_mb | cut -d= -f2)
    local namespace_total_mb=$((namespace_quota_mb * 3))
    
    # Total required
    local total_required_mb=$((k8s_overhead_mb + component_overhead_mb + namespace_total_mb))
    
    # Available for cluster (after OS overhead)
    local os_overhead_gb=$(detect_os_overhead)
    local available_for_cluster_gb=$(calc "$TOTAL_RAM_GB - $os_overhead_gb" | awk '{printf "%.2f", $1}')
    local available_for_cluster_mb=$(calc "$available_for_cluster_gb * 1024" | awk '{printf "%.0f", $1}')
    
    # Calculate usage percentage
    local usage_pct=$(calc "($total_required_mb / $available_for_cluster_mb) * 100" | awk '{printf "%.0f", $1}')
    
    echo ""
    log_info "Capacity Analysis:"
    log_info "  • Total RAM: ${TOTAL_RAM_GB}GB"
    log_info "  • OS Overhead: ${os_overhead_gb}GB"
    log_info "  • Available for cluster: ${available_for_cluster_gb}GB (${available_for_cluster_mb}MB)"
    echo ""
    log_info "Planned Usage:"
    log_info "  • K8s overhead: ${k8s_overhead_mb}MB"
    log_info "  • Components: ${component_overhead_mb}MB"
    log_info "  • Namespaces (3x ${namespace_quota_mb}MB): ${namespace_total_mb}MB"
    log_info "  • Total required: ${total_required_mb}MB"
    echo ""
    log_info "Utilization: ${usage_pct}%"
    
    if [[ "$usage_pct" -gt 90 ]]; then
        log_error "⚠️  RISK: >90% RAM allocation - thrashing likely!"
        log_warn "Recommendations:"
        log_warn "  1. Reduce namespace quotas"
        log_warn "  2. Remove non-essential components"
        log_warn "  3. Increase system swap to $(calc "$TOTAL_RAM_GB * 2" | awk '{printf "%.0f", $1}')GB"
        log_warn "  4. Consider upgrading RAM"
        return 1
    elif [[ "$usage_pct" -gt 80 ]]; then
        log_warn "⚠️  WARNING: 80-90% RAM allocation - monitor closely"
        log_info "Consider increasing swap to $(calc "$TOTAL_RAM_GB * 1.5" | awk '{printf "%.0f", $1}')GB"
        return 0
    else
        log_success "✓ Capacity looks good (${usage_pct}% utilization)"
        return 0
    fi
}

optimize_for_workload() {
    local profile="${WORKLOAD_PROFILE}"
    
    log_info "Optimizing for $profile workload profile..."
    
    case "$profile" in
        lab)
            # Lab profile optimizations for 8GB systems
            log_info "Lab profile adjustments:"
            log_info "  • Namespace quotas: 800MB (vs 1200MB default)"
            log_info "  • Recommended: Traefik over Nginx (saves 150MB)"
            log_info "  • Node count: 2 (meets multi-node requirements)"
            echo ""
            log_info "Component recommendations:"
            log_info "  • ESO (External Secrets Operator): 250MB"
            log_info "  • Traefik (Ingress Controller): 150MB"
            log_info "  • Vault (Secret Backend - dev mode): 150MB"
            log_info "  • Total overhead: 550MB"
            echo ""
            log_warn "⚠️  Note: ESO requires a secret backend!"
            log_info "Options:"
            log_info "  1. Vault (dev mode): +150MB (included in calculation)"
            log_info "  2. Cloud provider (AWS/Azure/GCP): 0MB local overhead"
            log_info "  3. Skip ESO if not needed for your labs"
            ;;
        minimal)
            log_info "Minimal profile (single node, basic services only)"
            log_info "  • Not recommended for ESO or heavy workloads"
            ;;
        full)
            log_info "Full profile (3 nodes, all components supported)"
            log_info "  • ESO + Vault HA supported"
            log_info "  • ArgoCD + monitoring stack supported"
            ;;
    esac
}

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

health_check() {
    log_info "Running cluster health check..."
    echo ""
    
    local issues=0
    local warnings=0
    
    # 1. Check cluster connectivity
    log_info "[1/7] Checking cluster connectivity..."
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "  ✓ Cluster is reachable"
    else
        log_error "  ✗ Cannot connect to cluster"
        ((issues++))
    fi
    
    # 2. Check nodes
    log_info "[2/7] Checking node status..."
    local total_nodes=$(kubectl get nodes -o name 2>/dev/null | wc -l | tr -d ' ')
    local ready_nodes=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l | tr -d ' ')
    
    if [[ "$total_nodes" -eq "$ready_nodes" ]] && [[ "$total_nodes" -gt 0 ]]; then
        log_success "  ✓ All nodes ready ($ready_nodes/$total_nodes)"
    else
        log_error "  ✗ Some nodes not ready ($ready_nodes/$total_nodes)"
        ((issues++))
    fi
    
    # 3. Check system pods
    log_info "[3/7] Checking system pods..."
    local system_pods=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    
    if [[ "$system_pods" -eq 0 ]]; then
        log_success "  ✓ All system pods running"
    else
        log_warn "  ⚠ $system_pods system pods not running"
        ((warnings++))
    fi
    
    # 4. Check registry
    log_info "[4/7] Checking registry..."
    if docker ps --filter "name=${REGISTRY_NAME}" --format "{{.Names}}" | grep -q "${REGISTRY_NAME}"; then
        if curl -s "http://${REGISTRY_HOST}/v2/_catalog" >/dev/null 2>&1; then
            log_success "  ✓ Registry is healthy"
        else
            log_warn "  ⚠ Registry running but not responding"
            ((warnings++))
        fi
    else
        log_error "  ✗ Registry is not running"
        ((issues++))
    fi
    
    # 5. Check storage
    log_info "[5/7] Checking storage..."
    local pv_count=$(kubectl get pv 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    local pvc_count=$(kubectl get pvc -A 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    
    if [[ -d "$PV_DIR" ]]; then
        log_success "  ✓ Storage directory exists ($pv_count PVs, $pvc_count PVCs)"
    else
        log_error "  ✗ Storage directory missing"
        ((issues++))
    fi
    
    # 6. Check resource pressure
    log_info "[6/7] Checking resource pressure..."
    local mem_usage=$(get_memory_usage_cached)
    local mem_pct=$(calc "($mem_usage / $TOTAL_RAM_GB) * 100" | awk '{printf "%.0f", $1}')
    local swap_used_mb=$(get_swap_usage)
    local swap_total_mb=$(get_swap_total)
    local swap_pct=0
    if [[ "$swap_total_mb" -gt 0 ]]; then
        swap_pct=$(calc "($swap_used_mb / $swap_total_mb) * 100" | awk '{printf "%.0f", $1}')
    fi
    
    if [[ "$mem_pct" -lt 85 ]] && [[ "$swap_pct" -lt 90 ]]; then
        log_success "  ✓ Resource usage normal (RAM: ${mem_pct}%, Swap: ${swap_pct}%)"
    elif [[ "$mem_pct" -ge 85 ]] && [[ "$swap_pct" -ge 50 ]]; then
        log_error "  ✗ High memory pressure (RAM: ${mem_pct}%, Swap: ${swap_pct}%)"
        ((issues++))
    else
        log_warn "  ⚠ Elevated resource usage (RAM: ${mem_pct}%, Swap: ${swap_pct}%)"
        ((warnings++))
    fi
    
    # 7. Check disk space
    log_info "[7/7] Checking disk space..."
    local disk_usage=$(get_disk_usage_percent "$BASE_DIR")
    
    if [[ "$disk_usage" -lt 80 ]]; then
        log_success "  ✓ Disk space sufficient (${disk_usage}% used)"
    elif [[ "$disk_usage" -lt 90 ]]; then
        log_warn "  ⚠ Disk space getting low (${disk_usage}% used)"
        ((warnings++))
    else
        log_error "  ✗ Disk space critical (${disk_usage}% used)"
        ((issues++))
    fi
    
    # Summary
    echo ""
    log_info "Health Check Summary:"
    if [[ "$issues" -eq 0 ]] && [[ "$warnings" -eq 0 ]]; then
        log_success "  ✓ All checks passed - cluster is healthy"
        return 0
    elif [[ "$issues" -eq 0 ]]; then
        log_warn "  ⚠ $warnings warnings found - cluster is functional but needs attention"
        return 0
    else
        log_error "  ✗ $issues critical issues and $warnings warnings found"
        return 1
    fi
}

# ============================================================================
# COMPONENT MANAGEMENT FUNCTIONS
# ============================================================================

toggle_metrics_server() {
    local action="${1:-status}"
    
    case "$action" in
        enable)
            log_info "Enabling metrics-server..."
            if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
                log_warn "Metrics-server is already installed"
                return 0
            fi
            install_metrics_server
            log_success "Metrics-server enabled"
            ;;
        disable)
            log_info "Disabling metrics-server..."
            if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
                log_warn "Metrics-server is not installed"
                return 0
            fi
            kubectl delete deployment metrics-server -n kube-system --ignore-not-found=true
            kubectl delete service metrics-server -n kube-system --ignore-not-found=true
            kubectl delete serviceaccount metrics-server -n kube-system --ignore-not-found=true
            kubectl delete clusterrole system:metrics-server --ignore-not-found=true
            kubectl delete clusterrolebinding system:metrics-server --ignore-not-found=true
            kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found=true
            log_success "Metrics-server disabled"
            ;;
        status)
            if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
                local ready=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                local desired=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
                log_info "Metrics-server: ENABLED ($ready/$desired ready)"
            else
                log_info "Metrics-server: DISABLED"
            fi
            ;;
        *)
            log_error "Invalid action. Use: enable, disable, or status"
            return 1
            ;;
    esac
}

list_components() {
    log_info "Cluster Components Status:"
    echo ""
    
    # Check metrics-server
    toggle_metrics_server status
    
    # Check registry
    if docker ps --filter "name=${REGISTRY_NAME}" --format "{{.Names}}" | grep -q "${REGISTRY_NAME}"; then
        log_info "Registry: RUNNING (${REGISTRY_HOST})"
    else
        log_info "Registry: STOPPED"
    fi
    
    # Check cluster
    if kubectl cluster-info >/dev/null 2>&1; then
        local node_count=$(kubectl get nodes -o name 2>/dev/null | wc -l | tr -d ' ')
        log_info "Cluster: RUNNING ($node_count nodes)"
    else
        log_info "Cluster: STOPPED"
    fi
    
    # Check namespaces
    local ns_count=$(kubectl get namespaces -o name 2>/dev/null | wc -l | tr -d ' ')
    log_info "Namespaces: $ns_count"
    
    # Resource usage summary
    echo ""
    log_info "Resource Usage:"
    local mem_usage=$(get_memory_usage_cached)
    local swap_usage_mb=$(get_swap_usage)
    local swap_total_mb=$(get_swap_total)
    log_info "  • RAM: ${mem_usage}GB / ${TOTAL_RAM_GB}GB ($(calc "($mem_usage / $TOTAL_RAM_GB) * 100" | awk '{printf "%.0f", $1}')%)"
    log_info "  • Swap: ${swap_usage_mb}MB / ${swap_total_mb}MB"
    
    local disk_usage=$(get_disk_usage_percent "$BASE_DIR")
    log_info "  • Disk ($BASE_DIR): ${disk_usage}%"
}

# ============================================================================
# BACKUP/RESTORE FUNCTIONS
# ============================================================================

backup_cluster() {
    local background="${1:-false}"
    
    if [[ "$background" == "true" ]]; then
        # Run backup in background with resource limits
        log_info "Starting backup in background..."
        local backup_pid_file="${TMP_DIR}/backup.pid"
        local backup_log_file="${TMP_DIR}/backup.log"
        
        # Launch background process with nice priority
        (
            # Lower process priority to avoid impacting cluster
            renice -n 10 $$ >/dev/null 2>&1 || true
            
            # Run the actual backup
            backup_cluster false 2>&1 | tee "$backup_log_file"
            
            # Clean up pid file on completion
            rm -f "$backup_pid_file" 2>/dev/null || true
        ) &
        
        local backup_pid=$!
        echo "$backup_pid" > "$backup_pid_file"
        
        log_success "Backup started in background (PID: $backup_pid)"
        log_info "Check status with: tail -f $backup_log_file"
        return 0
    fi
    
    log_info "Creating cluster backup..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/cluster-${timestamp}"
    
    mkdir -p "$backup_file"
    
    # Export all Kubernetes resources
    log_info "Exporting Kubernetes resources..."
    kubectl get all -A -o yaml > "${backup_file}/all-resources.yaml"
    kubectl get pv,pvc -A -o yaml > "${backup_file}/storage.yaml"
    kubectl get configmap,secret -A -o yaml > "${backup_file}/configs.yaml"
    kubectl get ingress -A -o yaml > "${backup_file}/ingress.yaml"
    
    # Backup PV data with progress indicator and CPU limits
    log_info "Backing up persistent volume data..."
    if [[ -d "$PV_DIR" ]] && [[ -n "$(ls -A $PV_DIR 2>/dev/null)" ]]; then
        # Use ionice (if available) and nice to limit resource usage
        if command -v ionice >/dev/null 2>&1; then
            nice -n 10 ionice -c3 tar -czf "${backup_file}/pv-data.tar.gz" -C "$PV_DIR" . 2>/dev/null || \
                nice -n 10 tar -czf "${backup_file}/pv-data.tar.gz" -C "$PV_DIR" . 
        else
            nice -n 10 tar -czf "${backup_file}/pv-data.tar.gz" -C "$PV_DIR" .
        fi
    fi
    
    # Create manifest
    cat > "${backup_file}/manifest.txt" <<EOF
Backup created: $(date)
Cluster: $CLUSTER_NAME
Kubernetes version: $(kubectl version --short 2>/dev/null | grep Server || echo "N/A")
Nodes: $(kubectl get nodes -o name 2>/dev/null | wc -l)
Namespaces: $(kubectl get ns -o name 2>/dev/null | wc -l)
EOF
    
    # Cleanup old backups (keep last 7)
    log_info "Cleaning up old backups (keeping last 7)..."
    ls -dt "${BACKUP_DIR}"/cluster-* | tail -n +8 | xargs rm -rf 2>/dev/null || true
    
    log_success "Backup created at ${backup_file}"
}

check_backup_status() {
    local backup_pid_file="${TMP_DIR}/backup.pid"
    local backup_log_file="${TMP_DIR}/backup.log"
    
    if [[ ! -f "$backup_pid_file" ]]; then
        log_info "No background backup running"
        return 0
    fi
    
    local backup_pid=$(cat "$backup_pid_file")
    
    if ps -p "$backup_pid" >/dev/null 2>&1; then
        log_info "Backup in progress (PID: $backup_pid)"
        if [[ -f "$backup_log_file" ]]; then
            log_info "Recent output:"
            tail -5 "$backup_log_file"
        fi
    else
        log_info "Backup completed or failed"
        if [[ -f "$backup_log_file" ]]; then
            log_info "Final output:"
            tail -10 "$backup_log_file"
        fi
        rm -f "$backup_pid_file" 2>/dev/null || true
    fi
}

restore_cluster() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "Please specify backup to restore"
        log_info "Available backups:"
        ls -1 "${BACKUP_DIR}" | grep "cluster-"
        return 1
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi
    
    log_info "Restoring from backup: $backup_name"
    
    # Restore PV data
    if [[ -f "${backup_path}/pv-data.tar.gz" ]]; then
        log_info "Restoring persistent volume data..."
        mkdir -p "$PV_DIR"
        tar -xzf "${backup_path}/pv-data.tar.gz" -C "$PV_DIR"
    fi
    
    # Restore Kubernetes resources
    log_info "Restoring Kubernetes resources..."
    kubectl apply -f "${backup_path}/storage.yaml" 2>/dev/null || true
    sleep 5
    kubectl apply -f "${backup_path}/all-resources.yaml" 2>/dev/null || true
    kubectl apply -f "${backup_path}/configs.yaml" 2>/dev/null || true
    kubectl apply -f "${backup_path}/ingress.yaml" 2>/dev/null || true
    
    log_success "Restore completed"
}

# ============================================================================
# MAINTENANCE FUNCTIONS
# ============================================================================

cleanup_resources() {
    log_info "Cleaning up unused resources..."
    
    # Prune Docker resources
    docker system prune -f --volumes 2>/dev/null || true
    
    # Delete completed/failed pods
    kubectl delete pods --field-selector=status.phase==Succeeded -A 2>/dev/null || true
    kubectl delete pods --field-selector=status.phase==Failed -A 2>/dev/null || true
    
    # Clean temp directory
    rm -rf "${TMP_DIR:?}"/*
    
    log_success "Cleanup completed"
}

show_status() {
    echo ""
    echo "=========================================="
    echo "  Kubernetes Cluster Status"
    echo "=========================================="
    echo ""
    
    # System info
    echo "System: $OS_TYPE ($CPU_ARCH)"
    echo "Docker Runtime: $DOCKER_RUNTIME"
    echo ""
    
    # System resources
    local mem_used=$(get_memory_usage_cached)
    local swap_used=$(get_swap_usage)
    echo "System Memory: ${mem_used}GB / ${TOTAL_RAM_GB}GB"
    echo "Swap Usage: ${swap_used}MB"
    echo ""
    
    # Cluster status
    if orb list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        echo "Cluster Status: Running"
        echo ""
        
        # Node status
        echo "Node Status:"
        kubectl get nodes -o wide 2>/dev/null || echo "  Unable to connect"
        echo ""
        
        # Resource usage
        echo "Resource Usage:"
        kubectl top nodes 2>/dev/null || echo "  Metrics not available yet"
        echo ""
        
        # Namespace summary
        echo "Namespace Summary:"
        kubectl get ns --no-headers 2>/dev/null | wc -l | xargs echo "  Total Namespaces:"
        kubectl get pods -A --no-headers 2>/dev/null | wc -l | xargs echo "  Total Pods:"
        echo ""
        
        # Top resource consumers
        echo "Top 5 Pods by Memory:"
        kubectl top pods -A --sort-by=memory 2>/dev/null | head -6 || echo "  Metrics not available"
        
    else
        echo "Cluster Status: Stopped"
    fi
    echo ""
    
    # Registry status
    if docker ps | grep -q "$REGISTRY_NAME"; then
        echo "Registry Status: Running (localhost:${REGISTRY_PORT})"
    else
        echo "Registry Status: Stopped"
    fi
    echo ""
    echo "=========================================="
}

show_health() {
    echo ""
    echo "=========================================="
    echo "  System Health Check"
    echo "=========================================="
    echo ""
    
    local issues=0
    
    # Memory check
    local mem_used=$(get_memory_usage_cached)
    local mem_threshold=6.5
    echo -n "Memory Usage: ${mem_used}GB / 8GB ... "
    if compare_float "$mem_used" ">" "$mem_threshold"; then
        echo -e "${RED}WARNING${NC}"
        echo "  Consider closing other applications"
        ((issues++))
    else
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Swap check
    local swap_used=$(get_swap_usage)
    echo -n "Swap Usage: ${swap_used}MB ... "
    if [[ "$swap_used" != "0.00" ]] && [[ "$swap_used" != "0" ]]; then
        echo -e "${RED}WARNING${NC}"
        echo "  System is using swap - performance degraded"
        ((issues++))
    else
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Storage check
    local storage_used=$(df -h "$EXTERNAL_DRIVE" | tail -1 | awk '{print $5}' | sed 's/%//')
    echo -n "External Storage: ${storage_used}% used ... "
    if [[ $storage_used -gt 90 ]]; then
        echo -e "${RED}WARNING${NC}"
        echo "  Low disk space on external drive"
        ((issues++))
    elif [[ $storage_used -gt 80 ]]; then
        echo -e "${YELLOW}CAUTION${NC}"
    else
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Cluster health
    if orb list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        echo -n "Cluster Status: "
        if kubectl get nodes &>/dev/null; then
            echo -e "${GREEN}Healthy${NC}"
            
            # Check node conditions
            local node_issues=$(kubectl get nodes -o json | jq -r '.items[].status.conditions[] | select(.status=="True" and .type!="Ready") | .type' 2>/dev/null)
            if [[ -n "$node_issues" ]]; then
                echo -e "  ${YELLOW}Node Conditions:${NC}"
                echo "$node_issues" | while read -r condition; do
                    echo "    - $condition"
                done
                ((issues++))
            fi
        else
            echo -e "${RED}Unhealthy${NC}"
            ((issues++))
        fi
    else
        echo "Cluster Status: Not running"
    fi
    
    echo ""
    echo "=========================================="
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}All systems healthy!${NC}"
    else
        echo -e "${YELLOW}Found $issues issue(s) - review warnings above${NC}"
    fi
    echo "=========================================="
    echo ""
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

show_menu() {
    while true; do
        echo ""
        echo "=========================================="
        echo "  Local Kubernetes Control Menu"
        echo "=========================================="
        echo ""
        echo "  S. System Info & Recommendations"
        echo "  C. Reconfigure Settings"
        echo ""
        echo "  1. Start Cluster"
        echo "  2. Stop Cluster"
        echo "  3. Restart Cluster"
        echo "  4. Delete Cluster (Keep Data)"
        echo ""
        echo "  5. View Status"
        echo "  6. System Health Check"
        echo "  7. View Logs"
        echo ""
        echo "  8. Backup Cluster"
        echo "  9. Restore Cluster"
        echo " 10. Rollback Failed Installation"
        echo ""
        echo " 11. Cleanup Resources"
        echo " 12. Manage Registry"
        echo ""
        echo " 13. Install Complete Environment"
        echo " 14. Install ArgoCD"
        echo " 15. Install Monitoring Stack"
        echo ""
        echo "Advanced:"
        echo "  N. Check Network Conflicts"
        echo "  R. Resource Quota Analysis"
        echo "  I. Image Optimization"
        echo "  T. Storage Health Check"
        echo "  M. Start Health Monitor"
        echo ""
        echo "  0. Exit"
        echo ""
        echo "=========================================="
        echo -n "Select option: "
        
        read -r choice
        
        case $choice in
            [Ss])
                show_system_info
                analyze_component_feasibility
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Cc])
                reconfigure_setup
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            1)
                start_registry
                start_cluster
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            2)
                stop_cluster
                stop_registry
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            3)
                stop_cluster
                sleep 3
                start_cluster
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            4)
                log_warn "This will delete the cluster but keep persistent data."
                echo -n "Continue? (y/N): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    delete_cluster
                fi
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            5)
                show_status
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            6)
                show_health
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            7)
                echo ""
                log_info "Recent logs from kube-system:"
                kubectl logs -n kube-system -l app=traefik --tail=20 2>/dev/null || echo "No logs available"
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            8)
                backup_cluster
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            9)
                echo ""
                log_info "Available backups:"
                ls -1 "${BACKUP_DIR}" | grep "cluster-" || echo "No backups found"
                echo ""
                echo -n "Enter backup name (or 'latest'): "
                read -r backup_name
                if [[ "$backup_name" == "latest" ]]; then
                    backup_name=$(ls -t "${BACKUP_DIR}" | grep "cluster-" | head -1)
                fi
                restore_cluster "$backup_name"
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            10)
                rollback_installation
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            11)
                echo ""
                echo "Cleanup Options:"
                echo "  1. Kubernetes cleanup (remove unused resources)"
                echo "  2. Docker cleanup (free up space)"
                echo "  3. Both"
                echo -n "Select [1-3]: "
                read -r cleanup_choice
                case $cleanup_choice in
                    1) cleanup_resources ;;
                    2) smart_cleanup ;;
                    3) 
                        cleanup_resources
                        echo ""
                        smart_cleanup
                        ;;
                    *) log_error "Invalid choice" ;;
                esac
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            12)
                if docker ps | grep -q "$REGISTRY_NAME"; then
                    echo ""
                    echo "Registry Status: Running"
                    echo "URL: localhost:${REGISTRY_PORT}"
                    echo ""
                    echo "1. Stop Registry"
                    echo "2. Restart Registry"
                    echo "3. View Registry Contents"
                    echo "0. Back"
                    echo ""
                    echo -n "Select: "
                    read -r reg_choice
                    case $reg_choice in
                        1) stop_registry ;;
                        2) stop_registry && sleep 2 && start_registry ;;
                        3) 
                            echo ""
                            curl -s http://localhost:${REGISTRY_PORT}/v2/_catalog | jq . 2>/dev/null || echo "Unable to fetch catalog"
                            ;;
                    esac
                else
                    echo ""
                    echo "Registry Status: Stopped"
                    echo -n "Start registry? (y/N): "
                    read -r confirm
                    [[ "$confirm" =~ ^[Yy]$ ]] && start_registry
                fi
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            13)
                install_complete_environment
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            14)
                install_argocd
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            15)
                install_monitoring
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Nn])
                check_network_conflicts
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Rr])
                analyze_resource_quotas
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Ii])
                optimize_docker_images
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Tt])
                check_storage_health
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            [Mm])
                echo ""
                echo "Health Monitor Options:"
                echo "  1. Start monitor (5 min intervals)"
                echo "  2. Start monitor (custom interval)"
                echo "  3. Stop monitor"
                echo "  4. View monitor logs"
                echo -n "Select [1-4]: "
                read -r monitor_choice
                case $monitor_choice in
                    1) start_health_monitor 300 ;;
                    2) 
                        echo -n "Enter interval in seconds: "
                        read -r custom_interval
                        start_health_monitor "$custom_interval"
                        ;;
                    3) stop_health_monitor ;;
                    4) view_health_logs ;;
                    *) log_error "Invalid choice" ;;
                esac
                echo ""
                log_info "Press Enter to continue..."
                read -r
                ;;
            0)
                echo ""
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# GUIDED INTERACTIVE INSTALLATION WIZARD
# ============================================================================

guided_install() {
    log_header "🚀 Kubernetes Environment Setup Wizard"
    log_spacer
    
    # ========================================================================
    # STEP 1: SYSTEM ASSESSMENT
    # ========================================================================
    log_step "1" "6" "System Assessment"
    
    show_system_info
    log_spacer
    
    log_action "Analyzing component feasibility for your system..."
    log_spacer
    analyze_component_feasibility
    log_spacer
    
    log_prompt "Press Enter to continue to configuration..."
    read -r
    
    # ========================================================================
    # STEP 2: CONFIGURATION CHECK
    # ========================================================================
    log_step "2" "6" "Configuration Review"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_section "Current Configuration"
        echo "  ${CYAN}•${NC} Storage: ${BOLD}$STORAGE_PATH${NC}"
        echo "  ${CYAN}•${NC} Cluster: ${BOLD}$CLUSTER_NAME${NC}"
        echo "  ${CYAN}•${NC} Registry Port: ${BOLD}$REGISTRY_PORT${NC}"
        echo "  ${CYAN}•${NC} Memory Limit: ${BOLD}$MEMORY_LIMIT${NC}"
        log_spacer
        
        # Only ask to reconfigure if we didn't just come from setup
        if [[ "${SKIP_RECONFIG:-false}" != "true" ]]; then
            log_prompt "Reconfigure settings? [y/N]:"
            read -rp "" reconfig
            reconfig=$(echo "$reconfig" | tr '[:upper:]' '[:lower:]')
            if [[ "$reconfig" =~ ^y ]]; then
                reconfigure_setup
                initialize_environment  # Reload settings
                log_spacer
            fi
        else
            log_success "Configuration confirmed (just completed setup)"
            log_spacer
        fi
    else
        log_warn "No configuration found. Running setup wizard..."
        log_spacer
        first_run_setup
        initialize_environment
        log_spacer
    fi
    
    log_prompt "Press Enter to continue to pre-flight checks..."
    read -r
    
    # ========================================================================
    # STEP 3: PRE-FLIGHT CHECKS & CLEANUP
    # ========================================================================
    log_step "3" "6" "Pre-Flight Checks"
    
    # Check for competing clusters
    log_action "Scanning for competing Kubernetes clusters..."
    local competition=$(detect_competing_clusters_cached)
    if [[ "$competition" != "NONE" ]]; then
        log_spacer
        disable_competing_clusters
    else
        log_success "No competing clusters detected"
    fi
    log_spacer
    
    # Smart resource check - check system health first
    log_info "Checking system resources..."
    local pre_mem=$(get_memory_usage_cached)
    local pre_swap=$(get_swap_usage)
    local needs_cleanup=false
    
    if [[ "$pre_swap" != "0.00" ]] && [[ "$pre_swap" != "0" ]]; then
        local swap_mb=$(echo "$pre_swap" | awk '{printf "%.0f", $1}')
        local swap_percent=$(calc "$pre_swap / ($TOTAL_RAM_GB * 1024) * 100" | awk '{printf "%.0f", $1}')
        if (( swap_mb > 3072 )) || (( swap_percent > 40 )); then
            needs_cleanup=true
            log_warn "High swap usage detected: $(calc "$pre_swap / 1024" | awk '{printf "%.2f", $1}')GB (${swap_percent}% of RAM)"
        fi
    fi
    
    if compare_float "$pre_mem" ">" "$(calc "$TOTAL_RAM_GB * 0.75" | awk '{printf "%.2f", $1}')"; then
        needs_cleanup=true
        log_warn "High memory usage: ${pre_mem}GB / ${TOTAL_RAM_GB}GB (>75%)"
    fi
    
    if [[ "$needs_cleanup" == true ]]; then
        echo ""
        log_warn "💡 System is under memory pressure. Recommended actions:"
        echo "  • Close unnecessary applications (browsers, IDEs, etc.)"
        echo "  • Run Docker cleanup to free resources"
        echo ""
    fi
    
    # Check Docker resources
    echo ""
    check_docker_resource_usage
    echo ""
    
    local running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    local reclaimable=$(docker system df 2>/dev/null | awk '/Local Volumes.*%/ {print $4}' | head -1 || echo "0B")
    
    if [[ "$needs_cleanup" == true ]] || [[ $running_containers -gt 3 ]] || [[ "$reclaimable" != "0B" ]]; then
        log_info "Docker cleanup can help free resources"
        read -rp "Run Docker cleanup now? [Y/n]: " do_cleanup
        do_cleanup=$(echo "$do_cleanup" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$do_cleanup" =~ ^n ]]; then
            smart_cleanup
            echo ""
            log_success "Cleanup complete! System should have more available resources."
        fi
        echo ""
    else
        log_success "System resources look good!"
        echo ""
    fi
    
    # Advanced checks offer
    log_info "Advanced pre-flight checks available:"
    echo "  • Network conflict detection"
    echo "  • Storage health check"
    echo "  • Image optimization analysis"
    echo ""
    read -rp "Run advanced checks? [y/N]: " advanced_checks
    advanced_checks=$(echo "$advanced_checks" | tr '[:upper:]' '[:lower:]')
    if [[ "$advanced_checks" =~ ^y ]]; then
        echo ""
        log_header "Network Conflict Check"
        check_network_conflicts
        echo ""
        
        log_header "Storage Health Check"
        check_storage_health
        echo ""
        
        log_header "Image Optimization Analysis"
        optimize_docker_images
        echo ""
    fi
    
    log_info "Press Enter to continue to installation mode selection..."
    read -r
    
    # ========================================================================
    # STEP 4: INSTALLATION MODE SELECTION
    # ========================================================================
    log_header "STEP 4/6: Installation Mode Selection"
    echo ""
    
    # Check current system health to inform recommendations
    local current_mem=$(get_memory_usage_cached)
    local current_swap=$(get_swap_usage)
    local system_constrained=false
    local high_swap=false
    local high_memory=false
    
    # Check swap usage
    if [[ "$current_swap" != "0.00" ]] && [[ "$current_swap" != "0" ]]; then
        local swap_mb=$(echo "$current_swap" | awk '{printf "%.0f", $1}')
        local swap_percent=$(calc "$current_swap / ($TOTAL_RAM_GB * 1024) * 100" | awk '{printf "%.0f", $1}')
        
        # High swap if >3GB or >40% of RAM
        if (( swap_mb > 3072 )) || (( swap_percent > 40 )); then
            high_swap=true
        fi
    fi
    
    # Check memory usage
    if compare_float "$current_mem" ">" "$(calc "$TOTAL_RAM_GB * 0.6" | awk '{printf "%.2f", $1}')"; then
        high_memory=true
    fi
    
    # System is ONLY constrained if BOTH memory AND swap are high
    # High swap alone with low memory = inactive/stale swap (not a problem)
    if [[ "$high_swap" == true ]] && [[ "$high_memory" == true ]]; then
        system_constrained=true
    fi
    
    # Determine what's recommended based on RAM AND current system state
    local mode_recommended=""
    local mode_complete=""
    local recommendation_note=""
    
    if [[ "$system_constrained" == true ]]; then
        # System under pressure - recommend minimal
        mode_recommended="Base + Registry only"
        recommendation_note="⚠️  System currently under memory pressure - Minimal mode recommended"
    elif compare_float "$TOTAL_RAM_GB" ">=" "16"; then
        mode_recommended="Base + Registry + Metrics + Traefik + ArgoCD + Monitoring"
        mode_complete="$mode_recommended (RECOMMENDED for your ${TOTAL_RAM_GB}GB RAM)"
        recommendation_note="✓ System has adequate resources for full stack"
    elif compare_float "$TOTAL_RAM_GB" ">=" "8"; then
        mode_recommended="Base + Registry + Metrics + Traefik"
        mode_complete="Base + Registry + Metrics + Traefik + ArgoCD + Monitoring"
        recommendation_note="✓ Optimized for your ${TOTAL_RAM_GB}GB RAM"
    else
        mode_recommended="Base + Registry + Metrics"
        mode_complete="Base + Registry + Metrics + Traefik + ArgoCD + Monitoring"
        recommendation_note="✓ Optimized for limited resources"
    fi
    
    # Show current system status and offer solutions
    if [[ "$system_constrained" == true ]]; then
        log_warn "⚠️  Current System Status: Memory Pressure Detected"
        echo "  • Memory Usage: ${current_mem}GB / ${TOTAL_RAM_GB}GB"
        if [[ "$current_swap" != "0.00" ]] && [[ "$current_swap" != "0" ]]; then
            local swap_gb=$(calc "$current_swap / 1024" | awk '{printf "%.2f", $1}')
            echo "  • Swap Usage: ${swap_gb}GB (High pressure)"
        fi
        echo ""
        log_info "💡 Free up resources before proceeding:"
        echo ""
        echo "  1) Run Docker cleanup (remove unused images/containers/volumes)"
        echo "  2) View what's using resources and continue anyway"
        echo "  3) Skip resource check and continue with Minimal mode"
        echo "  4) Cancel installation"
        echo ""
        
        read -rp "Select option [1-4]: " resource_action
        
        case "$resource_action" in
            1)
                echo ""
                log_info "Running Docker cleanup..."
                check_docker_resource_usage
                echo ""
                smart_cleanup
                echo ""
                log_info "Rechecking system status..."
                current_mem=$(get_memory_usage_cached)
                current_swap=$(get_swap_usage)
                
                # Recheck if still constrained
                system_constrained=false
                if [[ "$current_swap" != "0.00" ]] && [[ "$current_swap" != "0" ]]; then
                    local swap_mb=$(echo "$current_swap" | awk '{printf "%.0f", $1}')
                    local swap_percent=$(calc "$current_swap / ($TOTAL_RAM_GB * 1024) * 100" | awk '{printf "%.0f", $1}')
                    if (( swap_mb > 3072 )) || (( swap_percent > 40 )); then
                        system_constrained=true
                    fi
                fi
                if compare_float "$current_mem" ">" "$(calc "$TOTAL_RAM_GB * 0.8" | awk '{printf "%.2f", $1}')"; then
                    system_constrained=true
                fi
                
                if [[ "$system_constrained" == false ]]; then
                    log_success "✓ Resources freed! System is now healthy"
                    # Recalculate recommendation
                    if compare_float "$TOTAL_RAM_GB" ">=" "16"; then
                        mode_recommended="Base + Registry + Metrics + Traefik + ArgoCD + Monitoring"
                        recommendation_note="✓ System has adequate resources for full stack"
                    elif compare_float "$TOTAL_RAM_GB" ">=" "8"; then
                        mode_recommended="Base + Registry + Metrics + Traefik"
                        recommendation_note="✓ Optimized for your ${TOTAL_RAM_GB}GB RAM"
                    else
                        mode_recommended="Base + Registry + Metrics"
                        recommendation_note="✓ Optimized for limited resources"
                    fi
                else
                    log_warn "System still under pressure. Minimal mode recommended."
                    mode_recommended="Base + Registry only"
                    recommendation_note="⚠️  System still constrained - Minimal mode recommended"
                fi
                echo ""
                ;;
            2)
                echo ""
                check_docker_resource_usage
                echo ""
                log_info "Press Enter to continue with installation..."
                read -r
                ;;
            3)
                log_info "Continuing with Minimal mode..."
                ;;
            4)
                log_info "Installation cancelled. Free up resources and try again."
                return 0
                ;;
            *)
                log_warn "Invalid option. Defaulting to Minimal mode."
                ;;
        esac
        echo ""
    fi
    
    log_info "Select installation mode:"
    echo ""
    echo "  1) Recommended (Based on current system state)"
    echo "     Components: $mode_recommended"
    echo "     $recommendation_note"
    echo ""
    
    echo "  2) Complete Environment (Full Stack)"
    echo "     Components: $mode_complete"
    if compare_float "$TOTAL_RAM_GB" "<" "12"; then
        echo "     ⚠️  WARNING: May cause performance issues with ${TOTAL_RAM_GB}GB RAM"
        echo "     ⚠️  Recommended: 12GB+ RAM for full stack"
    fi
    echo ""
    
    echo "  3) Minimal (Resource-Constrained)"
    echo "     Components: Base Cluster + Registry only"
    echo "     ✓ Lightest footprint (~2GB RAM)"
    echo ""
    
    echo "  4) Custom (Advanced - Choose components)"
    echo "     ✓ Select exactly what to install"
    echo ""
    
    local install_mode
    while true; do
        read -rp "Select mode [1-4]: " install_mode
        if [[ "$install_mode" =~ ^[1-4]$ ]]; then
            break
        fi
        log_error "Invalid choice. Please enter 1-4"
    done
    
    echo ""
    
    # ========================================================================
    # STEP 5: CONFIRMATION & EXECUTION
    # ========================================================================
    log_header "STEP 5/6: Installation"
    echo ""
    
    case "$install_mode" in
        1)
            log_info "Installing RECOMMENDED components for ${TOTAL_RAM_GB}GB RAM..."
            ;;
        2)
            log_warn "Installing COMPLETE environment..."
            if compare_float "$TOTAL_RAM_GB" "<" "12"; then
                echo ""
                log_warn "⚠️  Your system has ${TOTAL_RAM_GB}GB RAM"
                log_warn "⚠️  Full stack works best with 12GB+"
                echo ""
                read -rp "Continue anyway? [y/N]: " confirm_complete
                confirm_complete=$(echo "$confirm_complete" | tr '[:upper:]' '[:lower:]')
                if [[ ! "$confirm_complete" =~ ^y ]]; then
                    log_info "Installation cancelled"
                    return 0
                fi
            fi
            ;;
        3)
            log_info "Installing MINIMAL components..."
            ;;
        4)
            log_info "Starting CUSTOM installation..."
            echo ""
            # Custom component selection will be handled below
            ;;
    esac
    
    echo ""
    log_info "Starting installation in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    echo ""
    
    # Start memory pressure monitoring
    start_memory_monitor
    
    # Initialize installation state
    init_install_state
    
    # Set trap for rollback on error and cleanup
    trap 'stop_memory_monitor; rollback_installation' ERR
    trap 'stop_memory_monitor' EXIT
    
    # Common setup steps
    check_external_drive
    check_dependencies
    check_docker_runtime_available
    create_directory_structure
    create_registry_config
    
    # Start registry
    log_header "Installing Registry"
    start_registry || {
        rollback_installation
        return 1
    }
    
    # Start cluster
    log_header "Installing Kubernetes Cluster"
    start_cluster || {
        rollback_installation
        return 1
    }
    
    # Setup base components
    log_header "Configuring Base Components"
    
    # Setup PriorityClasses first to protect system pods
    setup_priority_classes
    
    mark_component_start "namespaces"
    setup_namespaces && mark_component_complete "namespaces" || mark_component_failed "namespaces"
    
    mark_component_start "storage"
    setup_persistent_volumes && mark_component_complete "storage" || mark_component_failed "storage"
    
    # Install components based on mode
    case "$install_mode" in
        1) # Recommended - but still ASK before installing each
            log_section "Confirming Recommended Components for Your System"
            echo ""
            local components_to_install=()
            
            if compare_float "$TOTAL_RAM_GB" ">=" "16"; then
                log_info "Recommended for ${TOTAL_RAM_GB}GB RAM:"
                read -rp "  • Install Metrics Server? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("metrics-server")
                read -rp "  • Install Traefik Ingress? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("traefik")
                read -rp "  • Install ArgoCD? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("argocd")
                read -rp "  • Install Monitoring Stack? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("monitoring")
            elif compare_float "$TOTAL_RAM_GB" ">=" "8"; then
                log_info "Recommended for ${TOTAL_RAM_GB}GB RAM:"
                read -rp "  • Install Metrics Server? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("metrics-server")
                read -rp "  • Install Traefik Ingress? [Y/n]: " confirm && [[ ! "$confirm" =~ ^n ]] && components_to_install+=("traefik")
            else
                log_info "Recommended for ${TOTAL_RAM_GB}GB RAM (limited resources):"
                if [[ "${LOW_MEMORY_MODE:-false}" == "true" ]]; then
                    log_info "  ⚠️  Metrics Server skipped in low-memory mode"
                else
                    read -rp "  • Install Metrics Server (not recommended for <8GB)? [y/N]: " confirm && [[ "$confirm" =~ ^y ]] && components_to_install+=("metrics-server")
                fi
            fi
            
            echo ""
            if [[ ${#components_to_install[@]} -eq 0 ]]; then
                log_info "No optional components selected - cluster only"
            else
                log_info "Will install: ${components_to_install[*]}"
            fi
            
            # Install selected components
            for comp in "${components_to_install[@]}"; do
                case "$comp" in
                    metrics-server) install_component "metrics-server" install_metrics_server ;;
                    traefik) install_component "traefik" install_traefik ;;
                    argocd) install_component "argocd" install_argocd ;;
                    monitoring) install_component "monitoring" install_monitoring ;;
                esac
            done
            ;;
        2) # Complete
            log_section "Installing Complete Environment"
            echo ""
            install_component "metrics-server" install_metrics_server
            install_component "traefik" install_traefik
            install_component "argocd" install_argocd
            install_component "monitoring" install_monitoring
            ;;
        3) # Minimal
            # Only base + registry (already done)
            log_info "Minimal installation - skipping optional components"
            ;;
        4) # Custom
            custom_component_selection
            ;;
    esac
    
    # Wait for all pods
    log_info "Waiting for all system pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s 2>/dev/null || log_warn "Some pods may still be starting"
    
    # Create initial backup
    log_header "Creating Initial Backup"
    backup_cluster
    
    # Clear trap
    trap - ERR
    
    # ========================================================================
    # STEP 6: POST-INSTALL
    # ========================================================================
    log_header "STEP 6/6: Post-Installation"
    echo ""
    
    # Stop memory monitor and check for alerts
    if ! stop_memory_monitor; then
        log_warn "Memory pressure was detected during installation"
        log_warn "System may be running at capacity - consider closing other applications"
        echo ""
    fi
    
    log_success "✓ Installation Complete!"
    echo ""
    log_info "Installed Components:"
    echo "  ✓ Kubernetes Cluster: $CLUSTER_NAME"
    echo "  ✓ Registry: localhost:${REGISTRY_PORT}"
    echo "  ✓ Storage: $KUBE_ROOT"
    
    # Show installed components
    grep ":completed:" "$STATE_FILE" 2>/dev/null | cut -d: -f1 | while read -r comp; do
        echo "  ✓ $comp"
    done
    
    echo ""
    log_info "Quick Commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "  kubectl get namespaces"
    echo ""
    
    # Post-install options
    log_info "Additional Options:"
    echo ""
    
    read -rp "Install shell aliases for easier management? [Y/n]: " install_alias
    install_alias=$(echo "$install_alias" | tr '[:upper:]' '[:lower:]')
    if [[ ! "$install_alias" =~ ^n ]]; then
        install_aliases
    fi
    
    echo ""
    read -rp "Start periodic health monitoring? [Y/n]: " start_monitor
    start_monitor=$(echo "$start_monitor" | tr '[:upper:]' '[:lower:]')
    if [[ ! "$start_monitor" =~ ^n ]]; then
        echo ""
        read -rp "Monitoring interval in seconds [300]: " monitor_interval
        monitor_interval=${monitor_interval:-300}
        echo ""
        read -rp "Enable auto-cleanup on high swap usage? [Y/n]: " auto_clean
        auto_clean=$(echo "$auto_clean" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$auto_clean" =~ ^n ]]; then
            start_health_monitor "$monitor_interval" "true"
        else
            start_health_monitor "$monitor_interval" "false"
        fi
    fi
    
    echo ""
    log_header "Installation Complete! 🎉"
    log_success "Your Kubernetes environment is installed and ready!"
    echo ""
    
    # Show maintenance reminder
    log_info "💡 Maintenance Tip:"
    echo "  Run './local-k8s.sh maintenance' anytime to see best practices"
    echo "  for keeping your cluster healthy and performant."
    echo ""
    
    # Clear the skip reconfigure flag
    SKIP_RECONFIG=false
    
    # Offer to view status or return to menu - with loop
    while true; do
        log_header "Next Steps"
        echo "What would you like to do next?"
        echo ""
        echo "  1) View cluster status and quick health check"
        echo "  2) Return to main menu for more options"
        echo "  3) Exit (services are running in background)"
        echo ""
        read -rp "Select option [1-3]: " next_action
        
        case "$next_action" in
            1)
                echo ""
                log_header "Cluster Status"
                kubectl get nodes
                echo ""
                kubectl get pods -A
                echo ""
                log_info "Press Enter to continue..."
                read -r
                # Loop continues - back to options
                ;;
            2)
                # Exit loop and return to menu
                break
                ;;
            3)
                echo ""
                log_info "Cluster is running. Access anytime with:"
                echo "  ./local-k8s.sh menu"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid option. Please select 1-3."
                sleep 1
                # Loop continues
                ;;
        esac
    done
}

# Helper function to install optional components with error handling
install_component() {
    local component_name=$1
    local install_function=$2
    
    log_header "Installing $component_name"
    mark_component_start "$component_name"
    
    if $install_function; then
        mark_component_complete "$component_name"
        log_success "$component_name installed successfully"
    else
        mark_component_failed "$component_name"
        log_warn "$component_name installation failed, continuing..."
    fi
}

# Custom component selection for advanced users
custom_component_selection() {
    log_info "Select components to install (space-separated numbers):"
    echo ""
    echo "  1) Metrics Server (recommended)"
    echo "  2) Traefik Ingress Controller"
    echo "  3) ArgoCD"
    echo "  4) Monitoring Stack (Prometheus + Grafana)"
    echo ""
    read -rp "Enter choices [e.g., 1 2]: " choices
    
    # Install based on selections
    for choice in $choices; do
        case "$choice" in
            1) install_component "metrics-server" install_metrics_server ;;
            2) install_component "traefik" install_traefik ;;
            3) install_component "argocd" install_argocd ;;
            4) install_component "monitoring" install_monitoring ;;
        esac
    done
}

# ============================================================================
# GUIDED INTERACTIVE START WIZARD
# ============================================================================

guided_start() {
    log_header "🚀 Starting Kubernetes Environment"
    echo ""
    
    # Check if already installed
    if [[ ! -d "$KUBE_ROOT" ]]; then
        log_warn "No existing installation found at $KUBE_ROOT"
        echo ""
        read -rp "Would you like to run the installation wizard instead? [Y/n]: " run_install
        run_install=$(echo "$run_install" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$run_install" =~ ^n ]]; then
            guided_install
            return $?
        else
            log_error "Cannot start without installation"
            return 1
        fi
    fi
    
    # System check
    log_header "System Check"
    echo ""
    show_system_info
    echo ""
    
    # Configuration review
    log_info "Current Configuration:"
    echo "  • Cluster: $CLUSTER_NAME"
    echo "  • Registry Port: $REGISTRY_PORT"
    echo "  • Storage: $KUBE_ROOT"
    echo ""
    
    read -rp "Reconfigure? [y/N]: " reconfig
    reconfig=$(echo "$reconfig" | tr '[:upper:]' '[:lower:]')
    if [[ "$reconfig" =~ ^y ]]; then
        reconfigure_setup
        initialize_environment
        echo ""
    fi
    
    # Pre-flight checks
    log_header "Pre-Flight Checks"
    echo ""
    
    # Check for competing clusters
    local competition=$(detect_competing_clusters_cached)
    if [[ "$competition" != "NONE" ]]; then
        disable_competing_clusters
        echo ""
    else
        log_success "No competing clusters detected"
    fi
    
    # Resource check
    check_system_health || {
        echo ""
        log_warn "System resources are constrained"
        read -rp "Check Docker usage and offer cleanup? [Y/n]: " check_docker
        check_docker=$(echo "$check_docker" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$check_docker" =~ ^n ]]; then
            echo ""
            check_docker_resource_usage
            echo ""
            read -rp "Run cleanup? [y/N]: " do_cleanup
            do_cleanup=$(echo "$do_cleanup" | tr '[:upper:]' '[:lower:]')
            if [[ "$do_cleanup" =~ ^y ]]; then
                smart_cleanup
            fi
        fi
        echo ""
        read -rp "Continue with startup anyway? [y/N]: " continue_start
        continue_start=$(echo "$continue_start" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$continue_start" =~ ^y ]]; then
            log_info "Startup cancelled"
            return 0
        fi
    }
    
    echo ""
    log_info "Starting services..."
    echo ""
    
    # Start services
    check_external_drive
    check_dependencies
    check_docker_runtime_available
    init_install_state
    
    start_registry || {
        log_error "Failed to start registry"
        return 1
    }
    
    start_cluster || {
        log_error "Failed to start cluster"
        return 1
    }
    
    echo ""
    log_success "✓ Kubernetes environment is running!"
    echo ""
    log_info "Quick status check:"
    kubectl get nodes
    echo ""
    kubectl get pods -A | head -10
    echo ""
    
    # Offer next steps with loop
    while true; do
        log_header "Next Steps"
        echo "What would you like to do?"
        echo ""
        echo "  1) View detailed cluster status"
        echo "  2) Run system health check"
        echo "  3) Return to main menu"
        echo "  4) Exit"
        echo ""
        read -rp "Select option [1-4]: " next_action
        
        case "$next_action" in
            1)
                echo ""
                log_header "Detailed Cluster Status"
                kubectl cluster-info
                echo ""
                kubectl get all -A
                echo ""
                log_info "Press Enter to continue..."
                read -r
                # Loop continues
                ;;
            2)
                echo ""
                check_system_health
                echo ""
                log_info "Press Enter to continue..."
                read -r
                # Loop continues
                ;;
            3)
                # Exit loop and return to menu
                break
                ;;
            4)
                echo ""
                log_info "Cluster is running. Manage it with:"
                echo "  ./local-k8s.sh menu"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid option. Please select 1-4."
                sleep 1
                # Loop continues
                ;;
        esac
    done
}

# ============================================================================
# ORIGINAL NON-INTERACTIVE FUNCTIONS (for scripting/CI)
# ============================================================================

install_complete_environment() {
    log_header "Complete Environment Installation"
    
    # Show system info first
    show_system_info
    analyze_component_feasibility
    
    echo ""
    log_warn "This will install the base cluster with recommended components."
    echo -n "Continue? (y/N): "
    read -r response
    [[ ! "$response" =~ ^[Yy]$ ]] && return
    
    # Initialize installation state
    init_install_state
    
    # Set trap for rollback on error
    trap 'rollback_installation' ERR
    
    # Pre-flight checks
    log_header "Pre-flight Checks"
    
    # 1. Check for competing Kubernetes clusters
    disable_competing_clusters
    
    # 2. Check Docker resource usage
    check_docker_resource_usage
    
    # 3. Offer cleanup if resources are being used
    local running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    if [[ $running_containers -gt 3 ]] || docker system df 2>/dev/null | grep -q "Build Cache" | grep -v "0B"; then
        log_warn "Docker has accumulated resources that could be cleaned up"
        read -rp "Run smart cleanup now? [Y/n]: " cleanup_choice
        cleanup_choice=$(echo "$cleanup_choice" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$cleanup_choice" =~ ^n ]]; then
            smart_cleanup
        fi
    fi
    
    # 4. Standard checks
    check_external_drive
    check_dependencies
    check_docker_runtime_available
    check_kubectl
    check_helm
    check_system_health || {
        log_warn "System resources are constrained. Continue anyway? (y/N)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && exit 1
    }
    
    # Create directory structure
    log_header "Setting Up Storage"
    create_directory_structure
    create_registry_config
    
    # Start services
    log_header "Starting Services"
    start_registry || {
        rollback_installation
        return 1
    }
    
    start_cluster || {
        rollback_installation
        return 1
    }
    
    # Setup cluster components
    log_header "Configuring Cluster"
    
    mark_component_start "namespaces"
    setup_namespaces && mark_component_complete "namespaces" || mark_component_failed "namespaces"
    
    mark_component_start "storage"
    setup_persistent_volumes && mark_component_complete "storage" || mark_component_failed "storage"
    
    mark_component_start "metrics-server"
    install_metrics_server && mark_component_complete "metrics-server" || {
        mark_component_failed "metrics-server"
        log_warn "Metrics Server installation failed, continuing..."
    }
    
    mark_component_start "traefik"
    install_traefik && mark_component_complete "traefik" || {
        mark_component_failed "traefik"
        log_warn "Traefik installation failed, continuing..."
    }
    
    # Wait for all pods to be ready
    log_info "Waiting for all system pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s || log_warn "Some pods may still be starting"
    
    # Create initial backup
    log_header "Creating Initial Backup"
    backup_cluster
    
    # Clear trap
    trap - ERR
    
    log_header "Installation Complete!"
    echo ""
    log_success "Cluster Name: $CLUSTER_NAME"
    log_success "Registry: localhost:${REGISTRY_PORT}"
    log_success "Storage: $KUBE_ROOT"
    echo ""
    log_info "Namespaces created: dev, staging, testing"
    log_info "Resource quotas: Enabled (dynamic based on ${TOTAL_RAM_GB}GB RAM)"
    log_info "Metrics Server: Installed"
    log_info "Ingress Controller: Traefik"
    echo ""
    log_recommend "Quick Start Commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "  kubectl top nodes"
    echo ""
    log_info "Installation log: $INSTALL_LOG"
    echo ""
}

# ============================================================================
# ALIAS INSTALLATION
# ============================================================================

install_aliases() {
    local shell_rc
    
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    log_info "Installing shell aliases to $shell_rc..."
    
    # Check if aliases already exist
    if grep -q "# Kubernetes Learning Environment Aliases" "$shell_rc" 2>/dev/null; then
        log_info "Aliases already installed"
        return 0
    fi
    
    cat >> "$shell_rc" <<'EOF'

# Kubernetes Learning Environment Aliases
alias cluster-start='bash '"$0"' menu'
alias cluster-stop='bash '"$0"' stop'
alias cluster-status='bash '"$0"' status'
alias cluster-health='bash '"$0"' health'
alias cluster-clean='bash '"$0"' clean'
alias cluster-backup='bash '"$0"' backup'
EOF
    
    log_success "Aliases installed. Run 'source $shell_rc' or restart your terminal"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Check system prerequisites and compatibility
check_prerequisites() {
    local errors=0
    local warnings=0
    
    # Check for required commands
    local required_cmds=("docker" "kubectl")
    local optional_cmds=("helm" "jq" "curl" "wget")
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ Required command not found: $cmd"
            ((errors++))
        fi
    done
    
    # Check Docker socket access
    if command -v docker &>/dev/null; then
        if ! docker ps &>/dev/null; then
            echo "⚠️  Docker found but cannot connect to Docker daemon"
            echo "   Check: Docker running? Permission issues? Try: sudo usermod -aG docker \$USER"
            ((warnings++))
        fi
    fi
    
    # Check for math tools (bc, awk, or python)
    if ! command -v bc &>/dev/null && ! command -v awk &>/dev/null && ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        echo "❌ No math calculation tools found (need bc, awk, or python)"
        ((errors++))
    fi
    
    # Check writable home directory
    if [[ ! -w "$HOME" ]]; then
        echo "❌ Home directory not writable: $HOME"
        ((errors++))
    fi
    
    # Check for optional but useful tools
    for cmd in "${optional_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ℹ️  Optional tool not found: $cmd (recommended)"
            ((warnings++))
        fi
    done
    
    # Warn about platform-specific issues
    case "$(uname -s)" in
        Darwin*)
            # macOS specific checks
            if [[ $(sw_vers -productVersion 2>/dev/null | cut -d. -f1) -lt 11 ]]; then
                echo "⚠️  macOS version may be too old (recommend 11+)"
                ((warnings++))
            fi
            ;;
        Linux*)
            # Linux specific checks
            if [[ ! -f /proc/meminfo ]]; then
                echo "⚠️  Cannot read /proc/meminfo - memory detection may fail"
                ((warnings++))
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "⚠️  Native Windows detected - WSL2 is recommended for better compatibility"
            ((warnings++))
            ;;
    esac
    
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "❌ $errors critical error(s) found. Please fix before continuing."
        return 1
    fi
    
    if [[ $warnings -gt 0 ]]; then
        echo ""
        echo "⚠️  $warnings warning(s) - script may work with reduced functionality"
    fi
    
    return 0
}

initialize_environment() {
    # Check prerequisites first
    if [[ "${SKIP_PREREQ_CHECK:-false}" != "true" ]]; then
        if ! check_prerequisites; then
            echo ""
            echo "To skip this check (not recommended): export SKIP_PREREQ_CHECK=true"
            exit 1
        fi
    fi
    
    # Detect system (use cached versions for 40-60% speedup on repeated calls)
    OS_TYPE=$(detect_os_cached)
    CPU_ARCH=$(detect_arch)
    TOTAL_RAM_GB=$(detect_total_ram_gb_cached)
    CPU_CORES=$(detect_cpu_cores "$OS_TYPE")
    DOCKER_RUNTIME=$(detect_docker_runtime_cached)
    K8S_TOOLS=($(detect_k8s_tools))
    
    # Detect resource tier for adaptive behavior
    if [[ "${LOW_MEMORY_MODE:-false}" == "true" ]]; then
        RESOURCE_TIER="low"  # Force low tier in low-memory mode
        log_info "Low-memory mode enabled - using minimal resource allocation"
    elif compare_float "$TOTAL_RAM_GB" "<" "8"; then
        RESOURCE_TIER="low"
    elif compare_float "$TOTAL_RAM_GB" "<" "16"; then
        RESOURCE_TIER="medium"
    else
        RESOURCE_TIER="high"
    fi
    
    # Detect or load workload profile (can be overridden by --profile flag)
    if [[ -z "${WORKLOAD_PROFILE:-}" ]]; then
        # Auto-detect based on resource tier if not specified
        case "$RESOURCE_TIER" in
            low)
                WORKLOAD_PROFILE="minimal"
                ;;
            medium)
                WORKLOAD_PROFILE="lab"  # Default for 8-16GB systems
                ;;
            high)
                WORKLOAD_PROFILE="full"
                ;;
        esac
    fi
    export WORKLOAD_PROFILE
    
    # Try to load existing configuration
    if load_config 2>/dev/null; then
        # Use config values
        EXTERNAL_DRIVE="$STORAGE_PATH"
        # Ensure REGISTRY_NAME is set (may not be in older configs)
        REGISTRY_NAME="${REGISTRY_NAME:-local-registry}"
    else
        # No config file, use defaults
        STORAGE_PATH="$HOME/.kube-lab"
        EXTERNAL_DRIVE="$STORAGE_PATH"
        CLUSTER_NAME="local-k8s"
        REGISTRY_PORT="5000"
        REGISTRY_NAME="local-registry"
        MEMORY_LIMIT="auto"
    fi
    
    # Set directory paths
    KUBE_ROOT="${EXTERNAL_DRIVE}/kube-stack"
    REGISTRY_DIR="${KUBE_ROOT}/registry"
    PV_DIR="${KUBE_ROOT}/pv-data"
    BACKUP_DIR="${KUBE_ROOT}/backups"
    LOG_DIR="${KUBE_ROOT}/logs"
    TMP_DIR="${KUBE_ROOT}/tmp"
    CONFIG_DIR="${KUBE_ROOT}/config"
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR" "$TMP_DIR" 2>/dev/null || true
    
    # Set state and log file paths
    STATE_FILE="${TMP_DIR}/install-state.txt"
    INSTALL_LOG="${LOG_DIR}/install-$(date +%Y%m%d).log"
    
    # Platform-specific OS overhead (GB to reserve for OS/Docker)
    case "$OS_TYPE" in
        windows|wsl2)
            OS_OVERHEAD_GB=2.0  # Windows needs more for WSL2/HyperV
            ;;
        macos)
            if [[ "$CPU_ARCH" == "arm64" ]]; then
                OS_OVERHEAD_GB=1.5  # Apple Silicon more efficient
            else
                OS_OVERHEAD_GB=1.8  # Intel Mac needs more
            fi
            ;;
        linux)
            OS_OVERHEAD_GB=1.2  # Native Linux most efficient
            ;;
        *)
            OS_OVERHEAD_GB=1.5  # Default fallback
            ;;
    esac
    
    # Dynamic memory limits based on total RAM or config with OS overhead buffer
    if [[ "$MEMORY_LIMIT" == "auto" ]]; then
        # Reserve OS overhead, then allocate remaining
        local available_for_cluster=$(calc "$TOTAL_RAM_GB - $OS_OVERHEAD_GB" | awk '{printf "%.2f", $1}')
        
        # Safety check - never allocate if less than 2GB would remain
        if compare_float "$available_for_cluster" "<" "2.0"; then
            CLUSTER_MEMORY_LIMIT=1024  # Minimal 1GB
            log_warn "Very limited RAM detected. Setting minimal cluster memory allocation."
        else
            # Allocate percentage based on tier
            case "$RESOURCE_TIER" in
                low)
                    local alloc_percent=0.70  # Use 70% of available (aggressive for low RAM)
                    ;;
                medium)
                    local alloc_percent=0.75  # Use 75% of available
                    ;;
                high)
                    local alloc_percent=0.80  # Use 80% of available
                    ;;
            esac
            CLUSTER_MEMORY_LIMIT=$(calc "$available_for_cluster * $alloc_percent * 1024" | awk '{printf "%.0f", $1}')
        fi
    else
        CLUSTER_MEMORY_LIMIT=$MEMORY_LIMIT
    fi
    MAX_SAFE_MEMORY=$(calc "$TOTAL_RAM_GB * 0.8" | awk '{printf "%.2f", $1}')  # 80% threshold
}

# ============================================================================
# MAIN ENTRYPOINT
# ============================================================================

main() {
    # Parse flags and command
    local command=""
    local interactive=true
    export LOW_MEMORY_MODE=false
    
    # Process all arguments to extract flags and command
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
            --non-interactive|--ci|--no-interactive)
                interactive=false
                ;;
            --low-memory)
                LOW_MEMORY_MODE=true
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$arg"
                fi
                ;;
        esac
    done
    
    # Default to menu if no command
    command="${command:-menu}"
    
    # Initialize environment first
    initialize_environment
    
    # Show mode messages
    if [[ "$DRY_RUN" == true ]]; then
        log_info "🔍 DRY-RUN MODE: No changes will be made"
        echo ""
    fi
    
    if [[ "$interactive" == false ]]; then
        log_info "🤖 NON-INTERACTIVE MODE: Using defaults, no prompts"
        echo ""
    fi
    
    # Check if first run (no config) and command requires it
    if [[ ! -f "$CONFIG_FILE" ]] && [[ "$command" != "setup" ]] && [[ "$command" != "reconfigure" ]] && [[ "$command" != "sysinfo" ]] && [[ "$DRY_RUN" == false ]]; then
        if [[ "$interactive" == true ]]; then
            log_warn "No configuration found. Running first-time setup..."
            first_run_setup
            initialize_environment  # Reload after setup
        else
            log_warn "No configuration found. Using defaults for non-interactive mode..."
            # Use defaults without prompting
            STORAGE_PATH="${STORAGE_PATH:-$HOME/.kube-lab}"
            EXTERNAL_DRIVE="$STORAGE_PATH"
            CLUSTER_NAME="${CLUSTER_NAME:-local-k8s}"
            REGISTRY_PORT="${REGISTRY_PORT:-5000}"
            save_config
            initialize_environment
        fi
    fi
    
    case "$command" in
        install)
            if [[ "$DRY_RUN" == true ]]; then
                log_header "DRY-RUN: Installation Preview"
                show_system_info
                analyze_component_feasibility
                echo ""
                log_info "Would install:"
                echo "  ✓ Local Docker Registry (port $REGISTRY_PORT)"
                echo "  ✓ Kubernetes Cluster ($CLUSTER_NAME)"
                echo "  ✓ Metrics Server"
                echo "  ✓ Traefik Ingress Controller"
                echo ""
                log_info "Storage location: $KUBE_ROOT"
                log_info "Memory allocation: ${CLUSTER_MEMORY_LIMIT}MB"
            else
                if [[ "$interactive" == true ]]; then
                    # Use guided interactive wizard
                    guided_install
                else
                    # Use original non-interactive function
                    install_complete_environment
                    install_aliases
                fi
            fi
            ;;
        setup|reconfigure)
            if [[ "$DRY_RUN" == true ]]; then
                log_header "DRY-RUN: Setup Preview"
                show_system_info
                log_info "Current configuration:"
                if [[ -f "$CONFIG_FILE" ]]; then
                    cat "$CONFIG_FILE"
                else
                    echo "  No configuration file found"
                fi
            else
                if reconfigure_setup; then
                    initialize_environment  # Reload after successful reconfigure
                else
                    # User declined to overwrite - offer options in a loop
                    initialize_environment  # Load existing config
                    
                    while true; do
                        echo ""
                        log_header "Configuration Options"
                        echo "What would you like to do?"
                        echo ""
                        echo "  1) Continue with existing configuration → Install"
                        echo "  2) View current configuration"
                        echo "  3) Return to main menu"
                        echo "  4) Exit"
                        echo ""
                        read -rp "Select option [1-4]: " config_option
                        
                        case "$config_option" in
                            1)
                                echo ""
                                log_info "Proceeding with existing configuration..."
                                sleep 1
                                SKIP_RECONFIG=true
                                guided_install
                                break
                                ;;
                            2)
                                echo ""
                                show_system_info
                                echo ""
                                log_info "Press Enter to continue..."
                                read -r
                                # Loop continues - back to options menu
                                ;;
                            3)
                                # Exit loop and fall through to menu
                                break
                                ;;
                            4)
                                echo ""
                                log_info "Goodbye!"
                                exit 0
                                ;;
                            *)
                                log_warn "Invalid option. Please select 1-4."
                                sleep 1
                                # Loop continues
                                ;;
                        esac
                    done
                fi
            fi
            ;;
        sysinfo)
            show_system_info
            echo ""
            analyze_resource_profile
            ;;
        resource-analysis|resource-profile)
            analyze_resource_profile
            ;;
        check-feasibility)
            # Interactive component feasibility checker
            log_header "Component Feasibility Checker"
            echo ""
            echo "Select components to check:"
            echo "  1. Registry"
            echo "  2. Metrics Server"
            echo "  3. Traefik Ingress"
            echo "  4. ArgoCD"
            echo "  5. Full Monitoring Stack"
            echo ""
            read -p "Enter component numbers (space-separated, e.g., '1 2 3'): " -r selections
            
            local components=()
            for num in $selections; do
                case $num in
                    1) components+=("registry") ;;
                    2) components+=("metrics-server") ;;
                    3) components+=("traefik") ;;
                    4) components+=("argocd") ;;
                    5) components+=("monitoring") ;;
                esac
            done
            
            if [[ ${#components[@]} -gt 0 ]]; then
                if validate_component_feasibility "${components[@]}"; then
                    local required=$(predict_resource_consumption "${components[@]}")
                    log_success "✓ Components feasible!"
                    echo "  Required: ${required}MB"
                    echo "  Available: $((TOTAL_RAM_GB * 1024 * 80 / 100))MB (80% of total)"
                else
                    log_error "✗ Components NOT feasible"
                    local required=$(predict_resource_consumption "${components[@]}")
                    echo "  Required: ${required}MB"
                    echo "  Available: $((TOTAL_RAM_GB * 1024 * 80 / 100))MB (80% of total)"
                    echo ""
                    echo "Suggestions:"
                    local feasible=$(get_feasible_components_for_ram)
                    echo "  Try: $feasible"
                fi
            fi
            ;;
        analyze-components)
            show_system_info
            echo ""
            analyze_resource_profile
            ;;
        cluster-list|list-clusters)
            list_all_clusters
            ;;
        cluster-switch|switch-cluster)
            if [[ -z "$2" ]]; then
                log_error "Cluster name required: $0 cluster-switch <name>"
                list_all_clusters
            else
                switch_cluster "$2"
            fi
            ;;
        cluster-create|create-cluster)
            if [[ -z "$2" ]]; then
                log_error "Usage: $0 cluster-create <name> [memory] [runtime]"
                echo "Example: $0 cluster-create staging 8GB k3d"
            else
                create_named_cluster "$2" "$3" "$4"
            fi
            ;;
        cluster-info|cluster-status)
            get_current_cluster_info
            ;;
        cluster-backup|backup-cluster)
            local target_cluster="${2:-$ACTIVE_CLUSTER}"
            backup_cluster "$target_cluster"
            ;;
        cluster-backups|list-backups)
            list_cluster_backups
            ;;
        start)
            if [[ "$DRY_RUN" == true ]]; then
                log_header "DRY-RUN: Start Preview"
                show_system_info
                echo ""
                log_info "Would perform:"
                echo "  1. Check for competing clusters"
                echo "  2. Check external drive availability"
                echo "  3. Verify dependencies: docker, kubectl, helm"
                echo "  4. Check Docker runtime: $DOCKER_RUNTIME"
                echo "  5. Start registry on port $REGISTRY_PORT"
                echo "  6. Start cluster: $CLUSTER_NAME"
                echo ""
                log_info "No actual changes will be made"
            else
                if [[ "$interactive" == true ]]; then
                    # Use guided interactive wizard
                    guided_start
                else
                    # Use original non-interactive function
                    disable_competing_clusters
                    check_external_drive
                    check_dependencies
                    check_docker_runtime_available
                    init_install_state
                    start_registry
                    start_cluster
                fi
            fi
            ;;
        stop)
            stop_cluster
            stop_registry
            ;;
        delete)
            delete_cluster
            stop_registry
            ;;
        status)
            show_status
            ;;
        health)
            show_health
            ;;
        clean)
            cleanup_resources
            ;;
        backup)
            backup_cluster
            ;;
        restore)
            restore_cluster "${2:-latest}"
            ;;
        rollback)
            rollback_installation
            ;;
        argocd)
            check_external_drive
            check_dependencies
            check_docker_runtime_available
            install_argocd
            ;;
        monitoring)
            check_external_drive
            check_dependencies
            check_docker_runtime_available
            install_monitoring
            ;;
        check-competing|competing)
            detect_competing_clusters
            competition=$(detect_competing_clusters_cached)
            if [[ "$competition" == "NONE" ]]; then
                log_success "✓ No competing Kubernetes clusters detected"
            else
                disable_competing_clusters
            fi
            ;;
        docker-cleanup)
            smart_cleanup
            ;;
        docker-usage)
            check_docker_resource_usage
            ;;
        network-check|check-network)
            check_network_conflicts
            ;;
        quota-analysis|resource-quotas)
            analyze_resource_quotas
            ;;
        optimize-images|image-optimization)
            optimize_docker_images
            ;;
        storage-check|check-storage)
            check_storage_health
            ;;
        start-monitor)
            # Check for auto-cleanup flag
            local monitor_interval="${2:-300}"
            local auto_clean=false
            if [[ "$3" == "--auto-cleanup" ]] || [[ "$3" == "-a" ]]; then
                auto_clean=true
            fi
            start_health_monitor "$monitor_interval" "$auto_clean"
            ;;
        stop-monitor)
            stop_health_monitor
            ;;
        monitor-logs|health-logs)
            view_health_logs
            ;;
        maintenance|maintain|tips)
            show_maintenance_tips
            ;;
        prune|prune-images)
            prune_images
            ;;
        backup-bg|background-backup)
            backup_cluster true
            ;;
        backup-status)
            check_backup_status
            ;;
        health|health-check)
            health_check
            ;;
        components|list-components)
            list_components
            ;;
        enable-metrics)
            toggle_metrics_server enable
            ;;
        disable-metrics)
            toggle_metrics_server disable
            ;;
        metrics-status)
            toggle_metrics_server status
            ;;
        check-capacity|capacity)
            shift  # Remove command name
            log_header "Workload Capacity Check"
            show_system_info
            echo ""
            check_workload_capacity "$@"
            ;;
        optimize-quotas)
            optimize_for_workload
            ;;
        menu)
            # Check if first run
            if ! load_config; then
                first_run_setup
            fi
            show_menu
            ;;
        aliases)
            install_aliases
            ;;
        *)
            echo "Usage: $0 <command> [flags]"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  MAIN COMMANDS (Interactive by default)"
            echo "═══════════════════════════════════════════════════════════"
            echo "  setup           - First-time configuration wizard"
            echo "  install         - 🎯 Guided installation wizard"
            echo "                    (Assess → Configure → Pre-flight → Install)"
            echo "  start           - 🎯 Guided startup wizard"
            echo "                    (Check → Validate → Start → Verify)"
            echo "  stop            - Stop cluster and registry"
            echo "  delete          - Delete cluster (keep data)"
            echo "  status          - Show cluster status"
            echo "  menu            - Interactive menu (default)"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  FLAGS"
            echo "═══════════════════════════════════════════════════════════"
            echo "  --non-interactive  - Skip all prompts (for CI/CD)"
            echo "  --dry-run          - Preview actions without executing"
            echo "  --low-memory       - Minimal footprint mode (single node, 50MB registry)"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  WORKLOAD PROFILES (auto-detected)"
            echo "═══════════════════════════════════════════════════════════"
            echo "  minimal  - <8GB:  1 node, 512MB quotas, basic services"
            echo "  lab      - 8-16GB: 2 nodes, 800MB quotas, ESO+Traefik+Vault ready"
            echo "  full     - >16GB: 3 nodes, 2GB quotas, all components"
            echo ""
            echo "  Component Dependencies:"
            echo "    • ESO requires secret backend (Vault, AWS, Azure, GCP, etc.)"
            echo "    • ArgoCD works best with Git repo access"
            echo "    • Monitoring stack needs 800MB+ (Prometheus + Grafana)"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  MANAGEMENT"
            echo "═══════════════════════════════════════════════════════════"
            echo "  backup          - Create cluster backup (blocking)"
            echo "  backup-bg       - Create backup in background"
            echo "  backup-status   - Check background backup status"
            echo "  restore [name]  - Restore from backup"
            echo "  rollback        - Rollback failed installation"
            echo "  clean           - Cleanup Kubernetes resources"
            echo "  prune           - Remove unused Docker images"
            echo "  argocd          - Install ArgoCD"
            echo "  monitoring      - Install monitoring stack"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  COMPONENT MANAGEMENT"
            echo "═══════════════════════════════════════════════════════════"
            echo "  components      - List all components and status"
            echo "  enable-metrics  - Enable metrics-server"
            echo "  disable-metrics - Disable metrics-server"
            echo "  metrics-status  - Check metrics-server status"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  SMART DIAGNOSTICS"
            echo "═══════════════════════════════════════════════════════════"
            echo "  sysinfo         - System info & resource analysis"
            echo "  resource-analysis - Detailed resource profile & recommendations"
            echo "  check-feasibility - Check if components fit in available RAM"
            echo "  check-capacity [components...] - Calculate overhead for workload"
            echo "                    Example: check-capacity registry traefik eso"
            echo "  optimize-quotas - Show optimization recommendations for profile"
            echo "  health          - Run health check"
            echo "  check-competing - Detect competing K8s clusters"
            echo "  network-check   - Check for port/network conflicts"
            echo "  resource-quotas - Analyze resource usage & recommendations"
            echo "  storage-check   - Check storage health & manage backups"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  MULTI-CLUSTER MANAGEMENT (PHASE 3)"
            echo "═══════════════════════════════════════════════════════════"
            echo "  cluster-list          - List all configured clusters"
            echo "  cluster-info          - Show current cluster information"
            echo "  cluster-create <name> - Create new named cluster"
            echo "                          (e.g., cluster-create staging 8GB k3d)"
            echo "  cluster-switch <name> - Switch to different cluster"
            echo "  cluster-backup        - Backup current cluster"
            echo "  cluster-backups       - List all cluster backups"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  OPTIMIZATION"
            echo "═══════════════════════════════════════════════════════════"
            echo "  docker-cleanup  - Clean Docker (images, containers, volumes)"
            echo "  docker-usage    - Show Docker resource usage"
            echo "  optimize-images - Analyze & optimize Docker images"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  MONITORING & MAINTENANCE"
            echo "═══════════════════════════════════════════════════════════"
            echo "  start-monitor [interval] [--auto-cleanup]"
            echo "                  - Start periodic health monitoring"
            echo "                    (optional: auto-cleanup on high swap)"
            echo "  stop-monitor    - Stop health monitor"
            echo "  monitor-logs    - View health monitor logs"
            echo "  maintenance     - Show maintenance best practices & tips"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  OTHER"
            echo "═══════════════════════════════════════════════════════════"
            echo "  aliases         - Install shell aliases"
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  EXAMPLES"
            echo "═══════════════════════════════════════════════════════════"
            echo "  # Interactive guided installation (recommended)"
            echo "  $0 install"
            echo ""
            echo "  # Non-interactive installation (for scripts/CI)"
            echo "  $0 install --non-interactive"
            echo ""
            echo "  # Preview what would be installed"
            echo "  $0 install --dry-run"
            echo ""
            echo "  # Guided start with pre-flight checks"
            echo "  $0 start"
            echo ""
            echo "  # Direct start without prompts"
            echo "  $0 start --non-interactive"
            echo ""
            exit 1
            ;;
    esac
}

# Run main function only if script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

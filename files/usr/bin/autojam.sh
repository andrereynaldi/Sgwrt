#!/bin/bash
# Sync Jam otomatis berdasarkan bug isp by AlkhaNET
# Extended GMT+7 by vitoharhari
# Simplify usage and improved codes by helmiau

# Variables
dtdir="/tmp/date_sync"
nmfl="$(basename "$0")"
scver="3.5"
max_retry=5

# Function to check if service is running
cek_service() {
    local service="$1"
    [ -f "/etc/init.d/$service" ] && /etc/init.d/$service status >/dev/null 2>&1
}

# Function to stop VPN services
nyetop() {
    echo "${nmfl}: Stopping VPN services..."
    
    # Stop Nikki
    if [ -f "/etc/init.d/nikki" ] && [ "$(uci -q get nikki.config.enabled)" = "1" ]; then
        if cek_service "nikki"; then
            /etc/init.d/nikki stop && echo "- Stopped nikki"
        fi
    fi
    
    # Stop Neko
    if [ -f "/etc/init.d/neko" ]; then
        if cek_service "neko"; then
            /etc/init.d/neko stop && echo "- Stopped neko"
        fi
    fi
    
    # Stop OpenClash
    if [ -f "/etc/init.d/openclash" ] && [ "$(uci -q get openclash.config.enable)" = "1" ]; then
        if cek_service "openclash"; then
            /etc/init.d/openclash stop && echo "- Stopped openclash"
        fi
    fi
    
    # Stop Passwall
    if [ -f "/etc/init.d/passwall" ]; then
        if cek_service "passwall"; then
            /etc/init.d/passwall stop && echo "- Stopped passwall"
        fi
    fi
}

# Function to start VPN services
nyetart() {
    echo "${nmfl}: Starting VPN services..."
    
    # Start Nikki
    if [ -f "/etc/init.d/nikki" ] && [ "$(uci -q get nikki.config.enabled)" = "1" ]; then
        if cek_service "nikki"; then
            /etc/init.d/nikki restart && echo "- Restarted nikki"
        else
            /etc/init.d/nikki start && echo "- Started nikki"
        fi
    fi
    
    # Start Neko
    if [ -f "/etc/init.d/neko" ]; then
        if cek_service "neko"; then
            /etc/init.d/neko restart && echo "- Restarted neko"
        else
            /etc/init.d/neko start && echo "- Started neko"
        fi
    fi
    
    # Start OpenClash
    if [ -f "/etc/init.d/openclash" ] && [ "$(uci -q get openclash.config.enable)" = "1" ]; then
        if cek_service "openclash"; then
            /etc/init.d/openclash restart && echo "- Restarted openclash"
        else
            /etc/init.d/openclash start && echo "- Started openclash"
        fi
    fi
    
    # Start Passwall  
    if [ -f "/etc/init.d/passwall" ]; then
        if cek_service "passwall"; then
            /etc/init.d/passwall restart && echo "- Restarted passwall"
        else
            /etc/init.d/passwall start && echo "- Started passwall"
        fi
    fi
}

# Function to get date from server
ngecurl() {
    if curl -si "$cv_type" 2>/dev/null | grep "Date:" > "$dtdir"; then
        echo "${nmfl}: Getting time from $cv_type"
        return 0
    else
        echo "${nmfl}: Failed to get date from $cv_type"
        return 1
    fi
}

# Function to set system date
sandal() {
    if [ ! -f "$dtdir" ] || [ ! -s "$dtdir" ]; then
        echo "${nmfl}: Date file not found or empty!"
        return 1
    fi
    
    # Parse date components
    hari=$(cut -b 12-13 "$dtdir" 2>/dev/null)
    bulan=$(cut -b 15-17 "$dtdir" 2>/dev/null)  
    tahun=$(cut -b 19-22 "$dtdir" 2>/dev/null)
    jam=$(cut -b 24-25 "$dtdir" 2>/dev/null)
    menit=$(cut -b 27-28 "$dtdir" 2>/dev/null)
    
    # Validate parsed data
    if [ -z "$hari" ] || [ -z "$bulan" ] || [ -z "$tahun" ] || [ -z "$jam" ] || [ -z "$menit" ]; then
        echo "${nmfl}: Failed to parse date components!"
        return 1
    fi
    
    # Convert month name to number
    case $bulan in
        Jan) bulan="01" ;;
        Feb) bulan="02" ;;
        Mar) bulan="03" ;;
        Apr) bulan="04" ;;
        May) bulan="05" ;;
        Jun) bulan="06" ;;
        Jul) bulan="07" ;;
        Aug) bulan="08" ;;
        Sep) bulan="09" ;;
        Oct) bulan="10" ;;
        Nov) bulan="11" ;;
        Dec) bulan="12" ;;
        *) 
            echo "${nmfl}: Invalid month format: $bulan"
            return 1 
            ;;
    esac
    
    # Set system date
    if date -s "$tahun-$bulan-$hari $jam:$menit:00" >/dev/null 2>&1; then
        echo "${nmfl}: Time set to $(date)"
        return 0
    else
        echo "${nmfl}: Failed to set system date!"
        return 1
    fi
}

# Function to check connection with retry limit
ngepink() {
    local retry_count=0
    
    while [ $retry_count -lt $max_retry ]; do
        if curl -si "$cv_type" 2>/dev/null | grep -q "Date:"; then
            echo "${nmfl}: Connection OK"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        
        if [ "$2" = "cron" ]; then
            echo "${nmfl}: No connection (attempt $retry_count/$max_retry), restarting VPN..."
            nyetop
            sleep 5
            nyetart
            sleep 10
        else
            echo "${nmfl}: No connection (attempt $retry_count/$max_retry), retrying in 3 seconds..."
            sleep 3
        fi
        
        # If max retry reached
        if [ $retry_count -eq $max_retry ]; then
            echo "${nmfl}: Max retry reached ($max_retry attempts), connection failed"
            return 1
        fi
    done
}

# Main execution
# Parameter validation
if echo "$1" | grep -q "^https\?://"; then
    cv_type=$(echo "$1" | sed 's|https|http|g')
elif echo "$1" | grep -q "\."; then
    cv_type="http://$1"
elif [ -n "$1" ]; then
    echo "Usage: $nmfl <domain/url> [cron]"
    echo "Example: $nmfl google.com"
    echo "Example: $nmfl google.com cron"
    exit 1
else
    echo "Usage: $nmfl <domain/url> [cron]"
    echo "Missing domain/URL parameter!"
    exit 1
fi

# Main process
if [ -n "$cv_type" ]; then
    echo "${nmfl}: Script v${scver}"
    mkdir -p "$(dirname "$dtdir")"
    
    if [ "$2" = "cron" ]; then
        echo "${nmfl}: Running in cron mode"
        if ngepink "$1" "$2"; then
            if ngecurl; then
                sandal
            fi
        else
            echo "${nmfl}: Cron mode: Connection failed after $max_retry attempts"
        fi
    else
        echo "${nmfl}: Running in manual mode"
        nyetop
        sleep 3
        if ngepink "$1" "$2"; then
            if ngecurl; then
                if sandal; then
                    sleep 3
                    nyetart
                fi
            fi
        else
            echo "${nmfl}: Manual mode: Connection failed after $max_retry attempts, restarting VPN anyway..."
            nyetart
        fi
    fi
    
    # Cleanup
    [ -f "$dtdir" ] && rm -f "$dtdir"
    echo "${nmfl}: Task completed"
fi

# Supported VPN Tunnels: Nikki, Neko/Nekobox, OpenClash, Passwall
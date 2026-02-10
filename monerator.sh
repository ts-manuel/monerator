#!/bin/bash

# Monero P2Pool and XMRig Setup Script
# For Ubuntu/Debian Systems
# 
# Automate the process of download, installation and configuration for the three
# main components related to Monero mining. The script will also create systemd
# service files to manage the startup and operation of each component.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to get latest Monero version
get_latest_monero_version() {
    local latest_version
    latest_version=$(curl -sL "https://api.github.com/repos/monero-project/monero/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    if [ -n "$latest_version" ]; then
        echo "$latest_version"
    else
        error "Failed to get latest Monero version"
    fi
}

# Function to get latest release version from GitHub
get_latest_p2pool_version() {
    local latest_version
    latest_version=$(curl -sL "https://api.github.com/repos/SChernykh/p2pool/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    if [ -n "$latest_version" ]; then
        echo "$latest_version"
    else
        error "Failed to get latest P2Pool version"
    fi
}

# Function to get latest XMRig version
get_latest_xmrig_version() {
    local latest_version
    latest_version=$(curl -sL "https://api.github.com/repos/xmrig/xmrig/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    if [ -n "$latest_version" ]; then
        echo "$latest_version"
    else
        error "Failed to get latest XMRig version"
    fi
}

load_configuration() {
    # Load the configuration file for the script (user-editable)
    CONFIG_FILE="$SOURCE_DIR/config/monerator.conf"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log "Loaded configuration from $CONFIG_FILE"
    else
        error "Configuration file not found: $CONFIG_FILE"
    fi

    # Setup directories based on BASE_DIR
    export MONERO_DIR="$BASE_DIR/monero"
    export P2POOL_DIR="$BASE_DIR/p2pool"
    export XMRIG_DIR="$BASE_DIR/xmrig"

    # Setup log file paths
    export MONEROD_LOG_FILE="/var/log/monerod.log"
    export MONEROD_ERROR_LOG_FILE="/var/log/monerod.error.log"
    export P2POOL_LOG_FILE="/var/log/p2pool.log"
    export P2POOL_ERROR_LOG_FILE="/var/log/p2pool.error.log"
    export XMRIG_LOG_FILE="/var/log/xmrig.log"

    # Set versions (use latest if not specified)
    MONERO_VERSION=${MONERO_VERSION:-$(get_latest_monero_version)}
    P2POOL_VERSION=${P2POOL_VERSION:-$(get_latest_p2pool_version)}
    XMRIG_VERSION=${XMRIG_VERSION:-$(get_latest_xmrig_version)}
}

# Function to load config parameters from a file
# the file should have lines in the format KEY=VALUE
# this function will convert them to command line arguments
# e.g. WALLET_ADDRESS=44... becomes --WALLET_ADDRESS 44...
load_config_parameters_from_file() {
    local file="$1"
    local args=()

    while IFS='=' read -r key value; do
        # Skip empty lines or comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        args+=( "--$key" "$value" )
    done < "$file"

    echo "${args[@]}"
}

install_dependencies() {
    log "Installing system dependencies..."
    
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y \
        build-essential \
        cmake \
        pkg-config \
        libssl-dev \
        libzmq3-dev \
        libsodium-dev \
        libpgm-dev \
        libuv1-dev \
        libunbound-dev \
        libminiupnpc-dev \
        libunwind-dev \
        liblzma-dev \
        libreadline-dev \
        libldns-dev \
        libexpat1-dev \
        libgtest-dev \
        libcurl4-openssl-dev \
        git \
        wget \
        tar
}

collect_user_inputs() {

    clear
    echo
    echo -e "${BLUE}===== Choose what component to install =====${NC}"
    echo
    echo -e "1) ${GREEN}Monero${NC}                   (Local monero node only)"
    echo -e "2) ${GREEN}XMRig${NC}                    (Monero miner only)"
    echo -e "3) ${GREEN}Monero + P2Pool${NC}          (Local mining pool without miner)"
    echo -e "4) ${GREEN}Monero + P2Pool + XMRig${NC}  (all components)"
    echo -e "5) ${GREEN}Exit${NC}"
    echo
    read -p "Select an option (1-5): " choice

    case $choice in
        1) CREATE_SERVICE_MONEROD="y"
            CREATE_SERVICE_P2POOL="n"
            CREATE_SERVICE_XMRIG="n" ;;
        2) CREATE_SERVICE_MONEROD="n"
            CREATE_SERVICE_P2POOL="n"
            CREATE_SERVICE_XMRIG="y" ;;
        3) CREATE_SERVICE_MONEROD="y"
            CREATE_SERVICE_P2POOL="y"
            CREATE_SERVICE_XMRIG="n" ;;
        4) CREATE_SERVICE_MONEROD="y"
            CREATE_SERVICE_P2POOL="y"
            CREATE_SERVICE_XMRIG="y" ;;
        5) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0 
            ;;
        *) 
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac


    # Check wallet address only if P2Pool is to be installed
    if [[ $CREATE_SERVICE_P2POOL =~ ^[Yy]$ ]]; then

        # Check if WALLET_ADDRESS is set in config
        local p2pool_config=$(load_config_parameters_from_file "$SOURCE_DIR/config/p2pool.conf")

        # Load wallet address from p2pool config if present
        WALLET_ADDRESS=""
        if [[ $p2pool_config =~ --wallet[[:space:]]+([0-9A-Za-z]+) ]]; then
            WALLET_ADDRESS="${BASH_REMATCH[1]}"
        else
            echo -e "${YELLOW}No wallet address found in p2pool configuration.${NC}"
        fi

        # Do check if not configured to skip or if no address is set
        if [ "$SKIP_WALLET_ADDRESS_CHECK" != 1 ] || [ "$WALLET_ADDRESS" == "" ]; then
            
            # If a wallet address is already present in config, offer to use it
            if [ -n "$WALLET_ADDRESS" ]; then
                echo
                echo -e "Found existing wallet address: ${GREEN}${WALLET_ADDRESS}${NC}"
                read -p "Do you want to use this address? [y/n]: " USE_EXISTING
                if [[ $USE_EXISTING =~ ^[Yy]$ ]]; then
                    : # WALLET_ADDRESS is already set from config
                else
                    WALLET_ADDRESS=""
                fi
            fi
        else
            echo -e "${YELLOW}Skipping wallet address validation as per configuration.${NC}"
            echo -e "${YELLOW}Using wallet address: ${WALLET_ADDRESS}${NC}"
        fi
        
        # If no existing address or user wants a new one
        if [ -z "$WALLET_ADDRESS" ]; then
            while true; do
                read -p "Enter your Monero wallet address (starts with 4): " WALLET_ADDRESS
                if [[ $WALLET_ADDRESS =~ ^4[0-9A-Za-z]{94}$ ]]; then
                    break
                else
                    echo -e "${RED}Invalid Monero address format. Please try again.${NC}"
                fi
            done
        fi

    fi

}

setup_monero_daemon() {
    log "Setting up Monero node version ${MONERO_VERSION}..."
    
    mkdir -p "$MONERO_DIR"
    mkdir -p "$MONERO_DIR/data"
    cd "$MONERO_DIR" || error "Failed to enter Monero directory"
    
    # Remove 'v' prefix if present
    local VERSION_NUM=${MONERO_VERSION#v}
    
    # Detect system architecture and set appropriate download URL
    local ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        local TARFILE="monero-linux-x64-v${VERSION_NUM}.tar.bz2"
    elif [[ "$ARCH" == "aarch64" ]]; then
        local TARFILE="monero-linux-armv8-v${VERSION_NUM}.tar.bz2"
    else
        error "Unsupported architecture: $ARCH"
    fi

    local DOWNLOAD_URL="https://downloads.getmonero.org/cli/${TARFILE}"
    
    if [ -f "$TARFILE" ]; then
        log "Found existing Monero archive, skipping download"
    else
        log "Downloading from: ${DOWNLOAD_URL}"
        wget -q "${DOWNLOAD_URL}" -O "$TARFILE" || error "Failed to download Monero"
    fi
    
    tar xjf "$TARFILE" --strip-components=1
    
    # Set proper permissions
    sudo chown -R $USER:$USER "$MONERO_DIR"
    sudo chmod -R 755 "$MONERO_DIR"
    
    # Create and set permissions for log file
    sudo touch ${MONERO_DIR}/monerod.log
    sudo chown $USER:$USER ${MONERO_DIR}/monerod.log
    sudo chmod 644 ${MONERO_DIR}/monerod.log

    # Copy monero config file and substitute variables
    envsubst < "$SOURCE_DIR/config/monerod.conf" > "$MONERO_DIR/monerod.conf" || error "Failed to copy monerod.conf"

    # Set proper permissions for data directory
    sudo chown -R $USER:$USER "$MONERO_DIR/data"
    sudo chmod -R 755 "$MONERO_DIR/data"

    # Monero daemon service
    sudo tee /etc/systemd/system/monerod.service > /dev/null << EOF
[Unit]
Description=Monero Full Node
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
ExecStart=${MONERO_DIR}/monerod --config-file=${MONERO_DIR}/monerod.conf --non-interactive
StandardOutput=append:${MONEROD_LOG_FILE}
StandardError=append:${MONEROD_ERROR_LOG_FILE}
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Enable the monerod service
    sudo systemctl daemon-reload
    sudo systemctl enable monerod

    log "Monero node setup completed."
}

check_blockchain_sync() {
    if [ -f "${MONERO_DIR}/data/lmdb/data.mdb" ]; then
        # Blockchain data exists, check if synced
        if tail -n 50 "${MONERO_DIR}/monerod.log" 2>/dev/null | grep -q "You are now synchronized with the network" || tail -n 50 "${MONERO_DIR}/monerod.log" 2>/dev/null | grep -q "100%"; then
            return 0  # Synced
        fi
    fi
    return 1  # Not synced
}

setup_p2pool() {
    log "Setting up P2Pool version ${P2POOL_VERSION}..."
    
    cd $BASE_DIR || error "Failed to enter base directory"

    # Detect system architecture and set appropriate download URL
    local ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        local P2POOL_FILENAME="p2pool-${P2POOL_VERSION}-linux-x64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        local P2POOL_FILENAME="p2pool-${P2POOL_VERSION}-linux-aarch64"
    else
        error "Unsupported architecture: $ARCH"
    fi

    local TARFILE="${P2POOL_FILENAME}.tar.gz"
    local DOWNLOAD_URL="https://github.com/SChernykh/p2pool/releases/download/${P2POOL_VERSION}/${TARFILE}"
    
    # Remove any existing corrupted files
    if [ -f "$TARFILE" ]; then
        log "Removing existing P2Pool archive..."
        rm -f "$TARFILE"
    fi
    
    # Remove existing p2pool directory if it exists
    if [ -d "$P2POOL_DIR" ]; then
        log "Removing existing P2Pool directory..."
        rm -rf "$P2POOL_DIR"
    fi

    # Download fresh copy
    log "Downloading from: ${DOWNLOAD_URL}"
    wget -q "${DOWNLOAD_URL}" || error "Failed to download P2Pool"

    # Verify the download
    if [ ! -f "$TARFILE" ] || [ ! -s "$TARFILE" ]; then
        error "P2Pool download failed or file is empty"
    fi

    # Extract with error checking
    log "Extracting P2Pool..."
    if ! tar xzf "$TARFILE"; then
        rm -f "$TARFILE"
        error "Failed to extract P2Pool"
    fi

    # Rename the extracted directory to 'p2pool'
    mv "${P2POOL_FILENAME}" "p2pool" || error "Failed to rename P2Pool directory"

    # Clean up
    rm -f "$TARFILE"

    # Make p2pool executable
    chmod +x "$P2POOL_DIR/p2pool" || error "Failed to make P2Pool executable"

    # Verify installation
    if [ ! -x "$P2POOL_DIR/p2pool" ]; then
        error "P2Pool installation failed: executable not found or not executable"
    fi

    # Load p2pool parameter from config file
    p2pool_args=$(load_config_parameters_from_file "$SOURCE_DIR/config/p2pool.conf")

    # Substitute wallet address if needed
    if [ -n "$WALLET_ADDRESS" ]; then
        p2pool_args=$(echo "$p2pool_args" | sed -E "s/--wallet[[:space:]]+[0-9A-Za-z]+/--wallet ${WALLET_ADDRESS}/")
    fi
    
    # P2Pool service
    sudo tee /etc/systemd/system/p2pool.service > /dev/null << EOF
[Unit]
Description=P2Pool Monero Mining
After=monerod.service
Requires=monerod.service

[Service]
Type=simple
User=$USER
Group=$USER
ExecStart=${P2POOL_DIR}/p2pool ${p2pool_args}
StandardOutput=append:${P2POOL_LOG_FILE}
StandardError=append:${P2POOL_ERROR_LOG_FILE}
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Enable the p2pool service
    sudo systemctl daemon-reload
    sudo systemctl enable p2pool

    # Log successful setup
    log "P2Pool setup completed successfully"
    log "Installation directory: $P2POOL_DIR"
    if [[ $USE_P2POOL_MINI =~ ^[Yy]$ ]]; then
        log "Running in mini mode (recommended for hashrates < 50 kH/s)"
    else
        log "Running in standard mode"
    fi
}

setup_xmrig() {
    log "Setting up XMRig CPU miner version ${XMRIG_VERSION}..."
    
    mkdir -p "$XMRIG_DIR"
    cd "$XMRIG_DIR" || error "Failed to enter XMRig directory"

    # XMRig does not provide official ARM buils,
    # TODO: add support for building from source.
    local ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        # Download and extract XMRig
        local XMRIG_VERSION_NUM=${XMRIG_VERSION#v}  # Remove 'v' prefix from version
        local DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/${XMRIG_VERSION}/xmrig-${XMRIG_VERSION_NUM}-noble-x64.tar.gz"
        
        log "Downloading from: ${DOWNLOAD_URL}"
        wget -q "${DOWNLOAD_URL}" -O xmrig.tar.gz || error "Failed to download XMRig"
        tar xzf xmrig.tar.gz --strip-components=1 || error "Failed to extract XMRig"
        rm xmrig.tar.gz
    elif [[ "$ARCH" == "aarch64" ]]; then
        # TODO: Add support for building XMRig from source on ARM architecture
        error "Unsupported architecture: $ARCH"
    else
        error "Unsupported architecture: $ARCH"
    fi

    # Set executable permissions
    chmod +x xmrig

    # Verify installation
    if [ ! -x "$XMRIG_DIR/xmrig" ]; then
        error "XMRig installation failed"
    fi

    # Load p2pool parameter from config file
    xmrig_args=$(load_config_parameters_from_file "$SOURCE_DIR/config/xmrig.conf")

    # Substitute log file path
    xmrig_args=$(echo "$xmrig_args" | sed "s|\${XMRIG_LOG_FILE}|${XMRIG_LOG_FILE}|g")

    # XMRig service
    sudo tee /etc/systemd/system/xmrig.service > /dev/null << EOF
[Unit]
Description=XMRig CPU Miner
After=$(if [[ $CREATE_SERVICE_P2POOL =~ ^[Yy]$ ]]; then echo "p2pool.service"; else echo "network.target"; fi)
$(if [[ $CREATE_SERVICE_P2POOL =~ ^[Yy]$ ]]; then echo "Requires=p2pool.service"; fi)

[Service]
Type=simple
User=root
Group=root
ExecStart=${XMRIG_DIR}/xmrig ${xmrig_args}
Restart=always
RestartSec=30
Nice=10

[Install]
WantedBy=multi-user.target
EOF

    # Enable the xmrig service
    sudo systemctl daemon-reload
    sudo systemctl enable xmrig

    log "XMRig setup completed successfully"
}

setup_logs() {
    # Create log files with proper permissions
    sudo install -m 644 -o $USER -g $USER /dev/null ${MONEROD_LOG_FILE}
    sudo install -m 644 -o $USER -g $USER /dev/null ${MONEROD_ERROR_LOG_FILE}
    sudo install -m 644 -o $USER -g $USER /dev/null ${P2POOL_LOG_FILE}
    sudo install -m 644 -o $USER -g $USER /dev/null ${P2POOL_ERROR_LOG_FILE}
    # XMRig logs should be owned by root
    sudo install -m 644 -o root -g root /dev/null ${XMRIG_LOG_FILE}
}

# Install all the components and create services
install() {
    # Check if script is run as root
    if [ "$(id -u)" = "0" ]; then
        error "This script should not be run as root"
    fi

    clear
    echo
    echo -e "${BLUE}===== Installing Monero P2Poll XMRIG =====${NC}"

    # Create base directory
    mkdir -p "$BASE_DIR"

    collect_user_inputs

    # Check if there is something to install
    if [[ ! $CREATE_SERVICE_MONEROD =~ ^[Yy]$ && ! $CREATE_SERVICE_P2POOL =~ ^[Yy]$ && ! $CREATE_SERVICE_XMRIG =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}No components selected for installation. Exiting...${NC}"
        exit 0
    fi

    install_dependencies

    # Setup Monero daemon if selected
    if [[ $CREATE_SERVICE_MONEROD =~ ^[Yy]$ ]]; then
        setup_monero_daemon

        # Check if blockchain needs syncing
        if ! check_blockchain_sync; then
            echo -e "${YELLOW}The Monero blockchain is not fully synced yet.${NC}"
            read -p "Do you want to sync it before continuing? (recommended) [y/n]: " SYNC_FIRST
            
            if [[ $SYNC_FIRST =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}Starting Monero daemon for initial sync...${NC}"
                echo -e "${YELLOW}This may take several hours. You can press Ctrl+C to stop syncing.${NC}"
                echo -e "${YELLOW}The sync will continue from where it left off next time.${NC}"
                
                # Set up interrupt handler
                trap handle_interrupt SIGINT
                
                # Run monerod in interactive mode for initial sync
                if ! (cd "${MONERO_DIR}" && sudo ./monerod --config-file=${MONERO_DIR}/monerod.conf); then
                    echo -e "\n${RED}Sync was interrupted or failed. Exiting...${NC}"
                    exit 1
                fi
                
                # Remove the trap handler
                trap - SIGINT
                
                # Check if sync completed successfully
                if ! check_blockchain_sync; then
                    echo -e "\n${RED}Blockchain sync did not complete successfully. Please run the script again.${NC}"
                    exit 1
                fi
                
                echo -e "\n${GREEN}Blockchain sync completed successfully!${NC}"
            fi
        fi
    fi

    # Setup P2Pool if selected
    if [[ $CREATE_SERVICE_P2POOL =~ ^[Yy]$ ]]; then
        setup_p2pool
    fi

    # Setup XMRig if selected
    if [[ $CREATE_SERVICE_XMRIG =~ ^[Yy]$ ]]; then
        setup_xmrig
    fi

    setup_logs

    start_services

    # Show completion message
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Mining directory: ${BLUE}$BASE_DIR${NC}"
    echo
    echo -e "Use '${YELLOW}./monerator status${NC}' to check service status"
}

# Function to uninstall the the services and remove files
uninstall() {
    clear
    echo
    echo -e "${BLUE}===== Uninstalling Monero P2Pool XMRIG =====${NC}"

    # Get sudo privileges
    if not sudo -v; then
        echo -e "${RED}Error: Failed to obtain sudo privileges. Uninstallation aborted.${NC}"
        exit 1
    fi
    
    stop_services

    # Remove systemd services
    echo "Removing systemd services..."
    sudo systemctl disable monerod.service p2pool.service xmrig.service 2>/dev/null
    sudo rm -f /etc/systemd/system/monerod.service
    sudo rm -f /etc/systemd/system/p2pool.service
    sudo rm -f /etc/systemd/system/xmrig.service
    sudo systemctl daemon-reload

    # Ask user if they want to remove data
    read -p "Do you want to remove all data? (y/n): " REMOVE_DATA
    if [[ $REMOVE_DATA =~ ^[Yy]$ ]]; then
        echo "Removing all mining data..."
        rm -rf "$BASE_DIR"
    else
        echo "Mining data preserved."
    fi

    echo -e "${GREEN}Uninstallation completed successfully.${NC}"
}

start_services() {
    log "Starting mining services..."

    if systemctl is-enabled --quiet monerod.service; then
        sudo systemctl start monerod
        sleep 10  # Wait for Monero daemon to initialize
    fi

    if systemctl is-enabled --quiet p2pool.service; then
        sudo systemctl start p2pool
        sleep 5   # Wait for P2Pool to initialize
    fi

    if systemctl is-enabled --quiet xmrig.service; then
        sudo systemctl start xmrig
    fi
}

stop_services() {
    clear
    echo
    echo -e "${BLUE}===== Stopping Mining Services =====${NC}"

    if systemctl is-active --quiet xmrig.service; then
        sudo systemctl stop xmrig
    fi

    if systemctl is-active --quiet p2pool.service; then
        sudo systemctl stop p2pool
    fi

    if systemctl is-active --quiet monerod.service; then
        sudo systemctl stop monerod
    fi
}

check_services_status() {
    clear
    echo
    echo -e "${BLUE}===== Monero Mining Services Status =====${NC}"

    for service in monerod p2pool xmrig; do
        status=$(systemctl is-active $service.service)
        if [ "$status" = "active" ]; then
            echo -e "${GREEN}● $service.service is running${NC}"
        else
            echo -e "${RED}○ $service.service is $status${NC}"
        fi
        echo "---"
        systemctl status $service.service --no-pager | grep -A 2 "Active:"
        echo
    done
}

show_logs() {
    clear
    echo
    echo -e "${BLUE}===== Available Log Files =====${NC}"

    log_files=(
        "${MONEROD_LOG_FILE}"              # Monero daemon service log
        "${MONEROD_ERROR_LOG_FILE}"        # Monero daemon error log
        "${P2POOL_LOG_FILE}"               # P2Pool log
        "${P2POOL_ERROR_LOG_FILE}"         # P2Pool error log
        "${XMRIG_LOG_FILE}"                # XMRig log
    )

    # Display log files
    for i in "${!log_files[@]}"; do
        echo -e "${GREEN}[$i] ${log_files[$i]}${NC}"
    done

    # Get user selection
    read -p "Select a log file to view (0-$((${#log_files[@]}-1))): " log_selection

    # Validate selection
    if ! [[ "$log_selection" =~ ^[0-9]+$ ]] || [ "$log_selection" -lt 0 ] || [ "$log_selection" -ge "${#log_files[@]}" ]; then
        echo -e "${RED}Invalid selection. Exiting...${NC}"
        return
    fi

    # Display selected log file
    selected_log="${log_files[$log_selection]}"
    echo -e "${YELLOW}Displaying content of: $selected_log${NC}"
    echo

    # Check if the log file exists before attempting to print
    if [ -f "$selected_log" ]; then
        tail -f "$selected_log"
    else
        echo -e "${RED}Log file does not exist: $selected_log${NC}"
    fi
}

delete_logs() {
    clear
    echo
    echo -e "${BLUE}===== Delete Log Files =====${NC}"

    local logs=(
        "${MONEROD_LOG_FILE}"
        "${MONEROD_ERROR_LOG_FILE}"
        "${P2POOL_LOG_FILE}"
        "${P2POOL_ERROR_LOG_FILE}"
        "${XMRIG_LOG_FILE}"
    )

    echo "Available logs to delete:"
    for i in "${!logs[@]}"; do
        echo "[$i] ${logs[$i]}"
    done

    read -p "Enter the number of the log to delete (or 'all' to delete all logs): " choice

    if [[ "$choice" == "all" ]]; then
        for log in "${logs[@]}"; do
            if [ -f "$log" ]; then
                sudo rm "$log"
                echo "Deleted: $log"
            else
                echo "File not found: $log"
            fi
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt ${#logs[@]} ]; then
        if [ -f "${logs[$choice]}" ]; then
            sudo rm "${logs[$choice]}"
            echo "Deleted: ${logs[$choice]}"
        else
            echo "File not found: ${logs[$choice]}"
        fi
    else
        echo "Invalid choice"
        return 1
    fi

    echo
    read -p "Press Enter to continue..."
}

await_enter() {
    echo
    read -p "Press Enter to continue..."
}

show_interactive_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║             Monerator              ║${NC}"
        echo -e "${BLUE}║         interactive menu           ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
        echo
        echo -e "1) ${GREEN}Install${NC}"
        echo -e "2) ${GREEN}Uninstall${NC}"
        echo -e "3) ${GREEN}Start the services${NC}"
        echo -e "4) ${GREEN}Stop the services${NC}"
        echo -e "5) ${GREEN}Show status of services${NC}"
        echo -e "6) ${GREEN}Show Logs${NC}"
        echo -e "7) ${GREEN}Delete Logs${NC}"
        echo -e "8) ${GREEN}Exit${NC}"
        echo
        read -p "Select an option (1-8): " choice

        case $choice in
            1) install ;;
            2) uninstall ;;
            3) start_services
               await_enter ;;
            4) stop_services
               await_enter ;;
            5) check_services_status 
               await_enter ;;
            6) show_logs ;;
            7) delete_logs ;;
            8) 
                echo -e "${GREEN}Exiting...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Entry point for the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo -e "\n${RED}Script interrupted${NC}"; exit 1' SIGINT SIGTERM

    # Get the directory of the script
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    load_configuration

    if [ $# -eq 0 ]; then
        show_interactive_menu
    else
        case "$1" in
            install)
                install
                ;;
            uninstall)
                uninstall
                ;;
            start)
                start_services
                check_services_status
                exit 0
                ;;
            stop)
                stop_services
                check_services_status
                exit 0
                ;;
            status)
                check_services_status
                exit 0
                ;;
            logs)
                show_logs
                ;;
            delete-logs)
                delete_logs
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
    fi
fi

exit 0
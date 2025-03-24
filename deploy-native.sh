#!/bin/bash

# GiteaSecureLaunch - Native Deployment Script (Without Docker)
set -e

echo "==== GiteaSecureLaunch Native Deployment Script ===="
echo "This script will install Gitea directly on your system without Docker"
echo

# Function to check system requirements
check_system_requirements() {
    echo "Checking system requirements..."
    
    # Check for required tools
    local missing_deps=()
    
    for cmd in curl openssl git; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install them before continuing."
        
        if [ "$OS" = "Linux" ]; then
            if command -v apt-get &> /dev/null; then
                echo "Try: sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}"
            elif command -v dnf &> /dev/null; then
                echo "Try: sudo dnf install -y ${missing_deps[*]}"
            elif command -v pacman &> /dev/null; then
                echo "Try: sudo pacman -Sy ${missing_deps[*]}"
            fi
        elif [ "$OS" = "Darwin" ]; then
            echo "Try: brew install ${missing_deps[*]}"
        fi
        
        read -p "Do you want to try to install them now? (y/n): " install_deps
        if [[ "$install_deps" == "y" || "$install_deps" == "Y" ]]; then
            if [ "$OS" = "Linux" ]; then
                if command -v apt-get &> /dev/null; then
                    safe_apt_get "update"
                    safe_apt_get "install -y ${missing_deps[*]}"
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y ${missing_deps[*]}
                elif command -v pacman &> /dev/null; then
                    sudo pacman -Sy ${missing_deps[*]}
                fi
            elif [ "$OS" = "Darwin" ]; then
                brew install ${missing_deps[*]}
            fi
        else
            echo "Please install the required dependencies and run the script again."
            exit 1
        fi
    else
        echo "All required dependencies are installed."
    fi
    
    # Check disk space
    if [ "$OS" = "Linux" ]; then
        local available_space=$(df -m / | awk 'NR==2 {print $4}')
        if [ "$available_space" -lt 1000 ]; then
            echo "Warning: Less than 1GB of free disk space available. This might not be enough for Gitea."
            read -p "Continue anyway? (y/n): " continue_space
            if [[ "$continue_space" != "y" && "$continue_space" != "Y" ]]; then
                exit 1
            fi
        fi
    fi
    
    # Check memory
    if [ "$OS" = "Linux" ]; then
        local available_mem=$(free -m | awk 'NR==2 {print $7}')
        if [ "$available_mem" -lt 512 ]; then
            echo "Warning: Less than 512MB of free memory available. Gitea might not perform well."
            read -p "Continue anyway? (y/n): " continue_mem
            if [[ "$continue_mem" != "y" && "$continue_mem" != "Y" ]]; then
                exit 1
            fi
        fi
    fi
    
    echo "System check complete."
}

# Create required directories
GITEA_HOME_DIR="$HOME/gitea"
DATA_DIR="$GITEA_HOME_DIR/data"
CUSTOM_DIR="$GITEA_HOME_DIR/custom"
CONFIG_DIR="$GITEA_HOME_DIR/custom/conf"
WORK_DIR="$GITEA_HOME_DIR/work"
LOG_DIR="$GITEA_HOME_DIR/log"
CERTS_DIR="$GITEA_HOME_DIR/certs"

# Load environment variables
if [ -f .env ]; then
    source .env
    echo "Loaded configuration from .env file."
else
    echo "Error: .env file not found!"
    exit 1
fi

# Check operating system
OS=$(uname -s)
case "$OS" in
    Linux)
        echo "Detected Linux OS..."
        ;;
    Darwin)
        echo "Detected macOS..."
        ;;
    *)
        echo "Error: Unsupported operating system: $OS"
        echo "This script supports Linux and macOS only."
        exit 1
        ;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    i386|i686)
        ARCH="386"
        ;;
    armv7l|armv7)
        ARCH="arm-7"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "System architecture: $ARCH"

# Function to safely run apt-get with retry logic
safe_apt_get() {
    local cmd=$1
    local max_attempts=5
    local attempt=1
    local wait_time=10

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: Running apt-get $cmd..."
        
        if sudo apt-get $cmd; then
            echo "Successfully ran apt-get $cmd"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                echo "Error running apt-get $cmd. Waiting $wait_time seconds before retry..."
                sleep $wait_time
                # Increase wait time for each retry
                wait_time=$((wait_time + 10))
            else
                echo "Failed to run apt-get $cmd after $max_attempts attempts."
                echo "You may try one of the following:"
                echo "1. Wait for any ongoing system updates to complete"
                echo "2. Check active apt processes: ps aux | grep apt"
                echo "3. If safe, you can manually fix with: sudo rm /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* && sudo dpkg --configure -a"
                return 1
            fi
        fi
        
        attempt=$((attempt + 1))
    done
}

# Check system requirements before proceeding
check_system_requirements

# Check for PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL client not found. Installing PostgreSQL..."
    
    if [ "$OS" = "Linux" ]; then
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y postgresql postgresql-contrib
        elif command -v dnf &> /dev/null; then
            # Fedora/RHEL/CentOS
            sudo dnf install -y postgresql-server postgresql-contrib
            sudo postgresql-setup --initdb
            sudo systemctl enable postgresql
            sudo systemctl start postgresql
        elif command -v pacman &> /dev/null; then
            # Arch Linux
            sudo pacman -Sy postgresql
            sudo -u postgres initdb -D /var/lib/postgres/data
            sudo systemctl enable postgresql
            sudo systemctl start postgresql
        else
            echo "Unable to determine package manager. Please install PostgreSQL manually."
            exit 1
        fi
    elif [ "$OS" = "Darwin" ]; then
        # macOS with Homebrew
        if command -v brew &> /dev/null; then
            brew install postgresql
            brew services start postgresql
        else
            echo "Homebrew not installed. Please install Homebrew and PostgreSQL manually."
            exit 1
        fi
    fi
    
    echo "PostgreSQL installed successfully."
fi

# Create PostgreSQL user and database
echo "Setting up PostgreSQL database..."
if [ "$OS" = "Linux" ]; then
    sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" || echo "User may already exist"
    sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;" || echo "Database may already exist"
elif [ "$OS" = "Darwin" ]; then
    psql postgres -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" || echo "User may already exist"
    psql postgres -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;" || echo "Database may already exist"
fi

# Determine deployment type
echo
echo "Deployment Type:"
echo "1) Local development (HTTP, port 3000)"
echo "2) Local HTTPS with localhost (HTTPS, port 443)"
echo "3) Production server with domain name (HTTPS, port 443)"
echo "4) Production server with IP address (HTTPS, port 443)"
read -p "Select deployment type [1/2/3/4]: " deployment_type

# Create necessary directories
echo "Creating necessary directories..."
mkdir -p "$DATA_DIR" "$CUSTOM_DIR" "$CONFIG_DIR" "$WORK_DIR" "$LOG_DIR" "$CERTS_DIR"

# Download and install Gitea
echo "Downloading Gitea..."
# Add retry logic for getting the latest version
max_attempts=3
attempt=1
success=0

while [ $attempt -le $max_attempts ] && [ $success -eq 0 ]; do
    echo "Attempt $attempt to get latest Gitea version..."
    if GITEA_VERSION=$(curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest | grep tag_name | cut -d '"' -f 4); then
        # Remove 'v' prefix for filename but keep it for URL path
        GITEA_VERSION_NUM="${GITEA_VERSION#v}"
        echo "Latest Gitea version: $GITEA_VERSION"
        success=1
    else
        if [ $attempt -lt $max_attempts ]; then
            echo "Failed to get version info. Retrying in 5 seconds..."
            sleep 5
        else
            echo "Failed after $max_attempts attempts. Using a default version."
            GITEA_VERSION="v1.23.5"
            GITEA_VERSION_NUM="1.23.5"
        fi
    fi
    attempt=$((attempt + 1))
done

# Create a temporary directory for downloads
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Use GitHub's release URL format that works
if [ "$OS" = "Linux" ]; then
    GITEA_URL="https://github.com/go-gitea/gitea/releases/download/$GITEA_VERSION/gitea-$GITEA_VERSION_NUM-linux-$ARCH"
elif [ "$OS" = "Darwin" ]; then
    GITEA_URL="https://github.com/go-gitea/gitea/releases/download/$GITEA_VERSION/gitea-$GITEA_VERSION_NUM-darwin-$ARCH"
fi

echo "Downloading from: $GITEA_URL"

# Add retry logic for downloading
max_dl_attempts=3
dl_attempt=1
dl_success=0

while [ $dl_attempt -le $max_dl_attempts ] && [ $dl_success -eq 0 ]; do
    echo "Download attempt $dl_attempt..."
    if curl -L -o gitea "$GITEA_URL"; then
        # Verify the download is a binary, not an HTML file
        if file gitea | grep -q "HTML"; then
            echo "Error: Downloaded an HTML file instead of the Gitea binary."
            if [ $dl_attempt -lt $max_dl_attempts ]; then
                echo "Retrying in 5 seconds..."
                sleep 5
            else
                echo "Failed to download after $max_dl_attempts attempts."
                echo "Please download Gitea manually from: https://github.com/go-gitea/gitea/releases/latest"
                exit 1
            fi
        else
            echo "Successfully downloaded Gitea binary."
            dl_success=1
        fi
    else
        if [ $dl_attempt -lt $max_dl_attempts ]; then
            echo "Download failed. Retrying in 5 seconds..."
            sleep 5
        else
            echo "Failed to download after $max_dl_attempts attempts."
            echo "Please download Gitea manually from: https://github.com/go-gitea/gitea/releases/latest"
            exit 1
        fi
    fi
    dl_attempt=$((dl_attempt + 1))
done

chmod +x gitea

# Move Gitea to installation directory
mv gitea "$GITEA_HOME_DIR/"
cd - > /dev/null

# Create systemd service file (Linux only)
if [ "$OS" = "Linux" ]; then
    echo "Creating dedicated Gitea user..."
    # Create gitea user if it doesn't exist
    if ! id "git" &>/dev/null; then
        sudo useradd --system --shell /bin/bash --home-dir /home/git --create-home git
        echo "User 'git' created."
    else
        echo "User 'git' already exists."
    fi
    
    # Ensure proper ownership of Gitea directories
    sudo chown -R git:git "$GITEA_HOME_DIR"
    
    echo "Creating systemd service file..."
    cat > /tmp/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=git
Type=simple
WorkingDirectory=$GITEA_HOME_DIR
ExecStart=$GITEA_HOME_DIR/gitea web -c $CONFIG_DIR/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=$WORK_DIR

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/gitea.service /etc/systemd/system/gitea.service
    sudo systemctl daemon-reload
fi

# Configure Gitea
echo "Configuring Gitea..."

# Create initial configuration
cat > "$CONFIG_DIR/app.ini" << EOF
APP_NAME = $APP_NAME
RUN_USER = $(whoami)
RUN_MODE = prod

[database]
DB_TYPE = postgres
HOST = 127.0.0.1:5432
NAME = $POSTGRES_DB
USER = $POSTGRES_USER
PASSWD = $POSTGRES_PASSWORD
SSL_MODE = disable

[repository]
ROOT = $DATA_DIR/gitea-repositories

[server]
EOF

# Configure server section based on deployment type
if [ "$deployment_type" = "1" ]; then
    echo "Configuring for local development (HTTP)..."
    
    # Set domain to localhost if not specified
    read -p "Domain for Gitea [$DOMAIN] (or leave empty for 'localhost'): " input_domain
    DOMAIN=${input_domain:-${DOMAIN:-localhost}}
    
    # Add host entry if domain is not localhost
    if [ "$DOMAIN" != "localhost" ]; then
        read -p "Would you like to add an entry to /etc/hosts for local testing? [Y/n]: " add_hosts
        if [[ "$add_hosts" != "n" && "$add_hosts" != "N" ]]; then
            echo "Adding entry to /etc/hosts file..."
            echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
            echo "Entry added: 127.0.0.1 $DOMAIN"
        fi
    fi
    
    cat >> "$CONFIG_DIR/app.ini" << EOF
DOMAIN = $DOMAIN
HTTP_PORT = 3000
ROOT_URL = http://$DOMAIN:3000/
DISABLE_SSH = false
SSH_PORT = 2222
PROTOCOL = http
LFS_START_SERVER = true
LFS_CONTENT_PATH = $DATA_DIR/lfs
EOF

    echo "HTTP configuration complete!"
    echo "Your Gitea instance will be available at: http://$DOMAIN:3000"

elif [ "$deployment_type" = "2" ]; then
    echo "Configuring for local HTTPS with localhost..."
    
    # Set domain to localhost
    DOMAIN="localhost"
    
    # Generate self-signed certificates for localhost
    echo "Generating SSL certificates for localhost..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$CERTS_DIR/key.pem" -out "$CERTS_DIR/cert.pem" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    
    # Fix certificates permissions
    chmod 600 "$CERTS_DIR/key.pem"
    chmod 644 "$CERTS_DIR/cert.pem"
    
    cat >> "$CONFIG_DIR/app.ini" << EOF
DOMAIN = localhost
HTTP_PORT = 3000
ROOT_URL = https://localhost/
DISABLE_SSH = false
SSH_PORT = 2222
PROTOCOL = https
CERT_FILE = $CERTS_DIR/cert.pem
KEY_FILE = $CERTS_DIR/key.pem
LFS_START_SERVER = true
LFS_CONTENT_PATH = $DATA_DIR/lfs
EOF

    echo "HTTPS configuration complete!"
    echo "Your Gitea instance will be available at: https://localhost"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."

elif [ "$deployment_type" = "4" ]; then
    echo "Configuring for production deployment (HTTPS) with IP address..."
    
    # Get server IP address
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Detected server IP: $SERVER_IP"
    read -p "Use this IP address? [Y/n]: " use_detected_ip
    
    if [[ "$use_detected_ip" = "n" || "$use_detected_ip" = "N" ]]; then
        read -p "Enter your server's IP address: " SERVER_IP
    fi
    
    # Set domain to IP address
    DOMAIN="$SERVER_IP"
    
    # Generate self-signed certificates for IP address
    echo "Generating SSL certificates for IP address $SERVER_IP..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$CERTS_DIR/key.pem" -out "$CERTS_DIR/cert.pem" \
        -subj "/CN=$SERVER_IP" \
        -addext "subjectAltName=IP:$SERVER_IP"
    
    # Fix certificates permissions
    chmod 600 "$CERTS_DIR/key.pem"
    chmod 644 "$CERTS_DIR/cert.pem"
    
    cat >> "$CONFIG_DIR/app.ini" << EOF
DOMAIN = $SERVER_IP
HTTP_PORT = 3000
ROOT_URL = https://$SERVER_IP/
DISABLE_SSH = false
SSH_PORT = 2222
PROTOCOL = https
CERT_FILE = $CERTS_DIR/cert.pem
KEY_FILE = $CERTS_DIR/key.pem
LFS_START_SERVER = true
LFS_CONTENT_PATH = $DATA_DIR/lfs
EOF

    echo "Your Gitea instance will be available at: https://$SERVER_IP"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."

elif [ "$deployment_type" = "3" ]; then
    echo "Configuring for production deployment (HTTPS) with domain name..."
    
    # Get domain name
    read -p "Enter your domain name (e.g., git.example.com): " DOMAIN_NAME
    
    # Set domain
    DOMAIN="$DOMAIN_NAME"
    
    # Ask if user wants to generate self-signed or use Let's Encrypt
    echo
    echo "SSL Certificate Options:"
    echo "1) Self-signed certificate (for testing)"
    echo "2) Let's Encrypt (requires domain to point to this server)"
    read -p "Select certificate type [1/2]: " cert_type
    
    if [ "$cert_type" = "1" ]; then
        # Generate self-signed certificates for domain
        echo "Generating self-signed SSL certificates for domain $DOMAIN..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
            -keyout "$CERTS_DIR/key.pem" -out "$CERTS_DIR/cert.pem" \
            -subj "/CN=$DOMAIN" \
            -addext "subjectAltName=DNS:$DOMAIN"
        
        # Fix certificates permissions
        chmod 600 "$CERTS_DIR/key.pem"
        chmod 644 "$CERTS_DIR/cert.pem"
        
        echo "Self-signed certificates generated successfully."
        echo "Note: You will need to accept the self-signed certificate warning in your browser."
        
        cat >> "$CONFIG_DIR/app.ini" << EOF
DOMAIN = $DOMAIN
HTTP_PORT = 3000
ROOT_URL = https://$DOMAIN/
DISABLE_SSH = false
SSH_PORT = 2222
PROTOCOL = https
CERT_FILE = $CERTS_DIR/cert.pem
KEY_FILE = $CERTS_DIR/key.pem
LFS_START_SERVER = true
LFS_CONTENT_PATH = $DATA_DIR/lfs
EOF
    else
        # We'll use Let's Encrypt, which requires further setup
        echo "Let's Encrypt setup requires domain to be properly configured to point to this server."
        echo "Please make sure your domain $DOMAIN points to this server before continuing."
        read -p "Press Enter to continue or Ctrl+C to abort..."
        
        # Check if certbot is installed
        if ! command -v certbot &> /dev/null; then
            echo "Installing Certbot..."
            if [ "$OS" = "Linux" ]; then
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y certbot
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y certbot
                elif command -v pacman &> /dev/null; then
                    sudo pacman -Sy certbot
                fi
            elif [ "$OS" = "Darwin" ]; then
                brew install certbot
            fi
        fi
        
        # Get certificates using certbot standalone mode
        echo "Obtaining Let's Encrypt certificates..."
        sudo certbot certonly --standalone --agree-tos --email admin@$DOMAIN -d $DOMAIN
        
        # Copy certificates to the right location
        sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$CERTS_DIR/cert.pem"
        sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$CERTS_DIR/key.pem"
        
        # Fix permissions
        sudo chmod 644 "$CERTS_DIR/cert.pem"
        sudo chmod 600 "$CERTS_DIR/key.pem"
        
        echo "Let's Encrypt certificates obtained successfully."
        
        # Set up auto-renewal
        echo "Setting up certificate auto-renewal..."
        RENEWAL_SCRIPT="$GITEA_HOME_DIR/renew-cert.sh"
        cat > "$RENEWAL_SCRIPT" << EOFS
#!/bin/bash
sudo certbot renew --quiet
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$CERTS_DIR/cert.pem"
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$CERTS_DIR/key.pem"
sudo chmod 644 "$CERTS_DIR/cert.pem"
sudo chmod 600 "$CERTS_DIR/key.pem"
EOFS
        chmod +x "$RENEWAL_SCRIPT"
        
        # Add to crontab
        (crontab -l 2>/dev/null; echo "0 3 * * * $RENEWAL_SCRIPT") | crontab -
        
        echo "Certificate auto-renewal configured."
        
        cat >> "$CONFIG_DIR/app.ini" << EOF
DOMAIN = $DOMAIN
HTTP_PORT = 3000
ROOT_URL = https://$DOMAIN/
DISABLE_SSH = false
SSH_PORT = 2222
PROTOCOL = https
CERT_FILE = $CERTS_DIR/cert.pem
KEY_FILE = $CERTS_DIR/key.pem
LFS_START_SERVER = true
LFS_CONTENT_PATH = $DATA_DIR/lfs
EOF
    fi
    
    echo "Your Gitea instance will be available at: https://$DOMAIN"
fi

# Complete the configuration with default settings
cat >> "$CONFIG_DIR/app.ini" << EOF
[log]
ROOT_PATH = $LOG_DIR
MODE = file
LEVEL = info

[security]
INSTALL_LOCK = false

[service]
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
DISABLE_REGISTRATION = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA = false
REQUIRE_SIGNIN_VIEW = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.localhost

[mailer]
ENABLED = false

[picture]
DISABLE_GRAVATAR = false
ENABLE_FEDERATED_AVATAR = true

[openid]
ENABLE_OPENID_SIGNIN = true
ENABLE_OPENID_SIGNUP = true

[session]
PROVIDER = file

[indexer]
ISSUE_INDEXER_TYPE = bleve
REPO_INDEXER_ENABLED = true
REPO_INDEXER_TYPE = bleve

[admin]
DEFAULT_EMAIL_NOTIFICATIONS = enabled
EOF

# Start Gitea
echo "Starting Gitea..."
if [ "$OS" = "Linux" ]; then
    # Test the binary first to ensure it works
    echo "Testing Gitea binary..."
    if ! sudo -u git "$GITEA_HOME_DIR/gitea" --version; then
        echo "Error: The Gitea binary does not work correctly."
        echo "This may be due to missing dependencies or incorrect permissions."
        echo "You may need to install dependencies: sudo apt-get install git curl"
        exit 1
    fi
    
    # Start using systemd with retry logic
    for i in 1 2 3; do
        echo "Attempt $i to start Gitea service..."
        if sudo systemctl enable gitea && sudo systemctl start gitea; then
            if sudo systemctl is-active --quiet gitea; then
                echo "Gitea is now running as a system service."
                echo "You can manage it with: sudo systemctl [start|stop|restart|status] gitea"
                break
            else
                echo "Gitea service started but is not active. Checking logs..."
                sudo journalctl -u gitea --no-pager -n 20
                if [ $i -lt 3 ]; then
                    echo "Waiting before retry..."
                    sleep 5
                fi
            fi
        elif [ $i -lt 3 ]; then
            echo "Failed to start Gitea service. Waiting before retry..."
            sleep 5
        else
            echo "Failed to start Gitea service after multiple attempts."
            echo "Checking logs for errors:"
            sudo journalctl -u gitea --no-pager -n 30
            echo
            echo "You can manually start it with: sudo systemctl start gitea"
            echo "And check its status with: sudo systemctl status gitea"
        fi
    done
    
elif [ "$OS" = "Darwin" ]; then
    # Create a launchd plist file for macOS
    cat > ~/Library/LaunchAgents/io.gitea.web.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.gitea.web</string>
    <key>ProgramArguments</key>
    <array>
        <string>$GITEA_HOME_DIR/gitea</string>
        <string>web</string>
        <string>-c</string>
        <string>$CONFIG_DIR/app.ini</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$GITEA_HOME_DIR</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/gitea-error.log</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/gitea-output.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GITEA_WORK_DIR</key>
        <string>$WORK_DIR</string>
    </dict>
</dict>
</plist>
EOF

    # Try to load the launchd service
    if launchctl load ~/Library/LaunchAgents/io.gitea.web.plist; then
        echo "Gitea is now running as a launchd service."
        echo "You can manage it with: launchctl [load|unload] ~/Library/LaunchAgents/io.gitea.web.plist"
    else
        echo "Failed to start Gitea via launchd. Trying to run it directly..."
        cd "$GITEA_HOME_DIR"
        ./gitea web -c "$CONFIG_DIR/app.ini" &
        echo "Gitea started in background."
    fi
fi

echo
echo "==== Native Deployment Complete ===="
echo

# Display deployment information
if [ "$deployment_type" = "1" ]; then
    echo "Your Gitea instance should now be available at: http://$DOMAIN:3000"
elif [ "$deployment_type" = "2" ]; then
    echo "Your Gitea instance should now be available at: https://localhost"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."
elif [ "$deployment_type" = "4" ]; then
    echo "Your Gitea instance should now be available at: https://$SERVER_IP"
    echo "Note: Since this uses an IP address with a self-signed certificate, you will need to accept the security warning in your browser."
else
    echo "Your Gitea instance should now be available at: https://$DOMAIN"
    echo "Note: You'll need to configure your DNS to point to your server's IP address"
fi

echo
echo "To complete the installation, visit your Gitea URL and follow the web installer"
echo "Use these database settings:"
echo "  - Database Type: PostgreSQL"
echo "  - Database Host: 127.0.0.1:5432"
echo "  - Database Name: $POSTGRES_DB"
echo "  - Database User: $POSTGRES_USER"
echo "  - Database Password: $POSTGRES_PASSWORD"
echo
echo "Enjoy your personal Git service!"

# Check and configure firewall settings
configure_firewall() {
    echo "Checking and configuring firewall settings..."
    if [ "$OS" = "Linux" ]; then
        # Check for common firewall tools
        if command -v ufw &> /dev/null; then
            echo "UFW firewall detected."
            
            # Configure UFW based on deployment type
            if [ "$deployment_type" = "1" ]; then
                # HTTP deployment
                sudo ufw allow 3000/tcp comment "Gitea HTTP"
                sudo ufw allow 2222/tcp comment "Gitea SSH"
                echo "Firewall configured to allow ports 3000 (HTTP) and 2222 (SSH)."
            else
                # HTTPS deployment
                sudo ufw allow 443/tcp comment "Gitea HTTPS"
                sudo ufw allow 80/tcp comment "HTTP for Let's Encrypt"
                sudo ufw allow 2222/tcp comment "Gitea SSH"
                echo "Firewall configured to allow ports 443 (HTTPS), 80 (HTTP), and 2222 (SSH)."
            fi
            
            # Make sure UFW is enabled
            if ! sudo ufw status | grep -q "active"; then
                echo "UFW is not active. Do you want to enable it? (y/n)"
                read -p "Warning: Ensure SSH access is allowed before enabling: " enable_ufw
                if [[ "$enable_ufw" == "y" || "$enable_ufw" == "Y" ]]; then
                    sudo ufw allow ssh
                    sudo ufw --force enable
                    echo "UFW enabled with SSH access preserved."
                fi
            fi
            
        elif command -v firewall-cmd &> /dev/null; then
            echo "FirewallD detected."
            
            # Configure FirewallD based on deployment type
            if [ "$deployment_type" = "1" ]; then
                # HTTP deployment
                sudo firewall-cmd --permanent --add-port=3000/tcp
                sudo firewall-cmd --permanent --add-port=2222/tcp
                sudo firewall-cmd --reload
                echo "Firewall configured to allow ports 3000 (HTTP) and 2222 (SSH)."
            else
                # HTTPS deployment
                sudo firewall-cmd --permanent --add-port=443/tcp
                sudo firewall-cmd --permanent --add-port=80/tcp
                sudo firewall-cmd --permanent --add-port=2222/tcp
                sudo firewall-cmd --reload
                echo "Firewall configured to allow ports 443 (HTTPS), 80 (HTTP), and 2222 (SSH)."
            fi
            
        elif command -v iptables &> /dev/null; then
            echo "iptables detected."
            echo "Would you like to configure iptables rules? (y/n)"
            read -p "This may overwrite existing rules: " configure_iptables
            
            if [[ "$configure_iptables" == "y" || "$configure_iptables" == "Y" ]]; then
                if [ "$deployment_type" = "1" ]; then
                    # HTTP deployment
                    sudo iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
                    sudo iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
                    echo "iptables configured to allow ports 3000 (HTTP) and 2222 (SSH)."
                else
                    # HTTPS deployment
                    sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
                    sudo iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
                    echo "iptables configured to allow ports 443 (HTTPS), 80 (HTTP), and 2222 (SSH)."
                fi
                
                # Save iptables rules if possible
                if command -v netfilter-persistent &> /dev/null; then
                    sudo netfilter-persistent save
                elif [ -d "/etc/iptables" ]; then
                    sudo sh -c "iptables-save > /etc/iptables/rules.v4"
                fi
            fi
        else
            echo "No recognized firewall tool found (ufw, firewall-cmd, iptables)."
            echo "Please configure your firewall manually to allow the following ports:"
            if [ "$deployment_type" = "1" ]; then
                echo "- Port 3000 (TCP): Gitea HTTP web interface"
                echo "- Port 2222 (TCP): Gitea SSH"
            else
                echo "- Port 443 (TCP): Gitea HTTPS web interface"
                echo "- Port 80 (TCP): HTTP (for Let's Encrypt)"
                echo "- Port 2222 (TCP): Gitea SSH"
            fi
        fi
    elif [ "$OS" = "Darwin" ]; then
        echo "On macOS, please configure the firewall using System Preferences."
        echo "Ensure the following ports are open:"
        if [ "$deployment_type" = "1" ]; then
            echo "- Port 3000 (TCP): Gitea HTTP web interface"
            echo "- Port 2222 (TCP): Gitea SSH"
        else
            echo "- Port 443 (TCP): Gitea HTTPS web interface"
            echo "- Port 80 (TCP): HTTP (for Let's Encrypt)"
            echo "- Port 2222 (TCP): Gitea SSH"
        fi
    fi
}

# Run firewall configuration after service is started
configure_firewall

echo
echo "==== Native Deployment Complete ===="
echo

# Display deployment information
if [ "$deployment_type" = "1" ]; then
    echo "Your Gitea instance should now be available at: http://$DOMAIN:3000"
elif [ "$deployment_type" = "2" ]; then
    echo "Your Gitea instance should now be available at: https://localhost"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."
elif [ "$deployment_type" = "4" ]; then
    echo "Your Gitea instance should now be available at: https://$SERVER_IP"
    echo "Note: Since this uses an IP address with a self-signed certificate, you will need to accept the security warning in your browser."
else
    echo "Your Gitea instance should now be available at: https://$DOMAIN"
    echo "Note: You'll need to configure your DNS to point to your server's IP address"
fi

echo
echo "To complete the installation, visit your Gitea URL and follow the web installer"
echo "Use these database settings:"
echo "  - Database Type: PostgreSQL"
echo "  - Database Host: 127.0.0.1:5432"
echo "  - Database Name: $POSTGRES_DB"
echo "  - Database User: $POSTGRES_USER"
echo "  - Database Password: $POSTGRES_PASSWORD"
echo
echo "Enjoy your personal Git service!" 
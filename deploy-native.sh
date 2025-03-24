#!/bin/bash

# GiteaSecureLaunch - Native Deployment Script (Without Docker)
set -e

echo "==== GiteaSecureLaunch Native Deployment Script ===="
echo "This script will install Gitea directly on your system without Docker"
echo

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
GITEA_VERSION=$(curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "Latest Gitea version: $GITEA_VERSION"

# Create a temporary directory for downloads
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Download the appropriate binary
if [ "$OS" = "Linux" ]; then
    GITEA_URL="https://dl.gitea.io/gitea/$GITEA_VERSION/gitea-$GITEA_VERSION-linux-$ARCH"
elif [ "$OS" = "Darwin" ]; then
    GITEA_URL="https://dl.gitea.io/gitea/$GITEA_VERSION/gitea-$GITEA_VERSION-darwin-$ARCH"
fi

echo "Downloading from: $GITEA_URL"
curl -L -o gitea "$GITEA_URL"
chmod +x gitea

# Move Gitea to installation directory
mv gitea "$GITEA_HOME_DIR/"
cd - > /dev/null

# Create systemd service file (Linux only)
if [ "$OS" = "Linux" ]; then
    echo "Creating systemd service file..."
    cat > /tmp/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=$(whoami)
Type=simple
WorkingDirectory=$GITEA_HOME_DIR
ExecStart=$GITEA_HOME_DIR/gitea web -c $CONFIG_DIR/app.ini
Restart=always
Environment=USER=$(whoami) HOME=$HOME GITEA_WORK_DIR=$WORK_DIR

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
    # Start using systemd
    sudo systemctl enable gitea
    sudo systemctl start gitea
    
    echo "Gitea is now running as a system service."
    echo "You can manage it with: sudo systemctl [start|stop|restart|status] gitea"
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

    launchctl load ~/Library/LaunchAgents/io.gitea.web.plist
    
    echo "Gitea is now running as a launchd service."
    echo "You can manage it with: launchctl [load|unload] ~/Library/LaunchAgents/io.gitea.web.plist"
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
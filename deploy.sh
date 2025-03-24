#!/bin/bash

# Gitea Automated Deployment Script
set -e

echo "==== Gitea Deployment Script ===="
echo

# Check if Docker and Docker Compose are installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create required directories
echo "Creating necessary directories..."
mkdir -p gitea_data postgres_data certs

# Load environment variables
if [ -f .env ]; then
    source .env
    echo "Loaded configuration from .env file."
else
    echo "Error: .env file not found!"
    exit 1
fi

# Ask user to confirm or update domain settings
read -p "Domain for Gitea [$DOMAIN]: " input_domain
DOMAIN=${input_domain:-$DOMAIN}
sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env

# Determine if this is a local development or production deployment
echo
echo "Deployment Type:"
echo "1) Local development (HTTP, port 3000)"
echo "2) Production server (HTTPS, port 443)"
read -p "Select deployment type [1/2]: " deployment_type

# Create a backup of docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak

if [ "$deployment_type" = "1" ]; then
    echo "Configuring for local development (HTTP)..."
    
    # Update docker-compose.yml for HTTP
    sed -i 's/GITEA__server__PROTOCOL=https/GITEA__server__PROTOCOL=http/g' docker-compose.yml
    sed -i 's|GITEA__server__ROOT_URL=https://|GITEA__server__ROOT_URL=http://|g' docker-compose.yml
    sed -i 's|ROOT_URL=https://\${DOMAIN}/|ROOT_URL=http://\${DOMAIN}:3000/|g' docker-compose.yml
    
    # Remove HTTPS-specific environment variables
    sed -i '/GITEA__server__CERT_FILE/d' docker-compose.yml
    sed -i '/GITEA__server__KEY_FILE/d' docker-compose.yml
    
    # Update port mapping
    sed -i 's/"443:3000"/"3000:3000"/g' docker-compose.yml
    
    # Ask if user wants to modify hosts file for local testing
    read -p "Would you like to add an entry to /etc/hosts for local testing? [Y/n]: " add_hosts
    if [[ "$add_hosts" != "n" && "$add_hosts" != "N" ]]; then
        echo "Adding entry to /etc/hosts file..."
        echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
        echo "Entry added: 127.0.0.1 $DOMAIN"
    fi
    
    echo "Local development configuration complete!"
    echo "Your Gitea instance will be available at: http://$DOMAIN:3000"
    
else
    echo "Configuring for production deployment (HTTPS)..."
    
    # Update docker-compose.yml for HTTPS
    sed -i 's/GITEA__server__PROTOCOL=http/GITEA__server__PROTOCOL=https/g' docker-compose.yml
    sed -i 's|GITEA__server__ROOT_URL=http://|GITEA__server__ROOT_URL=https://|g' docker-compose.yml
    sed -i 's|ROOT_URL=http://\${DOMAIN}:3000/|ROOT_URL=https://\${DOMAIN}/|g' docker-compose.yml
    
    # Add HTTPS-specific environment variables if they don't exist
    if ! grep -q "GITEA__server__CERT_FILE" docker-compose.yml; then
        sed -i '/GITEA__server__PROTOCOL=https/a\      - GITEA__server__CERT_FILE=/data/gitea/cert/cert.pem\n      - GITEA__server__KEY_FILE=/data/gitea/cert/key.pem' docker-compose.yml
    fi
    
    # Update port mapping
    sed -i 's/"3000:3000"/"443:3000"/g' docker-compose.yml
    
    # Generate self-signed certificates
    echo "Generating SSL certificates for $DOMAIN..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout certs/key.pem -out certs/cert.pem \
        -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN,DNS:www.$DOMAIN,IP:127.0.0.1"
    
    # Fix certificates permissions
    chmod 600 certs/key.pem
    chmod 644 certs/cert.pem
    
    echo "Certificates generated successfully."
    echo "Your Gitea instance will be available at: https://$DOMAIN"
    
    # Ask about Let's Encrypt
    read -p "Would you like to set up Let's Encrypt certificates now? [y/N]: " setup_letsencrypt
    if [[ "$setup_letsencrypt" = "y" || "$setup_letsencrypt" = "Y" ]]; then
        echo "Setting up Let's Encrypt..."
        ./configure.sh # The configure.sh script already has Let's Encrypt setup option
    fi
fi

# Ensure the right volumes are in place
if grep -q "GITEA__server__PROTOCOL=https" docker-compose.yml; then
    # Ensure certs volume is mounted
    if ! grep -q "./certs:/data/gitea/cert" docker-compose.yml; then
        sed -i '/volumes:/a\      - ./certs:/data/gitea/cert' docker-compose.yml
    fi
else
    # Remove certs volume if not needed
    sed -i '/\.\/certs:\/data\/gitea\/cert/d' docker-compose.yml
fi

# Pull latest Docker images
echo "Pulling latest Docker images..."
docker compose pull

# Start the containers
echo "Starting Gitea and PostgreSQL services..."
docker compose up -d

echo
echo "==== Deployment Complete ===="
echo

if [ "$deployment_type" = "1" ]; then
    echo "Your local Gitea instance should now be available at: http://$DOMAIN:3000"
else
    echo "Your production Gitea instance should now be available at: https://$DOMAIN"
    echo "Note: You'll need to configure your DNS to point to your server's IP address"
fi

echo
echo "For first-time setup, visit the installation page and configure with these settings:"
echo "  - Database Type: PostgreSQL"
echo "  - Database Host: db:5432"
echo "  - Database Name: $POSTGRES_DB"
echo "  - Database User: $POSTGRES_USER"
echo "  - Database Password: $POSTGRES_PASSWORD"
echo 
echo "You can customize other settings as needed during installation."
echo "Enjoy your personal Git service!" 
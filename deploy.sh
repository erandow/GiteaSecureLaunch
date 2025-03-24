#!/bin/bash

# GiteaSecureLaunch - Automated Gitea Deployment Script
set -e

echo "==== GiteaSecureLaunch Deployment Script ===="
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

# Determine if this is a local development or production deployment
echo
echo "Deployment Type:"
echo "1) Local development (HTTP, port 3000)"
echo "2) Local HTTPS with localhost (HTTPS, port 443)"
echo "3) Production server with domain name (HTTPS, port 443)"
echo "4) Production server with IP address (HTTPS, port 443)"
read -p "Select deployment type [1/2/3/4]: " deployment_type

# Create a symlink to the appropriate docker-compose file
if [ "$deployment_type" = "1" ]; then
    echo "Configuring for local development (HTTP)..."
    
    # Set domain to localhost if not specified
    read -p "Domain for Gitea [$DOMAIN] (or leave empty for 'localhost'): " input_domain
    DOMAIN=${input_domain:-${DOMAIN:-localhost}}
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    
    # Ask if user wants to modify hosts file if not using localhost
    if [ "$DOMAIN" != "localhost" ]; then
        read -p "Would you like to add an entry to /etc/hosts for local testing? [Y/n]: " add_hosts
        if [[ "$add_hosts" != "n" && "$add_hosts" != "N" ]]; then
            echo "Adding entry to /etc/hosts file..."
            echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
            echo "Entry added: 127.0.0.1 $DOMAIN"
        fi
    fi
    
    # Use the local development docker-compose file
    ln -sf docker-compose.local.yml docker-compose.yml
    
    echo "Local development configuration complete!"
    echo "Your Gitea instance will be available at: http://$DOMAIN:3000"

elif [ "$deployment_type" = "2" ]; then
    echo "Configuring for local HTTPS with localhost..."
    
    # Set domain to localhost
    DOMAIN="localhost"
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    
    # Generate self-signed certificates for localhost
    echo "Generating SSL certificates for localhost..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout certs/key.pem -out certs/cert.pem \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    
    # Fix certificates permissions
    chmod 600 certs/key.pem
    chmod 644 certs/cert.pem
    
    # Use the localhost HTTPS docker-compose file
    ln -sf docker-compose.localhost-https.yml docker-compose.yml
    
    echo "Certificates generated successfully."
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
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    
    # Generate self-signed certificates for IP address
    echo "Generating SSL certificates for IP address $SERVER_IP..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout certs/key.pem -out certs/cert.pem \
        -subj "/CN=$SERVER_IP" \
        -addext "subjectAltName=IP:$SERVER_IP"
    
    # Fix certificates permissions
    chmod 600 certs/key.pem
    chmod 644 certs/cert.pem
    
    # Use the IP address docker-compose file
    ln -sf docker-compose.ip.yml docker-compose.yml
    
    echo "Your Gitea instance will be available at: https://$SERVER_IP"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."

elif [ "$deployment_type" = "3" ]; then
    echo "Configuring for production deployment (HTTPS) with domain name..."
    
    # Get domain name
    read -p "Enter your domain name (e.g., git.example.com): " DOMAIN_NAME
    
    # Set domain
    DOMAIN="$DOMAIN_NAME"
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    
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
            -keyout certs/key.pem -out certs/cert.pem \
            -subj "/CN=$DOMAIN" \
            -addext "subjectAltName=DNS:$DOMAIN"
        
        # Fix certificates permissions
        chmod 600 certs/key.pem
        chmod 644 certs/cert.pem
        
        echo "Self-signed certificates generated successfully."
        echo "Note: You will need to accept the self-signed certificate warning in your browser."
    else
        # We'll use Let's Encrypt, which requires further setup
        echo "Let's Encrypt setup requires domain to be properly configured to point to this server."
        echo "Please make sure your domain $DOMAIN points to this server before continuing."
        read -p "Press Enter to continue or Ctrl+C to abort..."
        
        # Check if certbot is installed
        if ! command -v certbot &> /dev/null; then
            echo "Installing Certbot..."
            apt-get update
            apt-get install -y certbot
        fi
        
        # Get certificates using certbot standalone mode
        echo "Obtaining Let's Encrypt certificates..."
        certbot certonly --standalone --agree-tos --email admin@$DOMAIN -d $DOMAIN
        
        # Copy certificates to the right location
        cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem certs/cert.pem
        cp /etc/letsencrypt/live/$DOMAIN/privkey.pem certs/key.pem
        
        # Fix permissions
        chmod 644 certs/cert.pem
        chmod 600 certs/key.pem
        
        echo "Let's Encrypt certificates obtained successfully."
        
        # Set up auto-renewal
        echo "Setting up certificate auto-renewal..."
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /home/$(whoami)/Project/gitea-deployment/certs/cert.pem && cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /home/$(whoami)/Project/gitea-deployment/certs/key.pem && chmod 644 /home/$(whoami)/Project/gitea-deployment/certs/cert.pem && chmod 600 /home/$(whoami)/Project/gitea-deployment/certs/key.pem && docker compose restart gitea\"") | crontab -
        
        echo "Certificate auto-renewal configured."
    fi
    
    # Use the domain docker-compose file
    ln -sf docker-compose.domain.yml docker-compose.yml
    
    echo "Your Gitea instance will be available at: https://$DOMAIN"
fi

# Remove the checks to adjust volumes since we now use dedicated files
# that already have the correct volume mounts

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
elif [ "$deployment_type" = "2" ]; then
    echo "Your local Gitea instance should now be available at: https://localhost"
    echo "Note: You will need to accept the self-signed certificate warning in your browser."
elif [ "$deployment_type" = "4" ]; then
    echo "Your production Gitea instance should now be available at: https://$SERVER_IP"
    echo "Note: Since this uses an IP address with a self-signed certificate, you will need to accept the security warning in your browser."
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
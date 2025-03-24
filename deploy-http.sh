#!/bin/bash

# GiteaSecureLaunch - HTTP Deployment Script
set -e

echo "==== GiteaSecureLaunch HTTP Deployment Script ===="
echo "This script will install Gitea with Docker using HTTP (no SSL)"
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
mkdir -p gitea_data postgres_data

# Check for .env file and create if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file with default values..."
    cat > .env << EOF
POSTGRES_DB=gitea
POSTGRES_USER=gitea
POSTGRES_PASSWORD=gitea
DOMAIN=localhost
APP_NAME=Gitea
EOF
    echo ".env file created with default values."
else
    echo "Using existing .env file."
fi

# Source the .env file
source .env

# Ask for domain
read -p "Domain for Gitea [$DOMAIN] (or leave empty for 'localhost'): " input_domain
DOMAIN=${input_domain:-${DOMAIN:-localhost}}

# Update .env file with new domain if changed
if [ "$DOMAIN" != "$(grep DOMAIN= .env | cut -d= -f2)" ]; then
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env || {
        # For macOS compatibility
        sed -i '' "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    }
    echo "Updated DOMAIN in .env file: $DOMAIN"
fi

# Add hosts entry if domain is not localhost
if [ "$DOMAIN" != "localhost" ]; then
    read -p "Would you like to add an entry to /etc/hosts for local testing? [Y/n]: " add_hosts
    if [[ "$add_hosts" != "n" && "$add_hosts" != "N" ]]; then
        echo "Adding entry to /etc/hosts file..."
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            sudo bash -c "echo '127.0.0.1 $DOMAIN' >> /etc/hosts"
        else
            # Linux and other Unix-like systems
            echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
        fi
        echo "Entry added: 127.0.0.1 $DOMAIN"
    fi
fi

# Pull latest Docker images
echo "Pulling latest Docker images..."
docker compose -f docker-compose-http.yml pull

# Start the containers
echo "Starting Gitea and PostgreSQL services..."
docker compose -f docker-compose-http.yml down 2>/dev/null || true
docker compose -f docker-compose-http.yml up -d

echo
echo "==== HTTP Deployment Complete ===="
echo
echo "Your Gitea instance should now be available at: http://$DOMAIN:3000"
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
#!/bin/bash

# Gitea Post-Installation Configuration Script
set -e

echo "==== Gitea Post-Installation Configuration ===="
echo

# Check if Gitea is running
if ! docker compose ps gitea | grep -q "Up"; then
    echo "Error: Gitea container is not running. Please run deploy.sh first."
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    source .env
    echo "Loaded configuration from .env file."
else
    echo "Error: .env file not found!"
    exit 1
fi

echo "This script will help you configure additional settings for your Gitea instance."
echo

# Check if using IP address instead of domain name
IS_IP_BASED=false
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_IP_BASED=true
fi

# Configuration options
echo "Select an option to configure:"
echo "1) Regenerate SSL certificates"
if [ "$IS_IP_BASED" = false ]; then
    echo "2) Use Let's Encrypt certificates instead of self-signed"
fi
echo "3) Configure email sending"
echo "4) Enable/disable registration"
echo "5) Restart Gitea service"
echo "6) Display Gitea logs"
echo "7) Exit"
echo

read -p "Enter your choice [1-7]: " choice

case $choice in
    1)
        echo "Regenerating SSL certificates..."
        
        if [ "$IS_IP_BASED" = true ]; then
            echo "Generating new SSL certificates for IP address $DOMAIN..."
            openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
                -keyout certs/key.pem -out certs/cert.pem \
                -subj "/CN=$DOMAIN" \
                -addext "subjectAltName=IP:$DOMAIN"
        else
            read -p "Confirm your domain ($DOMAIN) [Y/n]: " confirm_domain
            
            if [[ "$confirm_domain" != "n" && "$confirm_domain" != "N" ]]; then
                echo "Generating new SSL certificates for $DOMAIN..."
                openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
                    -keyout certs/key.pem -out certs/cert.pem \
                    -subj "/CN=$DOMAIN" \
                    -addext "subjectAltName=DNS:$DOMAIN,DNS:www.$DOMAIN,IP:127.0.0.1"
            else
                echo "Operation cancelled."
                exit 1
            fi
        fi
        
        # Fix certificates permissions
        chmod 600 certs/key.pem
        chmod 644 certs/cert.pem
        
        echo "Restarting Gitea to use the new certificates..."
        docker compose restart gitea
        
        echo "SSL certificates regenerated successfully!"
        ;;
        
    2)
        if [ "$IS_IP_BASED" = true ]; then
            echo "Let's Encrypt is not available for IP address-based deployments."
            echo "Let's Encrypt requires a domain name for validation."
            exit 1
        fi
        
        echo "Setting up Let's Encrypt certificates..."
        echo "Note: This requires a publicly accessible domain with proper DNS configuration."
        read -p "Confirm your domain ($DOMAIN) [Y/n]: " confirm_domain
        
        if [[ "$confirm_domain" != "n" && "$confirm_domain" != "N" ]]; then
            # Create a backup of the docker-compose.yml file
            cp docker-compose.yml docker-compose.yml.bak
            
            # Add certbot service to docker-compose.yml
            cat <<EOT >> docker-compose.yml

  certbot:
    image: certbot/certbot
    container_name: gitea-certbot
    volumes:
      - ./certs:/etc/letsencrypt
      - ./certbot-webroot:/var/www/certbot
    command: certonly --webroot --webroot-path=/var/www/certbot --email $ADMIN_EMAIL --agree-tos --no-eff-email -d $DOMAIN
EOT
            
            # Create directory for certbot webroot
            mkdir -p certbot-webroot
            
            echo "Running certbot to obtain certificates..."
            docker compose up certbot
            
            # Copy certificates to the correct location
            cp certs/live/$DOMAIN/fullchain.pem certs/cert.pem
            cp certs/live/$DOMAIN/privkey.pem certs/key.pem
            
            # Set proper permissions
            chmod 644 certs/cert.pem
            chmod 600 certs/key.pem
            
            echo "Restarting Gitea to use the new certificates..."
            docker compose restart gitea
            
            echo "Let's Encrypt certificates installed successfully!"
        else
            echo "Operation cancelled."
        fi
        ;;
        
    3)
        echo "Configuring email sending..."
        read -p "SMTP Server: " smtp_server
        read -p "SMTP Port: " smtp_port
        read -p "SMTP Username: " smtp_user
        read -s -p "SMTP Password: " smtp_password
        echo
        read -p "From Email Address: " from_email
        
        # Update gitea app.ini file to include SMTP settings
        docker exec gitea bash -c "cat >> /data/gitea/conf/app.ini << EOT

[mailer]
ENABLED = true
HOST = $smtp_server:$smtp_port
FROM = $from_email
USER = $smtp_user
PASSWD = $smtp_password
EOT"

        echo "Email configuration saved. Restarting Gitea..."
        docker compose restart gitea
        ;;
        
    4)
        echo "Configure registration settings:"
        echo "1) Disable registrations (private instance)"
        echo "2) Enable registrations for everyone"
        echo "3) Enable registrations with email confirmation"
        read -p "Select option [1-3]: " reg_option
        
        case $reg_option in
            1)
                setting="DISABLE_REGISTRATION = true"
                ;;
            2)
                setting="DISABLE_REGISTRATION = false"
                ;;
            3)
                setting="DISABLE_REGISTRATION = false
REGISTER_EMAIL_CONFIRM = true"
                ;;
            *)
                echo "Invalid option. No changes made."
                exit 1
                ;;
        esac
        
        # Update gitea app.ini file
        docker exec gitea bash -c "sed -i '/\[service\]/,/^\[/ s/DISABLE_REGISTRATION.*//' /data/gitea/conf/app.ini"
        docker exec gitea bash -c "sed -i '/\[service\]/,/^\[/ s/REGISTER_EMAIL_CONFIRM.*//' /data/gitea/conf/app.ini"
        docker exec gitea bash -c "cat >> /data/gitea/conf/app.ini << EOT
[service]
$setting
EOT"

        echo "Registration settings updated. Restarting Gitea..."
        docker compose restart gitea
        ;;
        
    5)
        echo "Restarting Gitea service..."
        docker compose restart gitea
        echo "Gitea service has been restarted."
        ;;
        
    6)
        echo "Displaying Gitea logs (press Ctrl+C to exit):"
        docker compose logs -f gitea
        ;;
        
    7)
        echo "Exiting configuration script."
        exit 0
        ;;
        
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac

echo
echo "Configuration complete!" 
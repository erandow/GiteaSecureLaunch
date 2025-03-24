#!/bin/bash

# Gitea Backup and Restore Script
set -e

BACKUP_DIR="./backups"
DATE_FORMAT=$(date +%Y%m%d-%H%M%S)

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "==== Gitea Backup and Restore Utility ===="
echo

# Menu
echo "Select an option:"
echo "1) Create a new backup"
echo "2) List available backups"
echo "3) Restore from backup"
echo "4) Exit"
echo

read -p "Enter your choice [1-4]: " choice

case $choice in
    1)
        echo "Creating backup..."
        
        # Stop containers for consistent backup
        echo "Stopping Gitea services..."
        docker compose down
        
        # Create backup archive
        BACKUP_FILE="$BACKUP_DIR/gitea-backup-$DATE_FORMAT.tar.gz"
        echo "Archiving data to $BACKUP_FILE..."
        tar -czf "$BACKUP_FILE" \
            gitea_data postgres_data .env docker-compose.yml \
            certs configure.sh deploy.sh README.md
        
        # Restart containers
        echo "Restarting Gitea services..."
        docker compose up -d
        
        echo "Backup completed successfully!"
        echo "Backup saved to: $BACKUP_FILE"
        ;;
        
    2)
        echo "Available backups:"
        
        if [ "$(ls -A $BACKUP_DIR)" ]; then
            ls -lh "$BACKUP_DIR" | grep -v "^total" | awk '{print NR ") " $9 " (" $5 ")"}'
        else
            echo "No backups available."
        fi
        ;;
        
    3)
        echo "Available backups for restoration:"
        
        if [ ! "$(ls -A $BACKUP_DIR)" ]; then
            echo "No backups available for restoration."
            exit 1
        fi
        
        # List backups with numbers
        ls -t "$BACKUP_DIR" | grep -v "^total" | cat -n
        
        # Get total number of backups
        TOTAL_BACKUPS=$(ls -1 "$BACKUP_DIR" | wc -l)
        
        # Ask which backup to restore
        read -p "Enter the number of the backup to restore [1-$TOTAL_BACKUPS]: " backup_number
        
        if ! [[ "$backup_number" =~ ^[0-9]+$ ]] || [ "$backup_number" -lt 1 ] || [ "$backup_number" -gt "$TOTAL_BACKUPS" ]; then
            echo "Invalid backup number."
            exit 1
        fi
        
        # Get the selected backup filename
        SELECTED_BACKUP=$(ls -t "$BACKUP_DIR" | sed -n "${backup_number}p")
        BACKUP_PATH="$BACKUP_DIR/$SELECTED_BACKUP"
        
        echo "You are about to restore from: $SELECTED_BACKUP"
        echo "WARNING: This will OVERWRITE all current data!"
        read -p "Are you sure you want to continue? [y/N]: " confirm
        
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Restoration cancelled."
            exit 0
        fi
        
        # Stop containers
        echo "Stopping Gitea services..."
        docker compose down
        
        # Backup current data (just in case)
        EMERGENCY_BACKUP="$BACKUP_DIR/pre-restore-backup-$DATE_FORMAT.tar.gz"
        echo "Creating emergency backup of current data to $EMERGENCY_BACKUP..."
        tar -czf "$EMERGENCY_BACKUP" \
            gitea_data postgres_data .env docker-compose.yml \
            certs configure.sh deploy.sh README.md 2>/dev/null || true
        
        # Remove current data
        echo "Removing current data..."
        rm -rf gitea_data postgres_data
        
        # Restore from backup
        echo "Restoring from backup: $BACKUP_PATH"
        tar -xzf "$BACKUP_PATH"
        
        # Start containers
        echo "Starting Gitea services..."
        docker compose up -d
        
        echo "Restoration completed successfully!"
        ;;
        
    4)
        echo "Exiting backup utility."
        exit 0
        ;;
        
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac 
# Gitea Self-Hosted Deployment

This project provides an automated way to deploy a personal Gitea Git service with Docker, HTTPS, and PostgreSQL.

## Features

- Gitea Git server deployment using Docker
- Support for both local development (HTTP) and production (HTTPS) environments
- PostgreSQL database for persistent data storage
- SSH access for Git operations
- Automated setup script with environment detection
- Let's Encrypt integration for production deployments

## Prerequisites

- A Linux server (physical or virtual) with public IP address (for production)
- Docker and Docker Compose installed
- Domain name pointing to your server (or local hosts file modified for testing)
- Basic knowledge of Linux command line
- Open ports: 443 (HTTPS) or 3000 (HTTP) and 2222 (SSH)

## Installation

1. Clone this repository:

```bash
git clone https://github.com/yourusername/gitea-deployment.git
cd gitea-deployment
```

2. Edit the `.env` file to customize your configuration:

```bash
nano .env
```

Modify the following settings:

- `DOMAIN`: Your Gitea domain (e.g., git.example.com)
- `POSTGRES_*`: Database credentials
- `APP_NAME`: Name of your Gitea instance
- `ADMIN_*`: Initial admin credentials

3. Run the deployment script:

```bash
./deploy.sh
```

4. Choose your deployment type:
   - **Local development**: Uses HTTP on port 3000, ideal for testing
   - **Production server**: Uses HTTPS on port 443 with SSL certificates

The script will automatically configure Gitea based on your selection:

**For local development:**

- Configure HTTP protocol
- Expose port 3000
- Optionally add an entry to your hosts file
- Skip SSL certificate generation

**For production:**

- Configure HTTPS protocol
- Generate SSL certificates or use Let's Encrypt
- Expose port 443
- Configure secure settings

## Post-Installation

After running the script, visit your Gitea URL to complete the setup:

1. The database settings should be pre-filled from your environment variables
2. Configure the site title, repository root path, and other settings as desired
3. Complete the installation

## Directory Structure

- `gitea_data/`: Contains all Gitea data
- `postgres_data/`: Contains PostgreSQL database files
- `certs/`: Contains SSL certificates for HTTPS (production mode only)

## Maintenance

### Updating Gitea

To update to the latest version of Gitea:

```bash
docker compose pull
docker compose up -d
```

### Backup

To backup your Gitea instance:

1. Use the included backup utility:

   ```bash
   ./backup.sh
   ```

2. Select option 1 to create a new backup.

### Additional Configuration

For additional configuration options:

```bash
./configure.sh
```

This provides options for:

- Using Let's Encrypt certificates
- Configuring email sending
- Managing user registration settings
- And more

## Switching Between Environments

If you need to switch between local development and production environments:

1. Simply run the deployment script again:

   ```bash
   ./deploy.sh
   ```

2. Choose the desired environment type when prompted.

## Troubleshooting

### Cannot access Gitea website

- For local development:

  - Ensure your domain is in your hosts file: `127.0.0.1 yourdomain`
  - Check that port 3000 is not in use by another application

- For production:
  - Ensure your domain points to your server's IP address
  - Check that ports 443 and 2222 are open in your firewall
  - Inspect container logs: `docker compose logs gitea`

### Database connection issues

- Check the PostgreSQL container is running: `docker compose ps`
- Inspect the database logs: `docker compose logs db`

## Security Considerations

- Change default passwords in the `.env` file
- Use Let's Encrypt certificates for production
- Consider setting up a reverse proxy (like Nginx) for additional security
- Regularly update your Docker images

## License

This project is MIT licensed.

## Need Help?

If you encounter any issues or have questions, please open an issue in the GitHub repository.
# GiteaSecureLaunch

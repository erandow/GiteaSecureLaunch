# GiteaSecureLaunch

A streamlined solution for deploying Gitea with automated HTTPS configuration. No domain name required!

This project provides an easy, automated way to deploy a personal Gitea Git service with Docker, secure HTTPS, and PostgreSQL database. Set up in minutes with a simple deployment script.

## Features

- Gitea Git server deployment using Docker
- Flexible deployment options:
  - Local HTTP for basic testing
  - Local HTTPS with localhost (no domain required)
  - Production HTTPS with custom domain (optional)
  - Production HTTPS with IP address (no domain required)
- PostgreSQL database for persistent data storage
- SSH access for Git operations
- Automated setup script with environment detection
- Let's Encrypt integration for production deployments with domains

## Prerequisites

- A Linux server (physical or virtual)
- Docker and Docker Compose installed
- Basic knowledge of Linux command line
- For domain-based deployment: Domain name (optional)
- Open ports: 3000 (HTTP) or 443 (HTTPS) and 2222 (SSH)

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

- `POSTGRES_*`: Database credentials
- `APP_NAME`: Name of your Gitea instance
- `ADMIN_*`: Initial admin credentials

3. Run the deployment script:

```bash
./deploy.sh
```

4. Choose your deployment type:
   - **Local development (HTTP)**: Simple HTTP on port 3000
   - **Local HTTPS with localhost**: Secure HTTPS on port 443 (no domain required)
   - **Production server with domain**: HTTPS on port 443 with custom domain
   - **Production server with IP**: HTTPS on port 443 using server IP (no domain required)

The script will automatically configure Gitea based on your selection.

## Deployment Options

This deployment supports multiple configurations which are managed through separate Docker Compose files:

1. **Local Development (HTTP)** - Uses `docker-compose.local.yml`

   - Accessible via HTTP on port 3000
   - Suitable for local development environments
   - No SSL certificates required

2. **Local HTTPS with Localhost** - Uses `docker-compose.localhost-https.yml`

   - Accessible via HTTPS on port 443
   - Uses self-signed certificates for localhost
   - Suitable for testing HTTPS functionality locally

3. **Production with Domain Name** - Uses `docker-compose.domain.yml`

   - Accessible via HTTPS on port 443
   - Supports both self-signed certificates and Let's Encrypt
   - Proper domain name required
   - Includes HTTP to HTTPS redirection

4. **Production with IP Address** - Uses `docker-compose.ip.yml`
   - Accessible via HTTPS on port 443
   - Uses self-signed certificates for IP address
   - Suitable for servers without domain names

### How it Works

When you run the `deploy.sh` script, you'll be prompted to select a deployment type. Based on your selection, the script will:

1. Update the `.env` file with appropriate values
2. Generate SSL certificates if needed
3. Create a symbolic link from the appropriate docker-compose file to `docker-compose.yml`
4. Start the containers using the selected configuration

This approach keeps the configuration for each deployment scenario separate and avoids the need to modify configuration files with sed commands.

## Post-Installation

After running the script, visit your Gitea URL to complete the setup:

- Local HTTP: http://localhost:3000 or http://your-local-domain:3000
- Local HTTPS: https://localhost
- Production with domain: https://your-domain.com
- Production with IP: https://your-server-ip

The database settings will be pre-filled from your environment variables.

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

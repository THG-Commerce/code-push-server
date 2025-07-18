# CodePush Server - GCP Terraform Deployment

This Terraform configuration deploys the CodePush Server to Google Cloud Platform using VM-based deployment.

## Architecture

- **Compute Engine VM**: Hosts the containerized CodePush server application
- **Redis**: Local Redis server running on the VM for caching and session storage
- **Nginx**: Reverse proxy with SSL termination via Let's Encrypt
- **VPC**: Private network with firewall rules for security
- **Cloud Storage**: Backend storage for CodePush packages
- **Cloud Build**: Automated CI/CD pipeline with GitHub integration (optional)
- **Fastly CDN**: Global content delivery network for performance (optional)

## Prerequisites

1. **GCP Project**: You need a GCP project with billing enabled
2. **Terraform**: Install Terraform >= 1.0
3. **gcloud CLI**: Install and authenticate with your GCP account
4. **Docker**: For building container images
5. **GitHub Repository**: For automated deployments (optional)

## Quick Start

### 1. Setup GCP Authentication

```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Terraform Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your values
vim terraform.tfvars
```

Required variables:
- `project_id`: Your GCP project ID
- `github_owner`: Your GitHub username (for CI/CD)
- `github_repo`: Your repository name

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### 4. Build and Deploy Container

After the infrastructure is deployed, build and push your container:

```bash
# Build the container image
cd ../api
docker build -t gcr.io/YOUR_PROJECT_ID/codepush:latest .

# Push to Google Container Registry
docker push gcr.io/YOUR_PROJECT_ID/codepush:latest

# The VM will automatically pull and run the latest image
# Or manually restart the container on the VM:
gcloud compute ssh codepush-vm --zone=us-central1-a --command="sudo /opt/codepush/run-container.sh"
```

## Configuration Options

### VM Configuration

- `vm_machine_type`: VM instance type (e.g., e2-standard-2, e2-micro)
- `vm_disk_size_gb`: Boot disk size in GB
- `vm_disk_type`: Disk type (pd-standard, pd-ssd)
- `ssh_public_key`: SSH public key for VM access

### Redis Configuration

Redis runs locally on the VM with password authentication:
- `redis_password`: Password for Redis (auto-generated if empty)

### Application Configuration

- `emulated_mode`: Enable for development/testing
- `enable_account_registration`: Allow new user registration
- `upload_size_limit_mb`: Maximum upload size

### CI/CD with GitHub

When `enable_cicd = true`, the deployment creates:
- Cloud Build trigger connected to your GitHub repository
- Automatic builds on push to specified branch
- Automatic deployment to Cloud Run

To connect your GitHub repository:
1. Go to Cloud Build in the GCP Console
2. Connect your repository under "Triggers"
3. Authorize GitHub access

### Custom Domain (Optional)

To use a custom domain:
1. Set `custom_domain` variable to your domain
2. Point your DNS A record to the output IP address
3. SSL certificate will be automatically provisioned

## Security Considerations

- Redis is deployed in a private VPC with no public access
- Cloud Run uses a dedicated service account with minimal permissions
- Container runs as non-root user
- Health checks and resource limits are configured

## Monitoring and Maintenance

### Logs
```bash
# View Cloud Run logs
gcloud logs read --service=codepush-server --limit=50

# View build logs
gcloud builds list
gcloud builds log BUILD_ID
```

### Scaling
```bash
# Update instance limits
gcloud run services update codepush-server \
  --max-instances=20 \
  --region=us-central1
```

### Updates
To update the application:
1. Push changes to your GitHub repository (if CI/CD is enabled)
2. Or manually build and deploy a new container image

## Costs

Estimated monthly costs (us-central1):

- **Compute Engine VM** (e2-standard-2): ~$30-60/month
- **Storage** (GCS): ~$5-20/month 
- **Networking** (VPC, static IP): ~$5-10/month
- **Fastly CDN** (optional): Variable based on traffic
- **Total**: ~$40-90/month + Fastly costs

### Cost Optimization Tips
- Consider smaller VM types (e2-micro, e2-small) for development environments
- Enable **Fastly CDN** to reduce origin server bandwidth costs and improve global performance
- Use storage lifecycle policies to automatically clean up old packages
- Monitor usage and scale VM size based on actual resource needs

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your account has necessary IAM roles
2. **API Not Enabled**: The script enables required APIs automatically
3. **GitHub Connection**: Manually connect repository in Cloud Build console
4. **Container Not Found**: Build and push your image first

### Useful Commands

```bash
# Check service status
gcloud run services describe codepush-server --region=us-central1

# View Redis instance
gcloud redis instances describe codepush-redis --region=us-central1

# Check Cloud Build triggers
gcloud builds triggers list
```

## Clean Up

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including data stored in Redis.

## Support

This Terraform configuration is provided as-is. For issues with the CodePush server application itself, refer to the main repository documentation.
# CodePush Server - GCP Terraform Deployment

This Terraform configuration deploys the CodePush Server to Google Cloud Platform using Cloud Run, Redis, and supporting infrastructure.

## Architecture

- **Cloud Run**: Hosts the containerized CodePush server application
- **Redis (Memorystore)**: Provides caching and session storage
- **VPC**: Private network for secure communication
- **Cloud Build**: Automated CI/CD pipeline with GitHub integration
- **Load Balancer**: Optional custom domain support with SSL

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

After the infrastructure is deployed, you need to build and push your container:

```bash
# Build the container image
cd ../api
docker build -t gcr.io/YOUR_PROJECT_ID/codepush:latest .

# Push to Google Container Registry
docker push gcr.io/YOUR_PROJECT_ID/codepush:latest

# Update Cloud Run service
gcloud run deploy codepush-server \
  --image gcr.io/YOUR_PROJECT_ID/codepush:latest \
  --region us-central1 \
  --platform managed
```

## Configuration Options

### Redis Configuration

- `redis_tier`: Choose between "BASIC" or "STANDARD_HA"
- `redis_memory_size_gb`: Memory allocation for Redis instance

### Cloud Run Configuration

- `min_instances`/`max_instances`: Auto-scaling configuration
- `cpu_limit`/`memory_limit`: Resource limits
- `allow_public_access`: Whether to allow public internet access

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
- Cloud Run: $0-50 (depending on usage)
- Redis (1GB Basic): ~$35
- VPC/Networking: ~$5
- Total: ~$40-90/month

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
output "vm_external_ip" {
  description = "External IP address of the VM"
  value       = var.deployment_type == "vm" ? google_compute_address.vm_ip.address : null
}

output "vm_internal_ip" {
  description = "Internal IP address of the VM"
  value       = var.deployment_type == "vm" ? google_compute_instance.codepush_vm.network_interface[0].network_ip : null
}

output "vm_name" {
  description = "Name of the VM instance"
  value       = var.deployment_type == "vm" ? google_compute_instance.codepush_vm.name : null
}

output "vm_zone" {
  description = "Zone where the VM is deployed"
  value       = var.deployment_type == "vm" ? google_compute_instance.codepush_vm.zone : null
}

output "vm_ssh_command" {
  description = "SSH command to connect to the VM"
  value       = var.deployment_type == "vm" ? "gcloud compute ssh ${google_compute_instance.codepush_vm.name} --zone=${google_compute_instance.codepush_vm.zone}" : null
}

output "fastly_service_id" {
  description = "Fastly service ID"
  value       = var.enable_fastly ? fastly_service_vcl.codepush_service[0].id : null
}

output "fastly_domain" {
  description = "Fastly domain"
  value       = var.enable_fastly ? var.fastly_domain : null
}

output "fastly_cname_target" {
  description = "CNAME target for Fastly domain"
  value       = var.enable_fastly ? "${fastly_service_vcl.codepush_service[0].id}.global.ssl.fastly.net" : null
}

output "cost_estimate" {
  description = "Estimated monthly costs"
  value = var.deployment_type == "vm" ? {
    vm_cost        = "~$30-60/month (depending on machine type)"
    storage_cost   = "~$5-20/month (depending on usage)"
    networking_cost = "~$5-10/month"
    fastly_cost    = var.enable_fastly ? "Variable based on traffic" : "Not enabled"
    total_estimate = "~$40-90/month + Fastly costs"
  } : {
    cloudrun_cost   = "~$0-50/month (depending on usage)"
    redis_cost      = "~$35/month (1GB Basic)"
    storage_cost    = "~$5-20/month"
    networking_cost = "~$5-10/month"
    fastly_cost     = var.enable_fastly ? "Variable based on traffic" : "Not enabled"
    total_estimate  = "~$45-115/month + Fastly costs"
  }
}



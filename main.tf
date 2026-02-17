terraform {
  required_version = ">= 1.9.8"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

provider "kubernetes" {}

#########################################
# 1. VARIABLES (API Supported Fields)
#########################################
variable "name" { 
  type = string 
  default = "ubuntu-mig-test"
  }
variable "project" { 
  type = string 
  default = "osp-mig"
  }

variable "cpu" {
  type    = number
  default = null
}

variable "memory" {
  type    = string
  default = "8Gi"
}

variable "storage" {
  type    = string
  default = null
}

#########################################
# 2. DATA SOURCE & FALLBACK LOGIC
#########################################
data "kubernetes_resource" "live_vm" {
  api_version = "kubevirt.io/v1"
  kind        = "VirtualMachine"
  metadata {
    name      = var.name
    namespace = var.project
  }
}

# Fetch the current PVC to find its name and current size
data "kubernetes_resource" "live_pvc" {
  api_version = "v1"
  kind        = "PersistentVolumeClaim"
  metadata {
    name      = data.kubernetes_resource.live_vm.object.spec.template.spec.volumes[0].persistentVolumeClaim.claimName
    namespace = var.project
  }
}

locals {
  live_obj    = data.kubernetes_resource.live_vm.object
  live_spec   = local.live_obj.spec.template.spec
  live_domain = local.live_spec.domain
  live_pvc    = data.kubernetes_resource.live_pvc.object

  # # PVC Logic
  pvc_name    = local.live_spec.volumes[0].persistentVolumeClaim.claimName
  pvc_size    = var.storage != null ? var.storage : data.kubernetes_resource.live_pvc.object.spec.resources.requests.storage

  # Fallback logic for API-driven fields
  cpu_cores    = var.cpu     != null ? var.cpu     : local.live_domain.cpu.cores
  memory_guest = var.memory  != null ? var.memory  : local.live_domain.memory.guest
  
  # Non-API Fields: Always fetch from live cluster 
  vol_name      = local.live_spec.volumes[0].name
  network_name  = local.live_spec.networks[0].name
  multus_name   = local.live_spec.networks[0].multus.networkName
  interface_mac = local.live_domain.devices.interfaces[0].macAddress
}

#########################################
# 3. RESOURCE
#########################################
# RESOURCE 1: Update the PVC size
resource "kubernetes_manifest" "vm_pvc" {
  field_manager { force_conflicts = true }

  computed_fields = [
    "spec.volumeName",
    "spec.storageClassName",
    "spec.accessModes",
    "spec.volumeMode",
    "metadata.labels",
    "metadata.annotations",
    "metadata.finalizers"
  ]

  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = local.pvc_name
      namespace = var.project
    }
    spec = {
      resources = {
        requests = {
          storage = local.pvc_size
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      manifest.metadata,
      manifest.spec.volumeName,
      manifest.spec.storageClassName,
      manifest.spec.accessModes,
      manifest.spec.volumeMode
    ]
  }
}

resource "kubernetes_manifest" "kubevirt" {
  field_manager {
    force_conflicts = true
  }

  computed_fields = [
    "metadata.labels",
    "metadata.annotations",
    "metadata.finalizers",
    "object.metadata.annotations",
    "spec.template.metadata.labels",
    "spec.template.metadata.annotations",
    "spec.template.spec.domain.devices.interfaces",
    "spec.template.spec.domain.devices.disks",
    "spec.template.spec.networks"
  ]

  manifest = {
    apiVersion = "kubevirt.io/v1"
    kind       = "VirtualMachine"
    metadata = {
      name      = var.name
      namespace = var.project
      annotations = {
        "kubemacpool.io/transaction-timestamp" = ""
      }
    }
    spec = {
      runStrategy = "Always"
      template = {
        spec = {
          domain = {
            cpu = {
              cores   = local.cpu_cores
              sockets = local.live_domain.cpu.sockets
              threads = local.live_domain.cpu.threads
            }
            memory = { guest = local.memory_guest }
            machine = { type = try(local.live_domain.machine.type, "pc-q35-rhel9.4.0") }
            devices = {
              disks = [{
                bootOrder = 1
                name      = local.vol_name
                disk      = { bus = "virtio" }
              }]
              interfaces = [{
                name       = local.network_name
                model      = "virtio"
                macAddress = local.interface_mac
                bridge     = {}
              }]
            }
          }
          networks = [{
            name   = local.network_name
            multus = { networkName = local.multus_name }
          }]
          volumes = [{
            name = local.live_spec.volumes[0].name
            persistentVolumeClaim = { claimName = local.pvc_name }
          }]
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      manifest.spec.template.spec.domain.devices,
      manifest.spec.template.spec.networks,
      manifest.spec.template.spec.domain.machine
    ]
  }
}

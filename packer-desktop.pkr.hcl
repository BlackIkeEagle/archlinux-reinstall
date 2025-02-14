packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1"
    }
  }
}

variable "admin_pass" {
  type    = string
  default = "vagrant"
}

variable "admin_user" {
  type    = string
  default = "vagrant"
}

variable "boot_wait" {
  type    = string
  default = "60s"
}

variable "disk_size" {
  type    = string
  default = "40960"
}

variable "disk_type" {
  type    = string
  default = "regular"
}

variable "filesystem" {
  type    = string
  default = "xfs"
}

variable "kernelcmdline" {
  type    = string
  default = ""
}

variable "headless" {
  type    = string
  default = "true"
}

variable "install_type" {
  type    = string
  default = ""
}

variable "iso_checksum_url" {
  type    = string
  default = "https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt"
}

variable "iso_url" {
  type    = string
  default = "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
}
# The "legacy_isotime" function has been provided for backwards compatability, but we recommend switching to the timestamp and formatdate functions.

source "qemu" "libvirt" {
  boot_command     = ["<enter><enter>", "systemctl stop sshd.service<enter><wait>", "curl -O 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/archlinux-reinstall.tar.gz'<enter><wait>", "mkdir archlinux-reinstall && tar -xf archlinux-reinstall.tar.gz -C archlinux-reinstall<enter><wait>", "cd archlinux-reinstall<enter><wait>", "./desktop-install${var.install_type}.sh && systemctl reboot<enter>vda<enter>legacy<enter>${var.filesystem}<enter>${var.disk_type}<enter>${var.kernelcmdline}<enter><enter>${var.admin_user}<enter>${var.admin_user}<enter>${var.admin_pass}<enter><enter><wait>"]
  boot_wait        = "${var.boot_wait}"
  cpus             = 2
  disk_compression = true
  disk_interface   = "virtio"
  disk_size        = "${var.disk_size}"
  headless         = "${var.headless}"
  http_directory   = "./"
  iso_checksum     = "file:${var.iso_checksum_url}"
  iso_url          = "${var.iso_url}"
  memory           = 1024
  net_device       = "virtio-net"
  shutdown_command = "sudo systemctl poweroff"
  ssh_password     = "${var.admin_pass}"
  ssh_port         = 22
  ssh_timeout      = "3600s"
  ssh_username     = "${var.admin_user}"
}

build {
  sources = ["source.qemu.libvirt"]

  post-processor "vagrant" {
    output = "output/archlinux${var.install_type}-${var.filesystem}_${legacy_isotime("2006.01.02")}-{{ .Provider }}.box"
  }
}

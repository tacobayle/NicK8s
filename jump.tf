data "template_file" "jumpbox_userdata" {
  depends_on = [local_file.private_key]
  template = file("${path.module}/userdata/jump.userdata")
  vars = {
    pubkey        = chomp(tls_private_key.ssh.public_key_openssh)
    avisdkVersion = var.jump["avisdkVersion"]
    ansibleVersion = var.ansible["version"]
    vsphere_user  = var.vsphere_user
    vsphere_password = var.vsphere_password
    vsphere_server = var.vsphere_server
    username = var.jump["username"]
    privateKey = var.ssh_key.private_key_filename
  }
}

data "vsphere_virtual_machine" "jump" {
  name          = var.jump["template_name"]
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "jump" {
  name             = var.jump["name"]
  datastore_id     = data.vsphere_datastore.datastore.id
  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder           = vsphere_folder.folder.path
  network_interface {
                      network_id = data.vsphere_network.networkMgt.id
  }

  num_cpus = var.jump["cpu"]
  memory = var.jump["memory"]
  wait_for_guest_net_timeout = var.jump["wait_for_guest_net_timeout"]
  guest_id = data.vsphere_virtual_machine.jump.guest_id
  scsi_type = data.vsphere_virtual_machine.jump.scsi_type
  scsi_bus_sharing = data.vsphere_virtual_machine.jump.scsi_bus_sharing
  scsi_controller_count = data.vsphere_virtual_machine.jump.scsi_controller_scan_count

  disk {
    size             = var.jump["disk"]
    label            = "jump.lab_vmdk"
    eagerly_scrub    = data.vsphere_virtual_machine.jump.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.jump.disks.0.thin_provisioned
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.jump.id
  }

  vapp {
    properties = {
     hostname    = "jump"
     public-keys = chomp(tls_private_key.ssh.public_key_openssh)
     user-data   = base64encode(data.template_file.jumpbox_userdata.rendered)
   }
 }

  connection {
   host        = vsphere_virtual_machine.jump.default_ip_address
   type        = "ssh"
   agent       = false
   user        = var.jump.username
   private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner "remote-exec" {
   inline      = [
     "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
   ]
  }

  provisioner "file" {
    source      = "~/.ssh/${var.ssh_key.private_key_filename}"
    destination = "~/.ssh/${var.ssh_key.private_key_filename}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 ~/.ssh/${var.ssh_key.private_key_filename}"
    ]
  }
}
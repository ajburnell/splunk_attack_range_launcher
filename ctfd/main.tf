## Gunicorn / CTFd is CPU and memory heavy. ##
## Using m-class instances to get balance of VCPU with high memory ##
## TODO
## - Modularise the key creation
## - Generate a password for the ctfd user for sudo instead of ALL.

## Get the latest Ubuntu AMI
data "aws_ami" "ubuntu_x86_64" {
  most_recent = true
  owners = ["099720109477"] # Canonical

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-*"]
  }

  filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
}

## Generate a private key
resource "tls_private_key" "ctfd_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

## Create the AWS key pair
resource "aws_key_pair" "akp" {
  key_name   = "ctfd_private_key"
  public_key = tls_private_key.ctfd_key.public_key_openssh
}

## Save the private key to file
resource "local_file" "local_key_pair" {
  filename = var.private_key_filename
  file_permission = "0400"
  content = tls_private_key.ctfd_key.private_key_pem
}

## Save the public key to file
resource "local_file" "local_pub_key" {
  filename = var.public_key_filename
  file_permission = "0600"
  content = tls_private_key.ctfd_key.public_key_openssh
}

## Create the EC2 instance with spot pricing
resource "aws_instance" "ctfd_server" {
  ami = data.aws_ami.ubuntu_x86_64.id
  key_name = aws_key_pair.akp.key_name
  associate_public_ip_address = true

  instance_market_options {
    market_type = "spot"
        spot_options {
      max_price = 0.100
    }
  }

  instance_type = "t2.medium"
  tags = {
    Name = "ctfd"
  }

  ## Upload our unique key for the CTFd user.
  provisioner "file" {
    source      =  var.public_key_filename
    destination = "/tmp/ctfd_key.pub"

  connection {
      host        = aws_instance.ctfd_server.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file(var.private_key_filename)}"
    }
  }

  ## Add the ctfd user for Ansible provisioner
  ## Set up the key pair for Ansible access
  ## Stops us using the default OS account to run the webserver
  provisioner "remote-exec" {
    inline = [
      "sudo useradd ctfd -m -s /bin/bash",
      "sudo usermod -aG sudo ctfd",
      "sudo mkdir -p /home/ctfd/.ssh",
      "sudo cp /tmp/ctfd_key.pub /home/ctfd/.ssh/authorized_keys",
      "sudo chown -R ctfd:ctfd /home/ctfd/.ssh",
      "sudo chmod 700 /home/ctfd/.ssh && sudo chmod 600 /home/ctfd/.ssh/authorized_keys",
      "sudo su -c \"echo 'ctfd ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ctfd\""
    ]

   connection {
      host        = aws_instance.ctfd_server.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file(var.private_key_filename)}"
    }
  }

  depends_on = [
        aws_key_pair.akp,
        local_file.local_key_pair
        ]
}

resource "aws_route53_record" "ctfd_a" {
  zone_id = var.r53_zone_id
  name    = var.ctfd_hostname
  type    = "A"
  ttl     = "300"
  records = [ aws_instance.ctfd_server.public_ip ]
}

## Create the Ansible inventoy file
resource "local_file" "ansible_inventory_ctfd" {
  filename = "hosts.ini"
  content = <<EOT
        [ctfd]
        ${aws_instance.ctfd_server.public_ip}
  EOT
}

## We do this outside the instance creation so that the
## AWS R53 record exists. Otherwise the certbot DNS checks
## will fail in the playbook. :(

resource "terraform_data" "ctfd_ansible" {

  provisioner "local-exec" {
    command = <<EOT
    echo -e "[ctfd]\n${aws_instance.ctfd_server.public_ip}" > hosts.bak
    ANSIBLE_FORCE_COLOR=1 ansible-playbook -u ctfd -i hosts.ini --private-key ${var.private_key_filename} --ssh-common-args='-o StrictHostKeyChecking=no' playbook.yml -vv
    EOT
  }

  depends_on = [
    aws_instance.ctfd_server,
    aws_route53_record.ctfd_a
  ]
}

## Doesn't quite seem ready for prime time.
# resource "ansible_playbook" "provision_ctfd" {
#  playbook     = "playbook.yml"
#  name         = aws_instance.ctfd_server.public_ip
#  replayable   = true
#  verbosity    = 4
#  groups       = [ "ctfd" ]
#
#  # Debug
#  ignore_playbook_failure = true  # <- here
#
#  extra_vars = {
#    ansible_host                       = aws_instance.ctfd_server.public_ip
#    ansible_user                       = "ctfd"
#    ansible_ssh_private_key_file       = var.private_key_filename
#    ansible_ssh_common_args            = "\"'-o StrictHostKeyChecking=no'\""
#  }
#
#  depends_on = [
#    aws_instance.ctfd_server,
#    aws_route53_record.ctfd_a
#  ]
#}

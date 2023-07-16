data "aws_ami" "this" {
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

resource "tls_private_key" "launcher_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "splunk_launcher_key"
  public_key = tls_private_key.launcher_key.public_key_openssh
}

resource "local_file" "local_key_pair" {
  filename = "splunk_launcher_key.pem"
  file_permission = "0400"
  content = tls_private_key.launcher_key.private_key_pem
}

resource "aws_instance" "this" {
  ami = data.aws_ami.this.id
  key_name = "splunk_launcher_key"
  
  instance_market_options {
    market_type = "spot"
	spot_options {
      max_price = 0.020
    }
  }
  instance_type = "t3.medium"
  tags = {
    Name = "attack-launcher"
  }
  depends_on = [
	aws_key_pair.generated_key,
	local_file.local_key_pair
	]
}

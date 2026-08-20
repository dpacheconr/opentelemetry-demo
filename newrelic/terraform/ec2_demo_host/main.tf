resource "aws_vpc" "demo_host" {
  cidr_block           = "10.42.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "demo_host" {
  vpc_id = aws_vpc.demo_host.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "demo_host" {
  vpc_id                  = aws_vpc.demo_host.id
  cidr_block              = "10.42.0.0/26"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet"
  }
}

resource "aws_route_table" "demo_host" {
  vpc_id = aws_vpc.demo_host.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_host.id
  }

  tags = {
    Name = "${var.name_prefix}-rt"
  }
}

resource "aws_route_table_association" "demo_host" {
  subnet_id      = aws_subnet.demo_host.id
  route_table_id = aws_route_table.demo_host.id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "demo_host" {
  key_name   = "${var.name_prefix}-key"
  public_key = file(var.public_key_path)
}

resource "aws_security_group" "demo_host" {
  name        = "${var.name_prefix}-sg"
  description = "SSH and frontend-proxy access for the OpenTelemetry demo minikube host"
  vpc_id      = aws_vpc.demo_host.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "frontend-proxy (kubectl port-forward)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_instance" "demo_host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo_host.key_name
  subnet_id                   = aws_subnet.demo_host.id
  vpc_security_group_ids      = [aws_security_group.demo_host.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data                   = file("${path.module}/user_data.sh.tpl")
  user_data_replace_on_change = false

  tags = {
    Name = "${var.name_prefix}-host"
  }
}

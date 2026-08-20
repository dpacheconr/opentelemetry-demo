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

resource "aws_ssm_parameter" "new_relic_license_key" {
  name        = "/${var.name_prefix}/new-relic-license-key"
  description = "New Relic license key for the OpenTelemetry demo, read by the instance at boot"
  type        = "SecureString"
  value       = var.new_relic_license_key
}

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "demo_host" {
  name               = "${var.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
}

data "aws_iam_policy_document" "read_license_key" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.new_relic_license_key.arn]
  }
}

resource "aws_iam_role_policy" "read_license_key" {
  name   = "${var.name_prefix}-read-license-key"
  role   = aws_iam_role.demo_host.id
  policy = data.aws_iam_policy_document.read_license_key.json
}

resource "aws_iam_instance_profile" "demo_host" {
  name = "${var.name_prefix}-profile"
  role = aws_iam_role.demo_host.name
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

resource "aws_launch_template" "demo_host" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.demo_host.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.demo_host.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.demo_host.id]
    subnet_id                   = aws_subnet.demo_host.id
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = var.root_volume_size
      volume_type = "gp3"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    otel_demo_values             = file("${path.module}/../../k8s/helm/opentelemetry-demo.yaml")
    nr_k8s_otel_collector_values = file("${path.module}/../../k8s/helm/nr-k8s-otel-collector.yaml")
    ssm_license_key_param        = aws_ssm_parameter.new_relic_license_key.name
    aws_region                   = var.region
    new_relic_region             = var.new_relic_region
    otel_demo_chart_version      = var.otel_demo_chart_version
    nr_k8s_chart_version         = var.nr_k8s_chart_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-host"
    }
  }
}

resource "aws_autoscaling_group" "demo_host" {
  name                = "${var.name_prefix}-asg"
  vpc_zone_identifier = [aws_subnet.demo_host.id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.demo_host.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-host"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_schedule" "stop_weekend" {
  scheduled_action_name  = "${var.name_prefix}-stop-weekend"
  autoscaling_group_name = aws_autoscaling_group.demo_host.name
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  recurrence             = "0 20 * * FRI"
  time_zone              = "UTC"
}

resource "aws_autoscaling_schedule" "start_weekday" {
  scheduled_action_name  = "${var.name_prefix}-start-weekday"
  autoscaling_group_name = aws_autoscaling_group.demo_host.name
  min_size               = 1
  max_size               = 1
  desired_capacity       = 1
  recurrence             = "0 6 * * MON"
  time_zone              = "UTC"
}

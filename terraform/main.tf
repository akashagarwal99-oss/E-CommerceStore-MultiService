resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false

  tags = {
    Name    = "${var.project_name}-private-subnet"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip"
    Project = var.project_name
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name    = "${var.project_name}-nat-gateway"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-private-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Allow HTTP access to frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP traffic from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-frontend-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Allow traffic from frontend to backend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "User service traffic from frontend"
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Product service traffic from frontend"
    from_port       = 3002
    to_port         = 3002
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Cart service traffic from frontend"
    from_port       = 3003
    to_port         = 3003
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Order service traffic from frontend"
    from_port       = 3004
    to_port         = 3004
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    description = "Allow outbound traffic for image pulls and external services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-backend-sg"
    Project = var.project_name
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "frontend" {
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.instance_type
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.frontend.id]

  user_data = <<-EOF
  #!/bin/bash
  set -eu

  yum install -y docker
  systemctl enable --now docker

  docker pull ${var.dockerhub_username}/ecommerce-frontend:latest

  docker run -d --name ecommerce-frontend --restart unless-stopped -p 80:80 -e BACKEND_PRIVATE_IP="${aws_instance.backend.private_ip}"${var.dockerhub_username}/ecommerce-frontend:latest
  EOF

  tags = {
    Name    = "${var.project_name}-frontend-instance"
    Project = var.project_name
  }
}

# Find the existing secret by name.
# This reads its metadata, not its secret value.
data "aws_secretsmanager_secret" "backend" {
  name = "ecommerce/backend"
}

# IAM role that EC2 can assume
resource "aws_iam_role" "backend" {
  name = "${var.project_name}-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

# Allow access to only our application secret
resource "aws_iam_role_policy" "backend_secrets" {
  name = "${var.project_name}-read-backend-secret"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = data.aws_secretsmanager_secret.backend.arn
    }]
  })
}

# Makes the IAM role attachable to EC2
resource "aws_iam_instance_profile" "backend" {
  name = "${var.project_name}-backend-profile"
  role = aws_iam_role.backend.name
}


resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.backend.id]

  iam_instance_profile        = aws_iam_instance_profile.backend.name
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/bash
    set -eu

    # Install and start Docker
    yum install -y docker awscli jq
    systemctl enable --now docker

    # Create Docker network
    docker network create ecommerce-network

    # Retrieve the secret from AWS Secrets Manager
    SECRET_JSON=$(aws secretsmanager get-secret-value \
      --secret-id ecommerce/backend \
      --region ${var.aws_region} \
      --query SecretString \
      --output text)

    MONGODB_BASE_URI=$(printf '%s' "$SECRET_JSON" | jq -er '.MONGODB_BASE_URI')
    JWT_SECRET=$(printf '%s' "$SECRET_JSON" | jq -er '.JWT_SECRET')

    unset SECRET_JSON

    # Pull backend images
    docker pull ${var.dockerhub_username}/ecommerce-user-service:latest
    docker pull ${var.dockerhub_username}/ecommerce-product-service:latest
    docker pull ${var.dockerhub_username}/ecommerce-cart-service:latest
    docker pull ${var.dockerhub_username}/ecommerce-order-service:latest

    # Start user service
    docker run -d \
      --name user-service \
      --network ecommerce-network \
      --restart unless-stopped \
      -p 3001:3001 \
      -e MONGODB_URI="$${MONGODB_BASE_URI}ecommerce_users" \
      -e JWT_SECRET \
      ${var.dockerhub_username}/ecommerce-user-service:latest

    # Start product service
    docker run -d \
      --name product-service \
      --network ecommerce-network \
      --restart unless-stopped \
      -p 3002:3002 \
      -e MONGODB_URI="$${MONGODB_BASE_URI}ecommerce_products" \
      ${var.dockerhub_username}/ecommerce-product-service:latest

    # Start cart service
    docker run -d \
      --name cart-service \
      --network ecommerce-network \
      --restart unless-stopped \
      -p 3003:3003 \
      -e MONGODB_URI="$${MONGODB_BASE_URI}ecommerce_carts" \
      -e PRODUCT_SERVICE_URL=http://product-service:3002 \
      ${var.dockerhub_username}/ecommerce-cart-service:latest

    # Start order service
    docker run -d \
      --name order-service \
      --network ecommerce-network \
      --restart unless-stopped \
      -p 3004:3004 \
      -e MONGODB_URI="$${MONGODB_BASE_URI}ecommerce_orders" \
      -e PRODUCT_SERVICE_URL=http://product-service:3002 \
      ${var.dockerhub_username}/ecommerce-order-service:latest

    # Clear secrets from shell variables
    unset MONGODB_BASE_URI JWT_SECRET

  EOF

  tags = {
    Name    = "${var.project_name}-backend"
    Project = var.project_name
  }

  depends_on = [
    aws_iam_role_policy.backend_secrets
  ]
}

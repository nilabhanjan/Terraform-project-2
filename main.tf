terraform {
  # Assumes s3 bucket and dynamo DB table already set up in aws-backend
 
  backend "s3" {
    bucket         = "nilabh-bucket-1"
    key            = "Terraform project 2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      
    }
  }
}

#variables decleration
variable "subnet_prefix" {
    description = "cidr block for subnet"
}

variable "ec2_size" {
  description = "type of ec2 instance"
  default = "t2.micro"
}

variable "ssh_key" {
  description = "key for connection"
}

variable "ami_code" {
  description = "ami code of the instance"
  
}

variable "cidr_block" {
  description = "cidr block for vpc"
  
}

#resoorces decleration

provider "aws" {
    region = "us-east-1"
  
}


resource "aws_vpc" "prod-vpc" {
  cidr_block = var.cidr_block
  tags ={
    Name ="production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  
}

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}



resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.prod-vpc.id
    cidr_block = var.subnet_prefix
    availability_zone= "us-east-1a"

    tags ={
        Name = "Prod"
    }
}

resource "aws_route_table_association" "a" {
  subnet_id  = aws_subnet.subnet-1.id 
  route_table_id = aws_route_table.prod-route-table.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow WEB traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

   ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

   ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_network_interface" "web-server" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

 
}

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}


resource "aws_instance" "web-server-instance" {
    ami = var.ami_code
    instance_type = var.ec2_size
    availability_zone = "us-east-1a"
    key_name = var.ssh_key

    network_interface {
      device_index = 0
      network_interface_id = aws_network_interface.web-server.id
    }

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo web server > /var/www/html/index.html'
                EOF

     tags ={
        Name ="web-server"
     }           
}


output "server_public_ip" {
    value = aws_eip.one.public_ip
  
}
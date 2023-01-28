# Configure the AWS Provider

provider "aws" {
  region = var.region
  shared_credentials_files = ["~/.aws/credentials"]
  profile = "default"
}


resource "aws_vpc" "app_vpc" {
  cidr_block = var.vpc_cidr
 instance_tenancy     = var.instance_tenancy
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "app-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "vpc_igw"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = var.vpc_cidr == "178.0.0.0/16" ? 3 : 0
  vpc_id            = aws_vpc.app_vpc.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = element(cidrsubnets(var.vpc_cidr, 8, 4, 4), count.index)

  tags = {
    "Name" = "Public-Subnet-${count.index}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

resource "aws_eip" "eip" {
  count            = length(aws_instance.web.*.id)
  instance         = element(aws_instance.web.*.id, count.index)
  public_ipv4_pool = "amazon"
  vpc              = true

  tags = {
    "Name" = "EIP-${count.index}"
  }
}

resource "aws_eip_association" "eip_association" {
  count         = length(aws_eip.eip)
  instance_id   = element(aws_instance.web.*.id, count.index)
  allocation_id = element(aws_eip.eip.*.id, count.index)
}

resource "aws_route_table_association" "public_rt_asso" {
  count          = length(aws_subnet.public_subnet) == 3 ? 3 : 0
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
}

resource "aws_instance" "web" {
  count            = length(aws_subnet.public_subnet.*.id)
  ami             = "ami-06e85d4c3149db26a"
  instance_type   = var.instance_type
  key_name        = var.instance_key
  subnet_id       = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.sg.id]

  user_data = <<-EOF
  #!/bin/bash
  cd /tmp
  sudo yum update -y
  sudo yum install httpd -y
  sudo chmod 777 /var/www/html -R
  echo '<head> <title>Hello World</title> </head> <body><h1>Hello World!</h1></body></html>' >> /var/www/html/index.html
  sudo systemctl start httpd
  sudo systemctl enable httpd
  sudo yum install -y mod_ssl
  cd /etc/pki/tls/certs
  sudo ./make-dummy-cert localhost.crt
  cd /etc/httpd/conf.d
  sudo su
  sed -e '/SSLCertificateKeyFile/s/^/#/g' -i ssl.conf
  sudo systemctl restart httpd
  EOF

  tags = {
    "Name"        = "Instance-${count.index}"
    "Environment" = "Test"
    "CreatedBy"   = "Terraform"
  }

  timeouts {
    create = "10m"
  }

  volume_tags = {
    Name = "web_instance"
  }
}

data "aws_route53_zone" "public-zone" {
  zone_id = "Z09448741N25V539U9BLS"
  private_zone = false
}

resource "aws_route53_record" "linux-alb-a-record" {
  depends_on = [aws_lb.lb]
  zone_id = data.aws_route53_zone.public-zone.zone_id
  name    = "record.A.${var.public_dns_name}"
  type    = "A"
  alias {
    name                   = aws_lb.lb.dns_name
    zone_id                = aws_lb.lb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "linux-alb-aaaa-record" {
  depends_on = [aws_lb.lb]
  zone_id = data.aws_route53_zone.public-zone.zone_id
  name    = "record.AAAA.${var.public_dns_name}"
  type    = "AAAA"
  alias {
    name                   = aws_lb.lb.dns_name
    zone_id                = aws_lb.lb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "linux-alb-certificate" {
  domain_name       = "${var.public_dns_name}"
  validation_method = "DNS"
  tags = {
    Name        = "linux-alb-certificate"
  }
}

resource "aws_route53_record" "linux-alb-certificate-validation-record" {
  count = length(aws_acm_certificate.linux-alb-certificate.domain_validation_options)

  zone_id = data.aws_route53_zone.public-zone.zone_id
  name    = element(aws_acm_certificate.linux-alb-certificate.domain_validation_options.*.resource_record_name, count.index)
  type    = element(aws_acm_certificate.linux-alb-certificate.domain_validation_options.*.resource_record_type, count.index)
  records = [element(aws_acm_certificate.linux-alb-certificate.domain_validation_options.*.resource_record_value, count.index)]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "linux-certificate-validation" {
  certificate_arn = aws_acm_certificate.linux-alb-certificate.arn
  validation_record_fqdns = aws_route53_record.linux-alb-certificate-validation-record.*.fqdn
}

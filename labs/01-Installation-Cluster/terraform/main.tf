# Récupération de l'AMI officielle Ubuntu Server 24.04 LTS via SSM Parameter Store
data "aws_ssm_parameter" "ubuntu_2404_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Récupération du VPC par défaut
data "aws_vpc" "default" {
  default = true
}

# Groupe de sécurité pour le cluster
resource "aws_security_group" "k8s_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Groupe de securite pour le cluster Kubernetes kubeadm formation"
  vpc_id      = data.aws_vpc.default.id

  # 1. Tout le trafic interne entre membres du groupe de sécurité (Calico IPIP, kubelet, etcd)
  ingress {
    description = "Trafic intra-cluster complet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # 2. Accès SSH pour les stagiaires
  ingress {
    description = "Acces SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 3. API Server Kubernetes (accès distant éventuel)
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 4. Plage NodePort : Ingress NGINX (30080/30443), frontend Lab 04 (30088), Lab 08 (30089), Grafana (Lab 06)
  ingress {
    description = "Plage NodePort Kubernetes"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Trafic sortant illimité
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name}-sg"
    Project = "Kubernetes-Administration"
  }
}

# Nœud Control Plane (t3.large, 35 Gio par défaut : voir variables.tf)
resource "aws_instance" "control_plane" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type               = var.control_plane_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.control_plane_disk_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  source_dest_check = false

  user_data = templatefile("${path.module}/scripts/bootstrap.sh", { node_name = "k8s-control" })

  tags = {
    Name    = "k8s-control"
    Role    = "control-plane"
    Project = "Kubernetes-Administration"
  }
}

# Elastic IP fixe pour k8s-control : l'adresse du kubeconfig local reste stable après un arrêt/redémarrage
resource "aws_eip" "control_plane_eip" {
  instance = aws_instance.control_plane.id
  domain   = "vpc"

  tags = {
    Name    = "k8s-control-eip"
    Project = "Kubernetes-Administration"
  }
}

# Worker 1 (t3.large, 30 Gio par défaut : voir variables.tf)
resource "aws_instance" "worker_1" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type               = var.worker_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.worker_disk_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  source_dest_check = false

  user_data = templatefile("${path.module}/scripts/bootstrap.sh", { node_name = "k8s-worker-1" })

  tags = {
    Name    = "k8s-worker-1"
    Role    = "worker"
    Project = "Kubernetes-Administration"
  }
}

# Worker 2 (t3.large, 30 Gio par défaut : voir variables.tf)
resource "aws_instance" "worker_2" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type               = var.worker_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.worker_disk_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  source_dest_check = false

  user_data = templatefile("${path.module}/scripts/bootstrap.sh", { node_name = "k8s-worker-2" })

  tags = {
    Name    = "k8s-worker-2"
    Role    = "worker"
    Project = "Kubernetes-Administration"
  }
}

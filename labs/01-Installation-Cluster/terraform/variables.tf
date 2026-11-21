variable "aws_region" {
  description = "Région AWS autorisée dans AWS Academy Learner Lab (us-east-1 ou us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Nom de la paire de clés SSH préexistante dans AWS Academy (vockey)"
  type        = string
  default     = "vockey"
}

variable "cluster_name" {
  description = "Nom du cluster pour le tagging des ressources"
  type        = string
  default     = "k8s-formation"
}

variable "control_plane_instance_type" {
  description = "Type d'instance pour le nœud de contrôle (t3.large avec 8 Gio RAM pour etcd, addons et poste de travail)"
  type        = string
  default     = "t3.large"
}

variable "worker_instance_type" {
  description = "Type d'instance pour les nœuds workers (t3.large avec 8 Gio RAM chacun pour supporter la pile de formation sans OOM)"
  type        = string
  default     = "t3.large"
}

variable "control_plane_disk_size" {
  description = "Taille du disque racine gp3 du nœud de contrôle en Gio"
  type        = number
  default     = 35
}

variable "worker_disk_size" {
  description = "Taille du disque racine gp3 des workers en Gio"
  type        = number
  default     = 30
}

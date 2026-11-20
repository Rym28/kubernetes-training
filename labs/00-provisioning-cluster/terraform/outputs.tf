output "control_plane_public_ip" {
  description = "Adresse IP publique fixe (Elastic IP) du nœud de contrôle"
  value       = aws_eip.control_plane_eip.public_ip
}

output "control_plane_private_ip" {
  description = "Adresse IP privée du nœud de contrôle"
  value       = aws_instance.control_plane.private_ip
}

output "worker_1_public_ip" {
  description = "Adresse IP publique du worker 1"
  value       = aws_instance.worker_1.public_ip
}

output "worker_1_private_ip" {
  description = "Adresse IP privée du worker 1"
  value       = aws_instance.worker_1.private_ip
}

output "worker_2_public_ip" {
  description = "Adresse IP publique du worker 2"
  value       = aws_instance.worker_2.public_ip
}

output "worker_2_private_ip" {
  description = "Adresse IP privée du worker 2"
  value       = aws_instance.worker_2.private_ip
}

output "ssh_control_plane_command" {
  description = "Commande SSH directe pour se connecter au poste de travail (control plane)"
  value       = "ssh -i labsuser.pem ubuntu@${aws_eip.control_plane_eip.public_ip}"
}

output "ingress_nodeport_url" {
  description = "Point d'accès HTTP Ingress NodePort fixe (Control Plane)"
  value       = "http://${aws_eip.control_plane_eip.public_ip}:30080"
}

output "ingress_nodeport_worker_urls" {
  description = "Points d'accès HTTP Ingress NodePort sur les workers"
  value = [
    "http://${aws_instance.worker_1.public_ip}:30080",
    "http://${aws_instance.worker_2.public_ip}:30080"
  ]
}

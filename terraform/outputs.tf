output "jumpbox_ip" {
  value = aws_instance.k8s["jumpbox"].public_ip
}

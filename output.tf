output "public_ip" {
  value = zipmap(aws_instance.web.*.tags.Name, aws_eip.eip.*.public_ip)
}

output "public_dns" {
  value = zipmap(aws_instance.web.*.tags.Name, aws_eip.eip.*.public_dns)
}

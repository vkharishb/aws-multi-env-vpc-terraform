output "asg_name" {
  value = aws_autoscaling_group.this.name
}

output "asg_arn" {
  value = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  value = aws_launch_template.this.id
}

output "iam_role_name" {
  value = aws_iam_role.instance.name
}

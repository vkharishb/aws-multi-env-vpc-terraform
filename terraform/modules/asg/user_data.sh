#!/bin/bash
# Bootstraps a minimal web server so the ALB health check and demo page
# have something to respond with. Replace this with your real deployment
# mechanism (CodeDeploy, a config management tool, a container pull, etc.)
# when you move past the demo stage.
set -euo pipefail

dnf update -y
dnf install -y httpd

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head><title>${environment} - Multi-Env VPC Demo</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 10%;">
  <h1>AWS Region: ${aws_region}</h1>
  <h2>Environment: ${environment}</h2>
  <p>Served by instance: $${INSTANCE_ID}</p>
  <p>Availability Zone: $${AZ}</p>
</body>
</html>
HTML

systemctl enable httpd
systemctl start httpd

# Multi-Environment VPC Architecture — Terraform (AWS)

A secure, highly available, multi-AZ network topology on AWS, provisioned entirely through
modularized Terraform, with remote state stored in Amazon S3 and state locking via Amazon DynamoDB.

Two independent, isolated environments (`dev`, `prod`) are built from the same reusable modules,
each with its own VPC, CIDR range, and state file — changes in one can never affect the other.

---

## 1. System Architecture

```
                                   Internet
                                      │
                                      ▼
                         ┌────────────────────────┐
                         │   Internet Gateway      │
                         └────────────┬────────────┘
                                      │
        ┌─────────────────────────────────────────────────────────┐
        │                         VPC (per env)                    │
        │                                                          │
        │   AZ-a                     AZ-b                  AZ-c    │
        │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
        │  │ Public Subnet│  │ Public Subnet│  │ Public Subnet│    │  ← ALB + NAT GW live here
        │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │    │
        │  │  │NAT GW  │  │  │  │NAT GW  │  │  │  │NAT GW  │  │    │  (prod: 1 per AZ / dev: 1 shared)
        │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │    │
        │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
        │         │                 │                 │            │
        │         └────────┬────────┴────────┬────────┘            │
        │                  │  Application Load Balancer │           │
        │                  │  (internet-facing, public) │           │
        │                  └────────────┬────────────────┘         │
        │                               │                          │
        │   AZ-a                     AZ-b                  AZ-c    │
        │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
        │  │Private Subnet│  │Private Subnet│  │Private Subnet│    │  ← EC2 Auto Scaling Group
        │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │    │     (no public IP, no SSH)
        │  │  │EC2 App │  │  │  │EC2 App │  │  │  │EC2 App │  │    │
        │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │    │
        │  └──────────────┘  └──────────────┘  └──────────────┘    │
        │           ▲                                              │
        │           │ private, no NAT/internet needed               │
        │  ┌────────┴─────────────────────────┐                     │
        │  │ VPC Interface Endpoints:          │                     │
        │  │  ssm / ssmmessages / ec2messages  │  ← SSM Session Manager access
        │  │ VPC Gateway Endpoint: s3          │                     │
        │  └────────────────────────────────────┘                    │
        └─────────────────────────────────────────────────────────┘
```

**Traffic flow (inbound):** Internet → IGW → ALB (public subnets) → Target Group → EC2 instances (private subnets, port 80).

**Traffic flow (outbound, e.g. `yum update`):** EC2 (private) → NAT Gateway (public subnet) → IGW → Internet.

**Operator access (no SSH, no bastion):** Engineer → AWS Systems Manager Session Manager → VPC Interface Endpoints → EC2 instances, entirely over AWS's private network. IAM controls who can start a session; every session is logged.

### Design decisions

| Decision | Choice | Why |
|---|---|---|
| Subnet tiers | Public (ALB, NAT) / Private (app instances) | App instances are never internet-reachable |
| AZ spread | dev: 2 AZs · prod: 3 AZs | Prod tolerates a full AZ outage; dev stays cheap |
| NAT strategy | dev: 1 shared NAT · prod: 1 NAT per AZ | Dev optimizes cost; prod removes the single point of failure |
| Instance access | SSM Session Manager only | No SSH keys to issue, rotate, or leak; every session is IAM-authenticated and audit-logged |
| Load balancing | Application Load Balancer + target-tracking Auto Scaling | HTTP-aware routing/health checks, scales on CPU automatically |
| State storage | S3 (versioned, encrypted, blocked public access) + DynamoDB locking | Team-safe state, no local `.tfstate` files, no concurrent-apply corruption |
| IMDS | IMDSv2 enforced (`http_tokens = "required"`) | Blocks the classic SSRF → credential-theft path against IMDSv1 |
| EBS | Encrypted `gp3` root volumes | Data-at-rest encryption by default |

---

## 2. Folder Structure

```
terraform-multi-env-vpc/
├── README.md
├── .gitignore
│
├── bootstrap/                    # Run ONCE, manually, before anything else
│   ├── main.tf                   #   Creates the S3 state bucket + DynamoDB lock table
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/                      # Reusable, environment-agnostic building blocks
│   ├── vpc/                      #   VPC, IGW, public/private subnets, route tables
│   ├── nat-gateway/               #   NAT Gateway(s) - "single" or "per_az" mode
│   ├── security-groups/          #   ALB SG → App SG → VPC-Endpoint SG (least privilege chain)
│   ├── vpc-endpoints/             #   SSM interface endpoints + S3 gateway endpoint
│   ├── alb/                       #   Application Load Balancer, target group, listeners
│   └── asg/                       #   Launch template, IAM role (SSM), Auto Scaling Group
│
└── environments/                 # One root module per environment - each has its OWN state
    ├── dev/
    │   ├── backend.tf             #   Remote state config (S3 key unique to dev)
    │   ├── providers.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars       #   dev-specific values (2 AZs, 1 NAT, small instances)
    │   ├── main.tf                #   Wires the modules above together
    │   └── outputs.tf
    └── prod/
        ├── backend.tf             #   Remote state config (different S3 key - isolated from dev)
        ├── providers.tf
        ├── variables.tf
        ├── terraform.tfvars       #   prod-specific values (3 AZs, NAT per AZ, bigger ASG)
        ├── main.tf
        └── outputs.tf
```

**Why this layout:** modules contain no environment-specific values at all — every CIDR, AZ list,
and instance size lives in `environments/*/terraform.tfvars`. Adding a third environment (e.g.
`staging`) means copying `environments/dev`, not touching a single module.

---

## 3 & 4. Source Code and Usage

The full working code is included in this project (all files under `modules/`, `environments/`,
and `bootstrap/`). Steps to actually run it:

### Prerequisites
- Terraform >= 1.6.0
- AWS CLI configured with credentials (`aws configure`) that have permissions to create VPCs, EC2,
  ALB, IAM roles, S3, and DynamoDB
- An AWS account (all resources here are created **in AWS only**, no other cloud)

### Step 1 — Bootstrap the remote state backend (once per AWS account)

```bash
cd bootstrap

# IMPORTANT: state_bucket_name must be globally unique across ALL of AWS.
# Edit variables.tf or pass -var to override the default.
terraform init
terraform apply -var="state_bucket_name=<your-unique-bucket-name>"
```

Note the `state_bucket_name` you used — you'll paste it into both `environments/dev/backend.tf`
and `environments/prod/backend.tf` if you changed it from the default.

### Step 2 — Deploy dev

```bash
cd ../environments/dev
terraform init      # connects to the S3 backend created in step 1
terraform plan
terraform apply
```

### Step 3 — Deploy prod

```bash
cd ../prod
terraform init
terraform plan
terraform apply
```

### Verify

```bash
terraform output alb_dns_name
# open the returned DNS name in a browser - you should see the demo page
```

### Connect to an instance (no SSH key needed)

```bash
aws ssm start-session --target <instance-id>
```

### Tear down

```bash
# from environments/dev or environments/prod
terraform destroy

# only if you want to remove the backend itself (rarely needed):
# cd bootstrap && terraform destroy   (blocked by prevent_destroy - remove that lifecycle block first)
```

---

## 5. Access Management & Endpoints (Load Balancer)

**Public entry point:** the Application Load Balancer is the *only* internet-facing resource.
It lives in the public subnets, listens on 80 (and 443 if you supply `certificate_arn`), and
forwards to the target group on the app port.

**Instance access model — zero SSH surface:**
- No key pair is created or attached to any instance.
- No security group allows port 22 from anywhere.
- Instances get an IAM role (`AmazonSSMManagedInstanceCore`) and reach AWS Systems Manager over
  **VPC interface endpoints** (`ssm`, `ssmmessages`, `ec2messages`) — traffic never leaves the AWS
  network, and works even in the `per_az` NAT setup without depending on NAT at all.
- Engineers connect with `aws ssm start-session`, authenticated and authorized entirely through IAM.
  Every session can be logged to CloudWatch/S3 for audit.

**Security group chain (least privilege):**
```
Internet (0.0.0.0/0) → ALB SG (80/443)
ALB SG                → App SG (app_port only, source = ALB SG, NOT 0.0.0.0/0)
App SG                → VPC-Endpoint SG (443, source = App SG only)
```
No tier trusts a wider source than it needs to.

**HTTPS:** the ALB module accepts an optional `certificate_arn` (bring your own ACM certificate).
When set, port 80 redirects to 443 and TLS 1.2+ is enforced via
`ELBSecurityPolicy-TLS13-1-2-2021-06`. Left empty, the ALB runs HTTP-only (fine for a dev/demo
environment).

---

## 6. Questions

If anything about the design, a specific resource, or how to extend this (adding HTTPS, a third
environment, ECS instead of EC2, CI/CD via GitHub Actions, etc.) isn't clear — ask and I'll walk
through it or adjust the code.

**A few things worth deciding before you run `terraform apply` for real:**
1. What should `state_bucket_name` in `bootstrap/variables.tf` actually be? (must be globally unique)
2. Do you have an ACM certificate ready for HTTPS, or is HTTP-only fine for now?
3. Should `environments/prod/main.tf`'s ALB `enable_deletion_protection = true` stay on (recommended), or do you want it off while you're still testing destroy/recreate cycles?
4. Do you want this wired into a CI/CD pipeline (e.g. GitHub Actions running `terraform plan` on PRs) as a next step?

---

## 7. Cloud Provider

Everything in this project is built for **AWS only** — VPC, EC2, ALB, IAM, S3, DynamoDB, and
Systems Manager. No multi-cloud abstraction is used, keeping the modules simple and AWS-idiomatic.

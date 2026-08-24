# AWS 3-Tier Infrastructure & Monitoring System (Terraform Managed)

This project demonstrates a production-grade, scalable, and secure 3-tier cloud architecture on AWS. The entire infrastructure is provisioned and managed using **Terraform (Infrastructure as Code)**, ensuring consistency, version control, and automated deployments.

---

## 🏗️ Architecture Overview
The system is designed for high availability and strict security, following the AWS Well-Architected Framework.

### 1. Networking (VPC & Multi-AZ)
* **Custom VPC:** `10.0.0.0/16` isolated environment.
* **Public Subnets:** Spread across `us-east-1a` and `us-east-1b` for the Application Load Balancer (ALB) and Frontend/Bastion host.
* **Private Subnets:** Isolated subnets for the Backend, Worker, and RDS, preventing direct internet access.
* **Internet Gateway (IGW):** Provides connectivity for public resources.

### 2. Compute & Load Balancing
* **Application Load Balancer (ALB):** Distributes incoming traffic across Frontend instances in multiple AZs.
* **Frontend (Nginx):** Acts as a reverse proxy. Public IP: `44.207.86.60`.
* **Backend (Flask):** Private REST API handling business logic.
* **Worker Service:** A background monitoring service that processes logs and triggers alerts.

### 3. Database & Storage
* **RDS PostgreSQL:** A managed database instance residing in the private subnets.
* **S3 Buckets:**
    * `new-mission-bucket`: Stores application logs and shared data.
    * `terraform-state-bucket`: Manages the remote Terraform state file for team collaboration.

---

## 🛠️ Terraform Implementation (IaC)

The infrastructure is broken down into modular components for maintainability:

### Modular Structure
* **Networking Module:** Manages VPC, Subnets, Route Tables, and IGW.
* **Security Module:** Handles **Security Group Referencing** (e.g., DB only accepts traffic from Backend/Worker) and IAM Roles.
* **Compute Module:** Provisions EC2 instances with **IAM Instance Profiles**, removing the need for local AWS keys.
* **Database Module:** Provisions the RDS instance and integrates with AWS Secrets Manager.

### Key IaC Features
* **Remote State Management:** State is stored in S3 with DynamoDB locking to prevent concurrent modification.
* **Secrets Management:** Database credentials are securely stored in **AWS Secrets Manager**, fetched dynamically by Terraform.
* **Variables & Outputs:** Use of `terraform.tfvars` for environment-specific configurations (e.g., region, instance types).

---

## 🔒 Security & IAM
* **Least Privilege:** Each component has a specific IAM Role. The Worker can only `PutObject` to S3 and `Publish` to SNS.
* **Security Groups:** * `SG-Database`: Port 5432 restricted to `SG-Backend` and `SG-Worker`.
    * `SG-Backend`: Port 5000 restricted to `SG-Frontend`.
* **Bastion Access:** Secure SSH access to private instances via the Frontend/Bastion host using `avivPair-01.pem`.

---

## 🚀 Monitoring & SNS Alerts
The **Worker** service utilizes custom Python logic with the `boto3` SDK:
1. **Log Collection:** Monitors system and application logs.
2. **S3 Archive:** Uploads logs to `s3://new-mission-bucket`.
3. **SNS Notification:** Sends human-readable email alerts via **AWS SNS** (`mission-alerts`) upon critical events or successful log rotations.

---

## 💻 Operations

### Deployment
```bash
# Initialize Terraform and S3 backend
terraform init

# Preview changes
terraform plan

# Apply infrastructure changes
terraform apply -var-file="terraform.tfvars"

----------------------------------------------------------

# AWS 3-Tier Infrastructure & Automated Monitoring System (Terraform Managed)

This project demonstrates a production-grade, scalable, and secure 3-tier cloud architecture on AWS. The entire infrastructure is provisioned and managed using **Terraform (Infrastructure as Code)**, ensuring consistency, version control, and automated deployments.

---

## 🏗️ Architecture Overview
The system is designed for high availability and strict security, following the AWS Well-Architected Framework.

### 1. Networking (VPC & Multi-AZ)
* **Custom VPC:** `10.0.0.0/16` isolated environment.
* **Public Subnets:** Hosting the Frontend web servers and acting as Bastion hosts for secure entry.
* **Private Subnets:** Isolated subnets for the Backend, Worker, and RDS, preventing direct internet access.
* **Internet Gateway (IGW):** Provides connectivity for public resources.

### 2. Compute & App Tier
* **Frontend (Nginx):** Acts as a reverse proxy routing external HTTP traffic directly to the internal API. Public IP: `44.207.86.60`.
* **Backend (Docker + Flask/Gunicorn):** Private REST API handling business logic, database transactions, and dispatching messages to the queue.
* **Worker Service (Docker):** A background worker that polls the message queue, processes tasks asynchronously, stores artifacts, and triggers alerts.

### 3. Database, Messaging & Storage
* **RDS PostgreSQL:** A managed relational database instance residing securely in the private subnets.
* **Amazon SQS:** Message queue decoupling the Backend and Worker services to ensure asynchronous task processing without timeouts.
* **S3 Buckets:**
    * `new-mission-bucket`: Stores application logs and shared data processed by the Worker.
    * `terraform-state-bucket`: Manages the remote Terraform state file for team collaboration.
* **Amazon SNS:** Topic `mission-alerts` configured for automated email notifications upon task completion.

---

## 🛠️ Terraform Implementation (IaC)

The infrastructure is broken down into modular components for maintainability:

### Modular Structure
* **Networking Module:** Manages VPC, Subnets, Route Tables, and IGW.
* **Security Module:** Handles **Security Group Referencing** (e.g., DB only accepts traffic from Backend) and IAM Roles.
* **Compute Module:** Provisions EC2 instances (Amazon Linux 2023) with **IAM Instance Profiles**, removing the need for local AWS keys.
* **Database Module:** Provisions the RDS instance and integrates with AWS Secrets Manager.

### Key IaC Features
* **Remote State Management:** State is stored in S3 with DynamoDB locking to prevent concurrent modification.
* **Secrets Management:** Database credentials are securely stored in **AWS Secrets Manager**, fetched dynamically by Terraform.
* **Variables & Outputs:** Use of `terraform.tfvars` for environment-specific configurations.

---

## 🔒 Security & IAM
* **Least Privilege:** Each component has a specific IAM Role. The Worker can only `PutObject` to S3, `ReceiveMessage` from SQS, and `Publish` to SNS.
* **Security Groups:** 
    * `SG-Database`: Port 5432 restricted solely to `SG-Backend`.
    * `SG-Backend`: Port 5000 restricted solely to `SG-Frontend` (Private IP routing).
    * `SG-Frontend`: Port 80 open to the internet (`0.0.0.0/0`), Port 22 restricted to specific administrator IP.
* **Bastion Access:** Secure SSH access to private instances via the Frontend/Bastion host using the `avivPair-01.pem` key.

---

## 🚀 Operations & Deployment

### 1. Infrastructure Provisioning
```bash
cd Terraform
terraform init
terraform plan
terraform apply -var-file="terraform.tfvars"
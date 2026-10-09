# AWS DevOps Greenfield Lab
## Spring Boot → GitHub → Jenkins Multibranch → Maven → Docker → Docker Hub → Kubernetes on EC2 → Internet

Teach from the storyboard (`aws-springboot-devops-storyboard.drawio`). Execute from this runbook.
Every major section follows: **Context → Concept → Architecture → Lab → Verify → Production Thinking.**

---

### Values worksheet (fill in as you go)

| Placeholder | Meaning | Where it comes from |
|---|---|---|
| `<YOUR_IP>` | Your workstation's public IPv4 | `curl -s https://checkip.amazonaws.com` |
| `<VPC_ID>` | ID of `devops-lab-vpc` | §4 |
| `<KEY_FILE>` | `~/.ssh/devops-lab-key.pem` | §9 |
| `<JENKINS_PUBLIC_IP>` / `<JENKINS_PRIVATE_IP>` | EC2 #1 (Elastic IP / 10.0.1.x) | §9 |
| `<CP_PUBLIC_IP>` / `<CP_PRIVATE_IP>` | EC2 #2 | §9 |
| `<WORKER_PUBLIC_IP>` / `<WORKER_PRIVATE_IP>` | EC2 #3 (Elastic IP / 10.0.1.x) | §9 |
| `<GITHUB_USERNAME>` / `<GITHUB_PAT>` | GitHub account / fine-grained token | §13, §17 |
| `<DOCKERHUB_USERNAME>` / `<DOCKERHUB_TOKEN>` | Docker Hub account / access token | §16 |
| `<WEBHOOK_SECRET>` | Random string shared by GitHub and Jenkins | §23 |

### Versions and why they were chosen

| Component | Version | Reason / compatibility |
|---|---|---|
| OS | Ubuntu Server 24.04 LTS (x86_64) | Supported until 2029. Docker, Kubernetes and Jenkins all publish apt repositories for it. x86 avoids arm64 image mismatches. |
| Java | 21 (LTS) | Required by current Jenkins LTS. Supported by Spring Boot 4 (minimum Java 17). |
| Spring Boot | 4.0.x (use the newest 4.0.x patch from start.spring.io) | Current generation. Requires Java 17+ and Maven 3.6.3+. |
| Maven | 3.9.9 via Maven Wrapper (`./mvnw`) | Identical Maven on laptops and Jenkins. No apt Maven (Ubuntu's 3.8.x) needed. The Docker build stage uses `maven:3.9-eclipse-temurin-21`. |
| Jenkins | LTS from `pkg.jenkins.io/debian-stable` | Current signed repository with a keyring file (no `apt-key`). |
| Docker Engine | Current, from `download.docker.com` | Installed on the Jenkins EC2 only, for image builds. |
| Container runtime | containerd 2.x (`containerd.io`) | Kubernetes talks to containerd via CRI. Kubernetes is ending support for containerd 1.x, so we start on 2.x. |
| Kubernetes | v1.35 via `pkgs.k8s.io` | Community-owned repository (the old Google/`apt.kubernetes.io` repositories are gone). Use the same minor for kubeadm, kubelet, and kubectl. kubectl must be within ±1 minor of the API server. If a newer minor is current when you teach, change `K8S_MINOR` everywhere. |
| CNI | Calico v3.30.x manifest | Supports current Kubernetes releases. Simple single-manifest install. |

---

# 1. Architecture and Story

## Context
We start with an empty AWS account and finish with a public web application that redeploys itself every time a developer pushes to `main`. Students build **one system**, piece by piece.

## Concept
The system has seven phases (storyboard legend):

1. **AWS Foundation**: VPC, subnets, Internet Gateway, route tables, security groups.
2. **Application**: Java 21, Spring Boot, GitHub, branches.
3. **CI**: Jenkins Multibranch, Maven build and test.
4. **Containers**: Docker image, Docker Hub.
5. **Kubernetes**: control plane, worker, CNI, Deployment.
6. **Continuous Deployment**: webhook, `kubectl apply`, rolling update.
7. **User Access**: Internet → Internet Gateway → Service → Pods.

## Architecture

```
Developer ─git push─▶ GitHub (main / develop / feature/*)
                          │ webhook :8080
┌─ AWS us-east-1 ─ VPC 10.0.0.0/16 ──────────────────────────────────────────────┐
│  Internet Gateway ◀──▶ public-rt (0.0.0.0/0 → IGW)                              │
│  ┌─ Public subnet 10.0.1.0/24 (AZ a) ─────────────────────────┐  ┌─ Private ──┐│
│  │ [jenkins-sg]  EC2 #1 Jenkins: Multibranch→Maven→Docker→kubectl│  │10.0.11.0/24││
│  │ [k8s-nodes-sg] EC2 #2 control plane ◀─:6443─ kubectl         │  │ reserved   ││
│  │                EC2 #3 worker: Deployment (2 pods) + NodePort  │  │ (no NAT)   ││
│  └──────────────────────────────────────────────────────────────┘  └────────────┘│
└─────────────────────────────────────────────────────────────────────────────────┘
Jenkins ─docker push─▶ Docker Hub ─image pull─▶ worker
End user ─▶ http://<WORKER_PUBLIC_IP>:30080/api/hello
```

**Storyboard ↔ runbook map**

| Storyboard page | Runbook § |
|---|---|
| 00 | §1 |
| 01 VPC | §3–4 |
| 02 Subnets | §5 |
| 03 IGW + routes | §6–7 |
| 04 Security groups | §8 |
| 05 Jenkins EC2 | §9–10 |
| 06–08 Kubernetes (control plane, worker, CNI) | §9, §11 |
| 09 Spring Boot app | §12 |
| 10 GitHub | §13 |
| 11 Branches | §14 |
| 12 Multibranch | §17–18 |
| 13 Maven | §19 |
| 14 Docker | §15 |
| 15 Docker Hub | §16 |
| 16 Deployment | §17, §19 |
| 17 Service + Internet | §21 |
| 18 First deploy | §20 |
| 19 Code change | §22 |
| 20–23 Push → webhook → pipeline → v2 | §23 |
| 24 What we built | §25–27 |

### Key design decisions

| Decision | Choice for this lab | Why |
|---|---|---|
| Kubernetes | **Self-managed (kubeadm on EC2)** | The goal is understanding Jenkins → Docker → Kubernetes → AWS. kubeadm makes every link visible (nodes, ports, CNI, NodePort, kubeconfig). It is also cheaper and simpler to clean up. EKS is the follow-up lab (§26). |
| Availability Zones | One AZ (`us-east-1a`) | Single control plane and single worker give no HA anyway. Avoids cross-AZ data charges. CIDRs for a second AZ are reserved (§3). |
| Private subnet / NAT | Private subnet created but **empty**. **No NAT Gateway.** | A NAT Gateway costs about $0.045/hour plus data processing. All three instances need outbound Internet, so they live in the public subnet with tight security groups. The private subnet teaches the pattern and is reused in the EKS lab. |
| Jenkins builds | Run on the controller's built-in node | The 3-EC2 constraint. Accepted risk for a lab. Production uses separate ephemeral agents (§10). |
| Registry | Docker Hub (public repo) | No registry authentication needed on nodes. Production uses Amazon ECR (§25). |
| Exposure | NodePort 30080 on the worker's Elastic IP | No cloud controller is needed. `LoadBalancer` Services stay `<pending>` on plain kubeadm. Production uses an ALB. |
| Image tags | Git commit SHA (7 chars) | Unique and immutable. Every release changes the pod template, which forces a rollout (§23). |

### Review of the previous runbook and what this version fixes

| Area | Problem in the previous version | Fix in this version |
|---|---|---|
| AWS networking | Assumed the default VPC. No subnet, Internet Gateway or route table design. | Custom VPC, subnets, IGW and route tables built step by step (§3–7). |
| CIDR planning | No check for overlap between VPC, pod and service ranges. | VPC 10.0.0.0/16, pods 192.168.0.0/16, services 10.96.0.0/12. All disjoint (§3). |
| Public IPs | Public IPs changed on stop/start, breaking the webhook, Jenkins URL and app URL. Control-plane public IP was unexplained. | Elastic IPs for Jenkins and the worker. Control-plane public IP explained (egress without NAT; inbound blocked except SSH). |
| Instance hardening | EBS unencrypted, IMDSv1 allowed, no tags. | Encrypted gp3, IMDSv2 required, `Project=devops-lab` tag on everything. |
| Maven | Ubuntu apt Maven (3.8.x) on Jenkins vs Maven 3.9 in Docker. "Maven not found" risk. | Maven Wrapper pinned to 3.9.9, committed to the repo. |
| Jenkinsfile | Docker Hub user and worker IP hard-coded in the Jenkinsfile. | Environment-specific values moved to Jenkins global properties. The Jenkinsfile is portable. |
| Pipeline | Separate Package stage with `-DskipTests` after tests. | Test stage runs `./mvnw verify` once (tests + package). |
| Webhook | No shared secret, so anyone who can reach port 8080 can trigger scans. | HMAC shared secret (§23). |
| Tags | Manual `:1.0` deploy mixed with SHA tags. | SHA tags only. The cluster is proven with a throw-away nginx smoke test instead. |
| RBAC | Cluster-admin objects lived in the application repository. | Namespace and RBAC applied by the cluster admin on the control plane. The app repo contains only app manifests. |
| Rollout history | No change-cause, so the history was unreadable. | `kubernetes.io/change-cause` set by the pipeline. |
| Docker Hub limits | Anonymous pull limits not addressed. | Documented, with an optional pull-secret fix (§24). |
| Story | Webhook was configured before the first deployment. | First deployment is triggered manually. The webhook is introduced as "nobody should click Build" (§23), matching the storyboard. |
| Cleanup | VPC components were not covered. | Full teardown, including the VPC, with CLI verification (§27). |

## Lab
No lab steps in this section. Present storyboard page 00.

## Verify
Students can name the seven phases and point to where Jenkins, the control plane, the worker, and the pods live.

## Production Thinking
The lab trades high availability and security depth for visibility and cost. §25 lists every difference.

---

# 2. Prerequisites

## Context
Missing tools or accounts are the most common live-session blockers.

## Concept
You need three accounts (AWS, GitHub, Docker Hub) and a workstation that can build Java and Docker.

## Architecture
Developer laptop (storyboard left column) plus the AWS account (outer box).

## Lab

**Accounts**
- AWS account with administrator access.
- GitHub account.
- Docker Hub account (free tier is enough).

**Workstation tools.** On Windows, use WSL2 (Ubuntu) or Git Bash for all shell commands.

| Tool | Check | Expected |
|---|---|---|
| Git | `git --version` | 2.x |
| JDK 21 (Eclipse Temurin) | `java -version` | `21.x` |
| Maven 3.9+ (only to generate the wrapper once) | `mvn -v` | Java version 21 |
| Docker Desktop / Engine | `docker version` | Client and Server |
| curl, ssh | `curl --version; ssh -V` | versions |

**AWS permissions**
- **Lab:** sign in as an IAM Identity Center user (or IAM user) with `AdministratorAccess`, with MFA enabled. Never use the root user for the lab.
- **Services used:** VPC/EC2 (VPC, subnets, IGW, route tables, security groups, EIPs, instances, volumes, key pairs), AWS Budgets, AWS CloudShell.
- **Production:** do not keep `AdministratorAccess`. Use permission sets scoped to the job:
  - for example, EC2/VPC actions restricted with `aws:RequestedRegion` and tag conditions (`aws:ResourceTag/Project`);
  - no long-lived access keys;
  - separate roles for platform engineers, CI, and read-only auditors;
  - CloudTrail enabled.

**Account safety (once)**
1. Root user → **Security credentials** → assign MFA.
2. **Billing and Cost Management → Budgets → Create budget**:
   - Use a template → **Monthly cost budget**
   - Name `devops-lab-budget`, amount `20` USD, your email
   - **Create budget**.

## Verify
- All workstation checks pass.
- You can open **CloudShell** (terminal icon in the AWS Console top bar) and `aws sts get-caller-identity` returns your user.

## Production Thinking
Accounts are created through AWS Organizations with SCP guardrails. Budgets and anomaly detection are on by default.

---

# 3. AWS Region and CIDR Design

## Context
IP ranges are hard to change later. Overlaps with Kubernetes ranges break pod networking in confusing ways.

## Concept
- A **Region** is a geographic area with several isolated **Availability Zones** (AZs).
- A VPC lives in one Region. Each subnet lives in one AZ.
- CIDR notation `/16` gives 65,536 addresses and `/24` gives 256 (AWS reserves 5 per subnet).

## Architecture
Storyboard page 01: Account → Region → VPC.

## Lab

**Region:** `us-east-1` (or the Region closest to your students; use it for everything). Select it in the console's top-right Region selector.

**Address plan**

| Range | CIDR | Used for | Status |
|---|---|---|---|
| VPC | `10.0.0.0/16` | All AWS addresses | Created |
| Public subnet AZ a | `10.0.1.0/24` | Jenkins, control plane, worker | Created |
| Private subnet AZ a | `10.0.11.0/24` | Production/EKS pattern (no NAT) | Created, empty |
| Public subnet AZ b | `10.0.2.0/24` | Reserved for EKS lab / multi-AZ | Not created |
| Private subnet AZ b | `10.0.12.0/24` | Reserved for EKS lab / multi-AZ | Not created |
| Kubernetes pods | `192.168.0.0/16` | Calico pod IPs (overlay, not in VPC) | kubeadm flag |
| Kubernetes Services | `10.96.0.0/12` (kubeadm default) | ClusterIPs | Default |

**Why this plan works**
- `10.96.0.0/12` spans 10.96.0.0–10.111.255.255, which does not overlap `10.0.0.0/16`. `192.168.0.0/16` overlaps neither.
- A /16 leaves room for EKS later, where the VPC CNI gives every pod a VPC IP and consumes addresses quickly.
- Numbering scheme: 1–9 = public, 11–19 = private, so students can read a subnet's role from its third octet.

**NAT Gateway decision.** A NAT Gateway is only required when instances in a private subnet need outbound Internet. In this lab:
- every instance needs outbound access (apt, GitHub, Docker Hub, `registry.k8s.io`);
- Jenkins and the worker need inbound access;
- the control plane only needs outbound.

Moving the control plane behind a NAT Gateway would add a constant hourly charge plus data processing fees, for one instance. We keep it in the public subnet with a public IP used for egress, and its security group blocks all inbound Internet traffic except SSH from `<YOUR_IP>`.

**DNS considerations**
- The VPC needs **DNS resolution** (default on) and **DNS hostnames** (we enable it).
- Instances use the Amazon-provided resolver at the VPC base address plus two (`10.0.0.2`).
- Kubernetes uses its own CoreDNS for in-cluster names.
- We set short hostnames on the instances and add them to `/etc/hosts`.

## Verify
In CloudShell: `aws configure get region` (or `echo $AWS_REGION`) shows your Region.

## Production Thinking
- Use 2–3 AZs, with private subnets per AZ and NAT per AZ (or VPC endpoints).
- Plan CIDRs centrally (IPAM) so VPCs never overlap across accounts. Peering and Transit Gateway require that.

---

# 4. VPC

## Context
We need an isolated network for our DevOps platform.

## Concept
A VPC is our logical network boundary in AWS. Nothing can talk to it until we add gateways and routes.

## Architecture
Storyboard page 01 (highlighted VPC).

## Lab
1. **VPC console → Your VPCs → Create VPC**.
2. Resources to create: **VPC only** (we deliberately build each piece ourselves; don't use "VPC and more").
3. Name tag: `devops-lab-vpc`.
4. IPv4 CIDR block: **IPv4 CIDR manual input**, `10.0.0.0/16`.
5. IPv6 CIDR block: **No IPv6 CIDR block**. Tenancy: **Default**.
6. **Add new tag**: Key `Project`, Value `devops-lab` (repeat this tag on every resource in this lab).
7. **Create VPC**. Record `<VPC_ID>`.
8. Select the VPC → **Actions → Edit VPC settings** → check **Enable DNS resolution** and **Enable DNS hostnames** → **Save**.

## Verify
In CloudShell:

```bash
aws ec2 describe-vpcs --filters Name=tag:Name,Values=devops-lab-vpc \
  --query 'Vpcs[0].[VpcId,CidrBlock,State]' --output table
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsHostnames
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsSupport
```

Expected: `available`, `10.0.0.0/16`, and both attributes `"Value": true`.

## Production Thinking
- Enable VPC Flow Logs.
- Create the VPC with infrastructure as code (Terraform or CloudFormation), never by hand.

---

# 5. Subnets

## Context
Some machines must be reachable from the Internet, others never should be.

## Concept
- A subnet is a slice of the VPC in one AZ.
- **Public vs private is not a subnet setting.** It is decided by the route table (§7).
- "Auto-assign public IPv4" only controls whether instances launched there get a public address.

## Architecture
Storyboard page 02.

## Lab
1. **VPC console → Subnets → Create subnet**. VPC: `devops-lab-vpc`.
2. Subnet 1:
   - Name `devops-lab-public-a`
   - AZ `us-east-1a`
   - IPv4 subnet CIDR `10.0.1.0/24`
   - Tag `Project=devops-lab`
3. **Add new subnet**, Subnet 2:
   - Name `devops-lab-private-a`
   - AZ `us-east-1a`
   - CIDR `10.0.11.0/24`
   - Tag `Project=devops-lab`
4. **Create subnet**.
5. Select `devops-lab-public-a` → **Actions → Edit subnet settings** → check **Enable auto-assign public IPv4 address** → **Save**.

## Verify

```bash
aws ec2 describe-subnets --filters Name=vpc-id,Values=<VPC_ID> \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
```

Expected: the public subnet shows `True`, the private subnet shows `False`, and both are in `us-east-1a`.

## Production Thinking
- One public and one private subnet per AZ, in at least 2 AZs.
- Workloads go in private subnets. Only load balancers and NAT go in public subnets.

---

# 6. Internet Gateway

## Context
Before our EC2 instances can communicate with the Internet, our VPC needs a path to the Internet.

## Concept
An Internet Gateway (IGW) is a horizontally scaled, highly available VPC component. It connects the VPC to the Internet and translates instances' private IPs to their public IPs. There is no charge for the IGW itself.

## Architecture
Storyboard page 03 (Internet Gateway on the VPC edge).

## Lab
1. **VPC console → Internet gateways → Create internet gateway**.
2. Name `devops-lab-igw`, tag `Project=devops-lab` → **Create**.
3. **Actions → Attach to VPC** → `devops-lab-vpc` → **Attach internet gateway**.

## Verify

```bash
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=<VPC_ID> \
  --query 'InternetGateways[].[InternetGatewayId,Attachments[0].State]' --output table
```

Expected: `available` (the attachment state).

## Production Thinking
Same IGW pattern. Ingress goes through an ALB/WAF in the public subnets. Private workloads leave through NAT or VPC endpoints.

---

# 7. Route Tables

## Context
An attached IGW does nothing until a route sends traffic to it.

## Concept
A route table is a set of signposts: destination → target.
- Every route table has `10.0.0.0/16 → local` (traffic inside the VPC).
- A subnet whose table also has `0.0.0.0/0 → IGW` is **public**.
- We leave the VPC's **main** route table untouched (local only). Any future subnet that is not explicitly associated is then private by default.

## Architecture
Storyboard page 03 (route-table note).

## Lab

**Public route table**
1. **VPC console → Route tables → Create route table**.
2. Name `devops-lab-public-rt`, VPC `devops-lab-vpc`, tag `Project=devops-lab` → **Create**.
3. **Routes** tab → **Edit routes** → **Add route**:
   - Destination `0.0.0.0/0`
   - Target **Internet Gateway** → `devops-lab-igw`
   - **Save changes**.
4. **Subnet associations** tab → **Edit subnet associations** → check `devops-lab-public-a` → **Save associations**.

**Private route table**
1. **Create route table**: name `devops-lab-private-rt`, VPC `devops-lab-vpc`.
2. Leave only the `local` route. Do not add a NAT route.
3. **Subnet associations** → associate `devops-lab-private-a`.

Network ACLs: leave the default NACL (allows all). Security groups are our filter.

## Verify

```bash
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<VPC_ID> \
  --query 'RouteTables[].{Name:Tags[?Key==`Name`]|[0].Value,Routes:Routes[].[DestinationCidrBlock,GatewayId],Subnets:Associations[].SubnetId}'
```

Expected:
- `devops-lab-public-rt` has `0.0.0.0/0 → igw-...` and the public subnet ID.
- `devops-lab-private-rt` has only `local` and the private subnet ID.

## Production Thinking
- Private route tables point `0.0.0.0/0` at a NAT Gateway in the same AZ.
- Add gateway endpoints (S3, free) and interface endpoints (ECR, STS, CloudWatch) to reduce NAT traffic.

---

# 8. Security Groups

## Context
Our subnet is public. We must decide exactly who may talk to what. "Allow all" is never the answer.

## Concept
Security groups are **stateful** instance firewalls:
- **inbound rules** allow new connections in;
- replies are allowed automatically;
- outbound rules govern connections the instance starts.

A rule's source can be a CIDR or **another security group**, which means "any instance that carries that group."

## Architecture
Storyboard page 04 (dashed boxes around the future instances).

## Lab

### 8.1 Create `jenkins-sg`
1. **EC2 console → Security Groups → Create security group**.
2. Name `jenkins-sg`, description `Jenkins controller`, VPC `devops-lab-vpc`.
3. Inbound rules:

| # | Type | Protocol | Port | Source | Purpose | Lifetime |
|---|---|---|---|---|---|---|
| J1 | SSH | TCP | 22 | `<YOUR_IP>/32` | Administer the instance | Lab only (production: SSM, no port 22) |
| J2 | Custom TCP | TCP | 8080 | `<YOUR_IP>/32` | Jenkins web UI | Lab only (production: HTTPS via ALB + SSO) |
| J3 | Custom TCP | TCP | 8080 | GitHub hook CIDRs | GitHub webhooks | **Temporary**, added in §23 |

4. Outbound: keep the default rule (see 8.3).
5. Tag `Project=devops-lab` → **Create security group**.

### 8.2 Create `k8s-nodes-sg`
1. **Create security group**: name `k8s-nodes-sg`, description `Kubernetes nodes`, VPC `devops-lab-vpc`.
2. Add only rule K1 → **Create**. The other rules reference this group, so it must exist first.
3. Select it → **Inbound rules → Edit inbound rules** → add the rest:

| # | Type | Protocol | Port | Source | Purpose | Lifetime |
|---|---|---|---|---|---|---|
| K1 | SSH | TCP | 22 | `<YOUR_IP>/32` | Administer nodes | Lab only |
| K2 | Custom TCP | TCP | 6443 | `k8s-nodes-sg` (self) | kubelet → API server | Permanent |
| K3 | Custom TCP | TCP | 6443 | `jenkins-sg` | Jenkins `kubectl` → API server | Permanent |
| K4 | Custom TCP | TCP | 10250 | `k8s-nodes-sg` (self) | API server → kubelet (logs, exec) | Permanent |
| K5 | Custom TCP | TCP | 179 | `k8s-nodes-sg` (self) | Calico BGP peering | Permanent |
| K6 | Custom protocol | 4 (IP-in-IP) | all | `k8s-nodes-sg` (self) | Calico pod traffic between nodes | Permanent |
| K7 | Custom TCP | TCP | 30080 | `0.0.0.0/0` | Public application NodePort | **Temporary demo rule** (production: ALB only) |

4. **Save rules**.

Ports **not** opened (and why):
- etcd 2379–2380, controller manager 10257, and scheduler 10259 listen on localhost in a single-control-plane cluster.
- The full NodePort range 30000–32767 is not opened; only 30080 is used.

### 8.3 Outbound rules
- All instances must start connections to apt mirrors (80/443), GitHub, Docker Hub, `pkgs.k8s.io`, `registry.k8s.io`, and each other.
- The default "all outbound" rule is kept for the lab, because a missing egress rule produces silent timeouts mid-demo.
- A hardened version would be: TCP 80 and 443 to `0.0.0.0/0`; on `jenkins-sg`, TCP 6443 and 30080 to `k8s-nodes-sg`; on `k8s-nodes-sg`, TCP 6443, 10250, 179 and protocol 4 to itself.
- Traffic to the Amazon DNS resolver and Amazon Time Sync is not filtered by security groups.

## Verify

```bash
aws ec2 describe-security-groups --filters Name=vpc-id,Values=<VPC_ID> \
  --query 'SecurityGroups[].{Name:GroupName,Id:GroupId,In:IpPermissions[].[IpProtocol,FromPort,ToPort]}'
```

You should see 2 rules on `jenkins-sg` and 7 on `k8s-nodes-sg`, plus the VPC's `default` group.

## Production Thinking
- No SSH; use SSM Session Manager.
- No NodePort exposure; the ALB security group is the only source allowed to reach the nodes.
- Kubernetes NetworkPolicies restrict pod-to-pod traffic.
- Security groups are managed as code and reviewed.

---

# 9. EC2 Instances

## Context
The network is ready. Now we place servers into it.

## Concept

| | EC2 #1 | EC2 #2 | EC2 #3 |
|---|---|---|---|
| Name / hostname | `jenkins` | `k8s-control-plane` | `k8s-worker-1` |
| Role | Jenkins controller + build executor | Kubernetes control plane | Kubernetes worker |
| Type | `t3.large` (2 vCPU, 8 GiB): Jenkins JVM + Maven + Docker builds | `t3.medium` (2 vCPU, 4 GiB): kubeadm needs ≥2 vCPU / 2 GiB | `t3.medium`: app pods + system pods + rolling-update surge |
| AMI | Ubuntu Server 24.04 LTS, 64-bit (x86) | same | same |
| Disk | 30 GiB gp3, encrypted | 20 GiB gp3, encrypted | 20 GiB gp3, encrypted |
| Subnet | `devops-lab-public-a` | same | same |
| Security group | `jenkins-sg` | `k8s-nodes-sg` | `k8s-nodes-sg` |
| Public IP | **Elastic IP** (webhook + UI URL must stay stable) | Auto-assigned (egress only) | **Elastic IP** (application URL must stay stable) |
| Private IP | 10.0.1.x | 10.0.1.x (Kubernetes API address) | 10.0.1.x |

**Jenkins controller or separate agent?**
- A separate agent is better: builds run untrusted code (tests, Maven plugins, Dockerfiles) and should not share a machine with the controller's credentials and configuration.
- With the 3-EC2 constraint, the lab runs builds on the controller's built-in node and accepts that risk.
- Production: controller with **0 executors**, plus ephemeral agents (EC2 or Kubernetes pods) created per build.

## Architecture
Storyboard pages 05–07 (the three EC2 boxes appear inside their security groups).

## Lab

### 9.1 Key pair
1. **EC2 → Key Pairs → Create key pair**: name `devops-lab-key`, type RSA, format `.pem` → **Create**.
2. On your workstation:

```bash
mkdir -p ~/.ssh && mv ~/Downloads/devops-lab-key.pem ~/.ssh/ && chmod 400 ~/.ssh/devops-lab-key.pem
```

### 9.2 Launch the three instances
Repeat for each row of the table above.

1. **EC2 → Instances → Launch instances**.
2. **Name**: `jenkins`. Click **Add additional tags** → `Project=devops-lab`.
3. **AMI**: Quick Start → Ubuntu → **Ubuntu Server 24.04 LTS (HVM), SSD Volume Type**, Architecture **64-bit (x86)**.
4. **Instance type**: `t3.large` (or `t3.medium` for the Kubernetes nodes).
5. **Key pair**: `devops-lab-key`.
6. **Network settings → Edit**:
   - VPC `devops-lab-vpc`
   - Subnet `devops-lab-public-a`
   - Auto-assign public IP **Enable**
   - Firewall: **Select existing security group** → `jenkins-sg` (or `k8s-nodes-sg`).
7. **Configure storage**: 30 GiB (or 20) **gp3**. Click **Advanced** → Encrypted **Yes** (KMS key: default `aws/ebs`).
8. **Advanced details**: Metadata version **V2 only (token required)**.
9. **Launch instance**.

Wait for **Running** and **3/3 status checks passed**. Record the private IPs.

### 9.3 Elastic IPs (Jenkins and worker)
1. **EC2 → Elastic IPs → Allocate Elastic IP address** → tag `Name=devops-lab-jenkins-eip`, `Project=devops-lab` → **Allocate**.
2. **Actions → Associate Elastic IP address** → Instance `jenkins` → **Associate**.
3. Repeat with `devops-lab-worker-eip` → `k8s-worker-1`.
4. Record `<JENKINS_PUBLIC_IP>`, `<WORKER_PUBLIC_IP>`, and `<CP_PUBLIC_IP>`.

### 9.4 SSH and OS preparation (all three)

```bash
ssh -i ~/.ssh/devops-lab-key.pem ubuntu@<JENKINS_PUBLIC_IP>   # tab 1
ssh -i ~/.ssh/devops-lab-key.pem ubuntu@<CP_PUBLIC_IP>        # tab 2
ssh -i ~/.ssh/devops-lab-key.pem ubuntu@<WORKER_PUBLIC_IP>    # tab 3
```

Set the hostname, using the matching name on each instance:

```bash
sudo hostnamectl set-hostname jenkins            # EC2 #1
sudo hostnamectl set-hostname k8s-control-plane  # EC2 #2
sudo hostnamectl set-hostname k8s-worker-1       # EC2 #3
```

On all three:

```bash
cat <<EOF | sudo tee -a /etc/hosts
<JENKINS_PRIVATE_IP>  jenkins
<CP_PRIVATE_IP>       k8s-control-plane
<WORKER_PRIVATE_IP>   k8s-worker-1
EOF

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
sudo apt-get install -y ca-certificates curl gnupg git jq vim
sudo install -m 0755 -d /etc/apt/keyrings
[ -f /var/run/reboot-required ] && sudo reboot
```

Reconnect after a reboot.

## Verify
On each instance (this proves the whole network path built in §4–8):

```bash
hostname                                   # expected name
ip -4 addr show | grep 'inet 10.0.1'       # private IP in the public subnet
resolvectl status | grep 'DNS Servers'     # 10.0.0.2 (Amazon-provided DNS)
getent hosts github.com                    # DNS resolution works
curl -sI https://github.com | head -1      # HTTP/2 200 → IGW + route table OK
getent hosts k8s-control-plane             # /etc/hosts entry
```

From the workstation, SSH works for all three. This proves security group rules J1/K1, the public IPs, and the IGW route.

## Production Thinking
- Instances in private subnets with no public IPs, launched from hardened AMIs through launch templates or Auto Scaling groups.
- Access through SSM with an instance profile (`AmazonSSMManagedInstanceCore`).
- No key pairs.

---

# 10. Jenkins

## Context
We need the automation server that will turn every commit into a running release.

## Concept
- The **Jenkins Controller** serves the UI, stores jobs and credentials, schedules builds, and receives webhooks.
- A **Jenkins Agent** executes build steps.
- In this lab the controller's **built-in node** acts as the agent, so it needs Java, Docker, and kubectl. Maven comes from the project's wrapper.

## Architecture
Storyboard page 05. Everything in this section runs on **EC2 #1 `jenkins`**.

## Lab

### 10.1 Java 21

```bash
sudo apt-get install -y fontconfig openjdk-21-jdk
java -version
```

### 10.2 Jenkins LTS

```bash
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install -y jenkins
sudo systemctl enable --now jenkins
```

> The Jenkins project rotates its repository signing key. If `apt-get update` shows `NO_PUBKEY` for `pkg.jenkins.io`, copy the current key URL from https://www.jenkins.io/doc/book/installing/linux/ (Debian/Ubuntu → LTS) and rerun the `wget` line.

### 10.3 Docker Engine (for image builds)

```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

The `docker` group is root-equivalent. That is acceptable on a dedicated lab CI host and is one more reason production uses isolated agents.

### 10.4 kubectl (same minor version as the cluster)

```bash
K8S_MINOR=v1.35
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl && sudo apt-mark hold kubectl
```

### 10.5 Setup wizard
1. Get the initial password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
2. Browse to `http://<JENKINS_PUBLIC_IP>:8080` (allowed only from `<YOUR_IP>` by rule J2).
3. Paste the password → **Continue** → **Install suggested plugins**. This includes Git, GitHub Branch Source, Pipeline, Credentials Binding, JUnit, and Timestamper.
4. **Create First Admin User**: use a strong password.
5. **Instance Configuration**: Jenkins URL `http://<JENKINS_PUBLIC_IP>:8080/` → **Save and Finish**.
6. **Manage Jenkins → Plugins → Available plugins** → install **Pipeline Graph View** → restart when idle.
7. **Manage Jenkins → Nodes → Built-In Node → Configure**: Number of executors **2** → **Save**. Jenkins will show a warning about building on the built-in node. That is the documented lab trade-off.
8. **Manage Jenkins → Security**: Jenkins' own user database; **Logged-in users can do anything**; anonymous read **unchecked**.

## Verify

```bash
systemctl is-active jenkins docker              # active active
sudo -u jenkins java -version                   # 21
sudo -u jenkins docker run --rm hello-world     # "Hello from Docker!"
sudo -u jenkins kubectl version --client        # v1.35.x
sudo -u jenkins git --version
```

The Jenkins dashboard loads in the browser.

## Production Thinking
- Jenkins sits behind an ALB with HTTPS and SSO.
- Configuration as Code (JCasC) and pinned plugins.
- `JENKINS_HOME` backed up or on EFS.
- Built-in executors set to 0, with ephemeral agents.

---

# 11. Kubernetes

## Context
We will run the application on Kubernetes, so we build a 2-node cluster with kubeadm.

## Concept

| Component | What it does |
|---|---|
| **containerd** | Container runtime. Kubernetes talks to it through CRI. |
| **kubelet** | Node agent. Turns pod specs into running containers and reports status. |
| **kubeadm** | One-time bootstrapper: certificates, control-plane static pods, node joining. |
| **kubectl** | Client for the API server. |
| **API server** (:6443) | The single front door. Validates requests and stores state in **etcd**. |
| **Scheduler** | Picks a node for each new pod. |
| **Controller manager** | Reconciliation loops (for example, "2 replicas desired, 1 running → create one"). |
| **kube-proxy** | Programs iptables rules that implement Services and NodePorts. |
| **Calico (CNI)** | Gives pods IPs and routes pod traffic between nodes (BGP + IP-in-IP). |

## Architecture
Storyboard pages 06 (control plane), 07 (worker), 08 (Calico).

## Lab

### 11.1 On BOTH Kubernetes nodes

```bash
# Swap off (kubelet requirement)
sudo swapoff -a && sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab

# Kernel modules + sysctls for container networking
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# containerd 2.x from Docker's repository
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update && sudo apt-get install -y containerd.io

# Full default config (re-enables CRI) + systemd cgroup driver
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -n 'SystemdCgroup' /etc/containerd/config.toml     # must print: SystemdCgroup = true
sudo systemctl restart containerd && sudo systemctl enable containerd

# kubeadm, kubelet, kubectl from pkgs.k8s.io
K8S_MINOR=v1.35
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# crictl config for debugging
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' \
  | sudo tee /etc/crictl.yaml
```

If `grep SystemdCgroup` prints nothing:
1. Edit `/etc/containerd/config.toml`.
2. Find the section header ending in `runtimes.runc.options]`.
3. Add `SystemdCgroup = true` below it.
4. Restart containerd.

kubelet restarting in a loop is normal until `init`/`join`.

### 11.2 Initialize the control plane (`k8s-control-plane` only)

```bash
sudo kubeadm config images pull
sudo kubeadm init \
  --apiserver-advertise-address=<CP_PRIVATE_IP> \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name=k8s-control-plane

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Copy the printed `kubeadm join ...` command into your worksheet. A warning about the sandbox (pause) image version is harmless.

### 11.3 Install Calico (`k8s-control-plane`)
Use the newest v3.30.x tag listed at https://github.com/projectcalico/calico/releases.

```bash
CALICO_VERSION=v3.30.0
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml
kubectl get pods -n kube-system -w        # wait for calico-node + coredns Running, then Ctrl+C
```

### 11.4 Join the worker (`k8s-worker-1`)

```bash
sudo kubeadm join <CP_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

If the join command is lost or expired, run on the control plane: `kubeadm token create --print-join-command`.

On the control plane:

```bash
kubectl label node k8s-worker-1 node-role.kubernetes.io/worker=
```

### 11.5 Cluster smoke test (proves CNI, DNS, NodePort and security groups end to end)

```bash
kubectl run nettest --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default
kubectl create deployment smoke --image=nginx:1.27
kubectl create service nodeport smoke --tcp=80:80 --node-port=30080
kubectl rollout status deployment/smoke
```

From your workstation, `curl -s http://<WORKER_PUBLIC_IP>:30080 | grep -i title` should return `<title>Welcome to nginx!</title>`.

Then free the port for our application:

```bash
kubectl delete service smoke && kubectl delete deployment smoke
```

## Verify

```bash
kubectl get nodes -o wide
```

```
NAME                STATUS   ROLES           VERSION    INTERNAL-IP
k8s-control-plane   Ready    control-plane   v1.35.x    <CP_PRIVATE_IP>
k8s-worker-1        Ready    worker          v1.35.x    <WORKER_PRIVATE_IP>
```

```bash
kubectl get pods -n kube-system     # all Running
```

## Production Thinking
- Amazon EKS: a managed multi-AZ control plane with no etcd to back up.
- Managed node groups or Karpenter across AZs.
- Pods get VPC IPs via the VPC CNI.
- Upgrades are API calls rather than manual kubeadm work.

---

# 12. Spring Boot Application

## Context
The platform is ready. Now we need something to deliver.

## Concept
A REST API with one endpoint, `GET /api/hello`. It returns the message, the version, and the hostname (the pod name in Kubernetes, so students can see load balancing). Actuator health endpoints feed the Kubernetes probes.

## Architecture
Storyboard page 09 (developer + laptop).

## Lab
On your workstation:

```bash
mkdir -p ~/aws-springboot-devops && cd ~/aws-springboot-devops
mkdir -p src/main/java/com/example/devops src/main/resources src/test/java/com/example/devops
```

**`pom.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>4.0.0</version>
        <relativePath/>
    </parent>

    <groupId>com.example</groupId>
    <artifactId>aws-springboot-devops</artifactId>
    <version>1.0.0</version>
    <name>aws-springboot-devops</name>

    <properties>
        <java.version>21</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-webmvc</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <finalName>app</finalName>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

(On Spring Boot 3.5.x, use `spring-boot-starter-web` instead of `spring-boot-starter-webmvc`.)

**`src/main/java/com/example/devops/AwsSpringbootDevopsApplication.java`**

```java
package com.example.devops;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AwsSpringbootDevopsApplication {
    public static void main(String[] args) {
        SpringApplication.run(AwsSpringbootDevopsApplication.class, args);
    }
}
```

**`src/main/java/com/example/devops/HelloController.java`**

```java
package com.example.devops;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class HelloController {

    // Change this to "2" in the live demo (§22)
    static final String VERSION = "1";

    @GetMapping("/hello")
    public Map<String, String> hello() {
        Map<String, String> response = new LinkedHashMap<>();
        response.put("message", "Hello from AWS DevOps Pipeline - Version " + VERSION);
        response.put("version", VERSION);
        response.put("hostname", resolveHostname());   // pod name in Kubernetes
        return response;
    }

    private String resolveHostname() {
        String hostname = System.getenv("HOSTNAME");
        if (hostname != null && !hostname.isBlank()) {
            return hostname;
        }
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
```

**`src/main/resources/application.properties`**

```properties
spring.application.name=aws-springboot-devops
server.port=8080
server.shutdown=graceful
management.endpoints.web.exposure.include=health,info
management.endpoint.health.probes.enabled=true
```

**`src/test/java/com/example/devops/AwsSpringbootDevopsApplicationTests.java`**

```java
package com.example.devops;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class AwsSpringbootDevopsApplicationTests {
    @Test
    void contextLoads() {
    }
}
```

**`src/test/java/com/example/devops/HelloControllerTest.java`**

```java
package com.example.devops;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;

class HelloControllerTest {

    @Test
    void messageContainsTheCurrentVersion() {
        Map<String, String> response = new HelloController().hello();

        assertThat(response.get("version")).isNotBlank();
        assertThat(response.get("message"))
            .isEqualTo("Hello from AWS DevOps Pipeline - Version " + response.get("version"));
        assertThat(response).containsKey("hostname");
    }
}
```

**Maven Wrapper.** Pins Maven 3.9.9 for everyone, including Jenkins:

```bash
mvn -N wrapper:wrapper -Dmaven=3.9.9
./mvnw -v                    # Apache Maven 3.9.9, Java version: 21
```

Build, test, and run:

```bash
./mvnw -B clean compile
./mvnw -B test               # Tests run: 2, Failures: 0 → BUILD SUCCESS
./mvnw -B package            # target/app.jar
java -jar target/app.jar     # Ctrl+C to stop
```

On Windows outside WSL, use `mvnw.cmd`.

## Verify
In a second terminal:

```bash
curl -s http://localhost:8080/api/hello
curl -s http://localhost:8080/actuator/health/readiness
```

```json
{"message":"Hello from AWS DevOps Pipeline - Version 1","version":"1","hostname":"my-laptop"}
{"status":"UP"}
```

`/` returns a 404 Whitelabel page. That is expected.

## Production Thinking
- Externalized configuration (environment variables, ConfigMaps, Secrets Manager).
- Structured JSON logs, metrics via Micrometer, and wider test coverage (integration and contract tests).

---

# 13. GitHub

## Context
Code that lives on one laptop can't be reviewed, built, or automated.

## Concept
GitHub is the single source of truth. Jenkins never builds from a laptop; it builds commits.

## Architecture
Storyboard page 10.

## Lab
1. GitHub → **+ → New repository**:
   - Name `aws-springboot-devops`, **Public**
   - Do **not** add a README, .gitignore, or license (we push an existing folder)
   - **Create repository**.
2. In the project folder, create **`.gitignore`**:

```gitignore
target/
.idea/
*.iml
.vscode/
.DS_Store
*.log
*.pem
*kubeconfig*
.env
```

3. Create **`README.md`**:

```markdown
# aws-springboot-devops
Spring Boot API delivered by a Jenkins Multibranch Pipeline to Kubernetes on AWS.
`GET /api/hello`
```

4. Initialize and push only the README and .gitignore to `main` (the application arrives through a feature branch in §14):

```bash
git config --global user.name "<YOUR_NAME>"
git config --global user.email "<YOUR_EMAIL>"
git init -b main
git add .gitignore README.md
git commit -m "Initial commit: README and .gitignore"
git remote add origin https://github.com/<GITHUB_USERNAME>/aws-springboot-devops.git
git push -u origin main
```

When prompted for a password, use a GitHub personal access token with **Contents: Read and write** for your own pushes, or authenticate with `gh auth login`.

## Verify
- `git status` shows `pom.xml`, `mvnw`, `.mvn/`, and `src/` as untracked.
- The GitHub page shows README and .gitignore on `main`.

## Production Thinking
- Organization-owned private repositories with branch protection, required reviews, required status checks (Jenkins), signed commits, and secret scanning.

---

# 14. Git Branching

## Context
Several people change code at once, and production must stay stable.

## Concept

| Branch | Purpose | What the pipeline does |
|---|---|---|
| `feature/*` | One unit of work, created from `develop` | Build, test, Docker build: fast feedback, nothing published |
| `develop` | Integration of finished features | Same as feature, plus **push the image** to Docker Hub |
| `main` | What runs in production; only receives merges from `develop` | Same as develop, plus **deploy** to Kubernetes and verify |

## Architecture
Storyboard page 11.

## Lab

```bash
git checkout -b develop && git push -u origin develop
git checkout -b feature/initial-api
chmod +x mvnw
git add pom.xml mvnw mvnw.cmd .mvn src
git commit -m "Add Spring Boot hello API, tests and Maven wrapper"
git push -u origin feature/initial-api
```

Merge into `develop`. Either:
- open a pull request on GitHub (base `develop` ← compare `feature/initial-api` → **Merge**), or
- merge on the command line:

```bash
git checkout develop
git merge --no-ff feature/initial-api -m "Merge feature/initial-api into develop"
git push origin develop
```

If you committed from Windows, run `git update-index --chmod=+x mvnw` before committing, so Linux runners can execute the wrapper.

## Verify

```bash
git branch -a
git log --oneline --graph --all -n 10
git ls-files -s mvnw      # mode 100755 = executable
```

`main` intentionally contains only README and .gitignore for now.

## Production Thinking
- Protect `main` (pull requests and passing checks only).
- Many teams use trunk-based development with short-lived feature branches and feature flags instead of a long-lived `develop`.

---

# 15. Docker

## Context
Kubernetes runs containers, not JAR files.

## Concept
- **Dockerfile** = the recipe.
- **Image** = the built, versioned, read-only package.
- **Container** = a running instance of an image.

A multi-stage build compiles with a full JDK and Maven, then ships only the JRE and the JAR, running as a non-root user.

## Architecture
Storyboard page 14 (Docker build inside Jenkins).

## Lab
Infrastructure files (Dockerfile, Kubernetes manifests, Jenkinsfile) go on one feature branch:

```bash
git checkout develop && git pull
git checkout -b feature/ci-cd-pipeline
```

**`Dockerfile`**

```dockerfile
# ---------- Stage 1: build ----------
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline     # cached dependency layer
COPY src ./src
RUN mvn -B -ntp package -DskipTests       # tests already ran in the pipeline's Test stage

# ---------- Stage 2: runtime ----------
FROM eclipse-temurin:21-jre
WORKDIR /app
RUN groupadd --system spring && useradd --system --gid spring --no-create-home spring
COPY --from=build /workspace/target/app.jar /app/app.jar
USER spring:spring
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

**`.dockerignore`**

```
target/
.git/
.idea/
.vscode/
k8s/
Jenkinsfile
*.md
```

What each part does:
- `FROM maven…` (base image with Maven and JDK 21) builds without needing Java on the host.
- `dependency:go-offline` caches dependencies, so code-only changes rebuild quickly.
- `package` creates the executable `app.jar`.
- `FROM eclipse-temurin:21-jre` is a small runtime with no compiler.
- `USER spring` means the app does not run as root.
- `EXPOSE` only documents the port.
- `ENTRYPOINT` in exec form makes Java PID 1, so it receives SIGTERM and shuts down gracefully.

Build and run locally:

```bash
docker build -t aws-springboot-devops:local .
docker run -d --name app-local -p 8080:8080 aws-springboot-devops:local
curl -s http://localhost:8080/api/hello
docker rm -f app-local
```

## Verify
- curl returns the Version 1 JSON (hostname = container ID).
- `docker image inspect aws-springboot-devops:local --format '{{.Config.User}}'` prints `spring:spring`.

## Production Thinking
- Pin base images by digest.
- Scan images (Trivy, ECR scanning) and generate SBOMs.
- Use distroless or minimal bases where possible.
- Build with remote cache on isolated builders.

---

# 16. Docker Hub

## Context
The worker can't see images that only exist on the Jenkins server.

## Concept
A container registry stores versioned images. Kubernetes nodes pull from it. Jenkins authenticates with an **access token**, never a password.

## Architecture
Storyboard page 15.

## Lab
1. hub.docker.com → **Repositories → Create a repository**:
   - Namespace `<DOCKERHUB_USERNAME>`
   - Name `aws-springboot-devops`
   - **Public** → **Create**.
2. Avatar → **Account settings → Personal access tokens → Generate new token**:
   - Description `jenkins-aws-lab`
   - Expiration 30 days
   - Permissions **Read & Write** → **Generate**
   - Copy the token as `<DOCKERHUB_TOKEN>`.
3. Test the login and push from your laptop:

```bash
docker login -u <DOCKERHUB_USERNAME>                       # paste the token
docker tag aws-springboot-devops:local <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test
docker push <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test
```

On Apple Silicon, build for the x86 nodes instead:

```bash
docker buildx build --platform linux/amd64 \
  -t <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test --push .
```

## Verify

```bash
docker rmi <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test
docker pull <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test
docker image inspect <DOCKERHUB_USERNAME>/aws-springboot-devops:manual-test --format '{{.Architecture}}'   # amd64
```

The Docker Hub **Tags** tab shows `manual-test`. The pipeline will only ever deploy commit-SHA tags.

## Production Thinking
- Amazon ECR (private) with IAM authentication, tag immutability, scan-on-push, and lifecycle policies.
- Nodes pull through VPC endpoints without public Internet access.

---

# 17. Jenkins Credentials

## Context
The pipeline must talk to GitHub, Docker Hub, and Kubernetes without any secret appearing in code or logs.

## Concept
Jenkins stores secrets encrypted. The pipeline references them by **ID**. `withCredentials` injects them only for the duration of a block and masks them in logs.

## Architecture
Storyboard pages 12, 15, and 16 (arrows from Jenkins to GitHub, Docker Hub, and the API server).

## Lab

### 17.1 GitHub fine-grained token
GitHub → avatar → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**:
- Name `jenkins-aws-lab`, expiry 30 days
- **Only select repositories** → `aws-springboot-devops`
- Permissions:
  - Contents: **Read-only**
  - Metadata: **Read-only**
  - Commit statuses: **Read and write**
  - Pull requests: **Read-only**
- **Generate** and copy it as `<GITHUB_PAT>`. If fine-grained tokens are blocked in your organization, use a classic token with the `repo` scope.

### 17.2 Kubernetes identity for Jenkins (on `k8s-control-plane`, as cluster admin)
Admin-level objects stay out of the application repository.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: springboot-app
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: springboot-app
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deployer
  namespace: springboot-app
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deployer
  namespace: springboot-app
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: springboot-app
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-deployer
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: springboot-app
  annotations:
    kubernetes.io/service-account.name: jenkins-deployer
type: kubernetes.io/service-account-token
EOF
```

Build a kubeconfig that uses this identity:

```bash
API_SERVER="https://<CP_PRIVATE_IP>:6443"
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
TOKEN=$(kubectl get secret jenkins-deployer-token -n springboot-app -o jsonpath='{.data.token}' | base64 -d)
cat > ~/jenkins-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: lab-cluster
    cluster:
      server: ${API_SERVER}
      certificate-authority-data: ${CA_DATA}
users:
  - name: jenkins-deployer
    user:
      token: ${TOKEN}
contexts:
  - name: jenkins-deployer@lab-cluster
    context:
      cluster: lab-cluster
      user: jenkins-deployer
      namespace: springboot-app
current-context: jenkins-deployer@lab-cluster
EOF
chmod 600 ~/jenkins-kubeconfig.yaml

kubectl --kubeconfig ~/jenkins-kubeconfig.yaml get pods -n springboot-app   # "No resources found" = OK
kubectl --kubeconfig ~/jenkins-kubeconfig.yaml get nodes                    # Forbidden = correct
```

Copy the file to your laptop for upload. Delete all copies after step 17.3:

```bash
scp -i ~/.ssh/devops-lab-key.pem ubuntu@<CP_PUBLIC_IP>:~/jenkins-kubeconfig.yaml .
```

### 17.3 Add the credentials in Jenkins
Path for each: **Manage Jenkins → Credentials → System → Global credentials (unrestricted) → Add Credentials**.

| ID | Kind | Fields | Used by |
|---|---|---|---|
| `github-creds` | Username with password | Username `<GITHUB_USERNAME>`, Password `<GITHUB_PAT>` | Multibranch branch source (scan, clone, commit status) |
| `dockerhub-creds` | Username with password | Username `<DOCKERHUB_USERNAME>`, Password `<DOCKERHUB_TOKEN>` | Docker Push stage |
| `k8s-kubeconfig` | Secret file | Upload `jenkins-kubeconfig.yaml` | Kubernetes Deploy + Verify stages |

Then remove the copies:

```bash
rm jenkins-kubeconfig.yaml
ssh -i ~/.ssh/devops-lab-key.pem ubuntu@<CP_PUBLIC_IP> 'rm ~/jenkins-kubeconfig.yaml'
```

### 17.4 Environment values (not secrets) as Jenkins global properties
These keep the Jenkinsfile free of environment-specific values.

**Manage Jenkins → System → Global properties** → check **Environment variables** → **Add**:

| Name | Value |
|---|---|
| `DOCKERHUB_REPO` | `<DOCKERHUB_USERNAME>/aws-springboot-devops` |
| `APP_URL` | `http://<WORKER_PRIVATE_IP>:30080/api/hello` |

**Save**.

## Verify
- **Manage Jenkins → Credentials** lists three IDs, and their secrets are not displayed.
- On the Jenkins host, `nc -zv <CP_PRIVATE_IP> 6443` succeeds (security group rule K3).

## Production Thinking
- Short-lived credentials only. Jenkins assumes an IAM role (instance profile or OIDC).
- EKS access entries map that role to namespace-scoped RBAC.
- Registry access through IAM (ECR).
- Remaining secrets in AWS Secrets Manager via the Jenkins AWS Secrets Manager credentials provider.

---

# 18. Jenkins Multibranch Pipeline

## Context
We want every branch built automatically, without creating jobs by hand.

## Concept
- A normal Pipeline job = one branch, configured by hand.
- A **Multibranch Pipeline** points at a repository. It **scans** it, creates one child job per branch that contains a `Jenkinsfile`, and runs that branch's own Jenkinsfile. It removes jobs for deleted branches.

```
GitHub repo ──┬── main
              ├── develop
              └── feature/*
                     │
        Multibranch: branch discovery → Jenkinsfile → one job per branch
```

**What happens when a developer creates `feature/login` and pushes:**
1. GitHub sends a push/create event (webhook, §23), or the periodic scan finds the branch.
2. Jenkins sees a new branch with a Jenkinsfile and creates job `feature%2Flogin` (the slash is URL-encoded).
3. That job runs Checkout → Maven Build → Test → Docker Build. Push and deploy are skipped because of the branch rules in the Jenkinsfile.
4. Every later push to `feature/login` triggers that job again.
5. When the branch is deleted, Jenkins removes its job (orphaned item strategy).

## Architecture
Storyboard page 12.

## Lab
1. Jenkins → **New Item**: name `aws-springboot-devops` → **Multibranch Pipeline** → **OK**.
2. **Branch Sources → Add source → GitHub**:
   - Credentials: `github-creds`
   - Repository HTTPS URL: `https://github.com/<GITHUB_USERNAME>/aws-springboot-devops`
   - **Validate** → expect `Credentials ok. Connected to …`
3. **Behaviours**:
   - **Discover branches** → Strategy **All branches**. The default "exclude branches filed as PRs" hides feature branches once a pull request exists.
   - Remove **Discover pull requests from origin** and **Discover pull requests from forks** (X button). This keeps one build per push for the lab.
   - **Add → Filter by name (with wildcards)** → Include `main develop feature/*`.
4. **Build Configuration**: Mode **by Jenkinsfile**, Script Path `Jenkinsfile`.
5. **Scan Multibranch Pipeline Triggers**: **Periodically if not otherwise run**, interval **1 hour** (the safety net; webhooks come in §23).
6. **Orphaned Item Strategy**: **Discard old items**, max 5.
7. **Save**. The first scan runs.

## Verify
The Scan Repository Log shows `'Jenkinsfile' not found` for every branch, and no child jobs. That is correct: no Jenkinsfile, no pipeline.

## Production Thinking
- Use a GitHub App instead of a personal token (higher API limits, no personal dependency).
- Enable PR discovery with status checks required by branch protection.
- Use folder-scoped credentials per team.

---

# 19. Jenkinsfile

## Context
The pipeline definition lives with the code and evolves with it.

## Concept
- A declarative pipeline with seven stages. `when { branch … }` makes the same file behave differently per branch.
- Secrets come only from Jenkins credentials.
- The image tag is the commit SHA.

## Architecture
Storyboard pages 13–16 (Maven → Docker → Docker Hub → kubectl).

## Lab
Still on `feature/ci-cd-pipeline`:

```bash
mkdir -p k8s
```

**`k8s/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: springboot-app
  namespace: springboot-app
  labels:
    app: springboot-app
  annotations:
    kubernetes.io/change-cause: "CHANGE_CAUSE_PLACEHOLDER"
spec:
  replicas: 2
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: springboot-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: springboot-app
    spec:
      containers:
        - name: app
          image: IMAGE_PLACEHOLDER
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: JAVA_TOOL_OPTIONS
              value: "-XX:MaxRAMPercentage=75.0"
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              memory: 512Mi
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: http
            periodSeconds: 5
            failureThreshold: 30
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: http
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: http
            periodSeconds: 15
            failureThreshold: 3
```

**`k8s/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: springboot-app-svc
  namespace: springboot-app
  labels:
    app: springboot-app
spec:
  type: NodePort
  selector:
    app: springboot-app
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 30080
```

**`Jenkinsfile`**

```groovy
pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        skipDefaultCheckout(true)
    }

    environment {
        K8S_NAMESPACE  = 'springboot-app'
        K8S_DEPLOYMENT = 'springboot-app'
        // DOCKERHUB_REPO and APP_URL come from Manage Jenkins → System → Global properties
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    if (!env.DOCKERHUB_REPO?.trim() || !env.APP_URL?.trim()) {
                        error('Set DOCKERHUB_REPO and APP_URL in Manage Jenkins → System → Global properties')
                    }
                    env.GIT_SHORT_SHA = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.IMAGE = "${env.DOCKERHUB_REPO}:${env.GIT_SHORT_SHA}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.GIT_SHORT_SHA}"
                }
                echo "Branch=${env.BRANCH_NAME} Commit=${env.GIT_SHORT_SHA} Image=${env.IMAGE}"
            }
        }

        stage('Maven Build') {
            steps {
                sh 'chmod +x mvnw && ./mvnw -B -ntp clean compile'
            }
        }

        stage('Test') {
            steps {
                sh './mvnw -B -ntp verify'          // unit tests + package target/app.jar
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                }
                success {
                    archiveArtifacts artifacts: 'target/app.jar', fingerprint: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$IMAGE" .'
            }
        }

        stage('Docker Push') {
            when { anyOf { branch 'main'; branch 'develop' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DOCKERHUB_USER',
                                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    // Single quotes: the shell expands the secret, Groovy never interpolates it
                    sh '''
                        export DOCKER_CONFIG="$WORKSPACE/.docker"
                        echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
                        docker push "$IMAGE"
                        docker logout
                    '''
                }
            }
            post {
                always { sh 'rm -rf "$WORKSPACE/.docker"' }
            }
        }

        stage('Kubernetes Deploy') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl apply -f k8s/service.yaml
                        sed -e "s|IMAGE_PLACEHOLDER|${IMAGE}|g" \
                            -e "s|CHANGE_CAUSE_PLACEHOLDER|Jenkins ${BRANCH_NAME} build ${BUILD_NUMBER} commit ${GIT_SHORT_SHA}|g" \
                            k8s/deployment.yaml | kubectl apply -f -
                        kubectl rollout status deployment/"$K8S_DEPLOYMENT" -n "$K8S_NAMESPACE" --timeout=300s
                    '''
                }
            }
        }

        stage('Verify') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl get deployment,pods,service -n "$K8S_NAMESPACE" -o wide
                        DEPLOYED=$(kubectl get deployment "$K8S_DEPLOYMENT" -n "$K8S_NAMESPACE" \
                          -o jsonpath='{.spec.template.spec.containers[0].image}')
                        echo "Deployed image: $DEPLOYED"
                        test "$DEPLOYED" = "$IMAGE"
                        for i in $(seq 1 12); do
                          if curl -fsS "$APP_URL"; then echo; echo "Application OK"; exit 0; fi
                          echo "Attempt $i failed, retrying in 5s"; sleep 5
                        done
                        echo "Application did not respond at $APP_URL"; exit 1
                    '''
                }
            }
        }
    }

    post {
        always {
            sh '''
                docker rmi "$IMAGE" >/dev/null 2>&1 || true
                docker image prune -f >/dev/null 2>&1 || true
            '''
        }
        success { echo "SUCCESS ${env.BRANCH_NAME} @ ${env.GIT_SHORT_SHA}" }
        failure { echo "FAILED ${env.BRANCH_NAME} @ ${env.GIT_SHORT_SHA}: read the failed stage log" }
    }
}
```

**What each stage does**
- **Checkout**: clones the exact triggering commit using the job's GitHub credentials. Fails fast if global properties are missing. Computes the SHA tag.
- **Maven Build**: compiles with the pinned wrapper.
- **Test**: runs the unit tests and packages the JAR. JUnit results appear in Jenkins. A red test stops everything.
- **Docker Build**: builds on every branch, so a broken Dockerfile is caught early.
- **Docker Push** (`develop` and `main` only): logs in with a token via `--password-stdin` into a per-build config directory that is deleted afterwards.
- **Kubernetes Deploy** (`main` only):
  - `KUBECONFIG` exists only inside the `withCredentials` block.
  - It substitutes the image and change-cause into the manifest and applies it.
  - It waits for `rollout status`. If the new pods never become ready, the stage fails and the old pods keep serving traffic (`maxUnavailable: 0`).
- **Verify** (`main` only): confirms that the running Deployment uses this build's image, then calls the app through the NodePort from inside the VPC.

Commit and integrate:

```bash
git add Dockerfile .dockerignore k8s Jenkinsfile
git commit -m "Add Dockerfile, Kubernetes manifests and Jenkinsfile"
git push -u origin feature/ci-cd-pipeline
git checkout develop
git merge --no-ff feature/ci-cd-pipeline -m "Merge feature/ci-cd-pipeline into develop"
git push origin develop
```

Then in Jenkins: `aws-springboot-devops` → **Scan Multibranch Pipeline Now**.

## Verify
- Jobs `develop` and `feature/ci-cd-pipeline` appear. `main` and `feature/initial-api` do not (no Jenkinsfile on those branches).
- The feature build shows Push, Deploy, and Verify as skipped.
- The develop build pushes `<sha>` to Docker Hub.

## Production Thinking
- Shared libraries for common steps.
- Image scanning and signing stages.
- Separate deploy pipelines per environment, a manual approval gate for production, or GitOps (Argo CD) applying manifests from Git.

---

# 20. First Deployment

## Context
Every piece exists. We run the whole chain once.

## Concept
Merging `develop` into `main` is a release. `main` now contains a Jenkinsfile, so Jenkins discovers it and runs all seven stages.

## Architecture
Storyboard page 18 (highlighted path from GitHub to the Service).

## Lab

```bash
git checkout main && git pull origin main
git merge --no-ff develop -m "Release: Version 1"
git push origin main
```

The webhook is not configured yet, so in Jenkins click **Scan Multibranch Pipeline Now**. Then open `main` → build #1 → **Pipeline Overview**.

Expected:

```
Checkout ✔ → Maven Build ✔ → Test ✔ → Docker Build ✔ → Docker Push ✔ → Kubernetes Deploy ✔ → Verify ✔
```

The console log ends with:

```
Deployed image: <DOCKERHUB_USERNAME>/aws-springboot-devops:a1b2c3d
{"message":"Hello from AWS DevOps Pipeline - Version 1","version":"1","hostname":"springboot-app-…"}
Application OK
Finished: SUCCESS
```

## Verify
On `k8s-control-plane`:

```bash
kubectl get deployments -n springboot-app        # springboot-app 2/2
kubectl get pods -n springboot-app -o wide       # 2 × Running on k8s-worker-1
kubectl get services -n springboot-app           # NodePort 80:30080/TCP
kubectl describe pod -n springboot-app -l app=springboot-app | grep -E 'Image:|Ready:|Started'
kubectl rollout history deployment/springboot-app -n springboot-app
```

Also check:
- Docker Hub shows tag `a1b2c3d`.
- GitHub shows a green ✔ on the commit.
- Jenkins **Tests** shows 2 passed.

## Production Thinking
Releases are promoted, not rebuilt: the image built and tested in staging is the same digest deployed to production, with an approval and change record.

---

# 21. Internet Access

## Context
The pods are running. Now the outside world must reach them.

## Concept
The path:
1. Browser → worker **Elastic IP**.
2. The **IGW** maps it to the private IP 10.0.1.x.
3. **Public route table** and **security group rule K7** allow TCP 30080.
4. **kube-proxy** iptables rule for NodePort 30080.
5. One of the Service's **ready pod endpoints**.
6. Spring Boot on 8080.

Break any link and the request fails. That is the troubleshooting map.

Why NodePort and not `LoadBalancer`: plain kubeadm has no cloud controller, so `type: LoadBalancer` would stay `<pending>`.

## Architecture
Storyboard page 17.

## Lab
From your workstation:

```bash
curl -s http://<WORKER_PUBLIC_IP>:30080/api/hello
for i in 1 2 3 4 5 6; do curl -s http://<WORKER_PUBLIC_IP>:30080/api/hello; echo; done   # hostname alternates between pods
```

Browser: `http://<WORKER_PUBLIC_IP>:30080/api/hello`

## Verify

```bash
kubectl get endpoints springboot-app-svc -n springboot-app    # two pod IPs :8080
```

On the worker: `curl -s localhost:30080/api/hello` works. If this works but the Internet curl does not, check the security group or the IP.

## Production Thinking
- Route 53 name → **ALB** (public subnets, HTTPS with an ACM certificate, AWS WAF) → Kubernetes Service/Ingress → Pods in private subnets.
- The ALB is created by the AWS Load Balancer Controller.
- No NodePort and no node public IPs.

---

# 22. Code Change

## Context
Real systems change constantly. How does a change reach users?

## Concept
The developer edits one line on a feature branch. Everything after `git push` is automated.

## Architecture
Storyboard page 19.

## Lab

```bash
git checkout develop && git pull origin develop
git checkout -b feature/version-2
```

Edit `src/main/java/com/example/devops/HelloController.java`:

```java
    static final String VERSION = "2";
```

```bash
./mvnw -B test                         # still green: the test checks consistency, not a fixed number
git add .
git commit -m "Update application to Version 2"
```

Do **not** push yet. The webhook comes first.

## Verify
`git log -1 --stat` shows only `HelloController.java` changed.

## Production Thinking
- Developers run the same tests locally (pre-commit hooks).
- Pull requests trigger CI before review.
- Feature flags decouple deploy from release.

---

# 23. Automatic CI/CD Deployment

## Context
So far someone clicked "Scan". From now on, **nobody clicks anything**.

## Concept
A GitHub **webhook** POSTs every push and branch event to `http://<JENKINS_PUBLIC_IP>:8080/github-webhook/`.
- The GitHub plugin matches the repository.
- Multibranch indexes the changed branch and starts its build.
- A shared **secret** lets Jenkins verify the request really came from GitHub.

**Why a unique tag per build matters**

If every build pushed `:latest`:
- the Deployment manifest would never change, so `kubectl apply` would report `unchanged` and **no rollout would happen**;
- nodes would keep running their cached image;
- rollbacks would be impossible (`latest` now means the new image);
- you couldn't tell which code is running.

A commit-SHA tag fixes all of this:
- it changes the pod template, which forces a rolling update;
- every node pulls the exact image;
- `rollout history` maps to commits.

`BUILD_NUMBER` also works, but it restarts per branch in Multibranch (both `develop` and `main` have a build #5). The SHA is globally unique.

## Architecture
Storyboard pages 20–23.

## Lab

### 23.1 Open port 8080 to GitHub's webhook senders (temporary rule J3)

```bash
curl -s https://api.github.com/meta | jq -r '.hooks[]' | grep -v ':'     # IPv4 CIDRs
```

**EC2 → Security Groups → `jenkins-sg` → Edit inbound rules.** For each CIDR, add: Custom TCP, port 8080, source = CIDR, description `GitHub webhooks`. **Save**.

### 23.2 Shared secret

```bash
openssl rand -hex 32        # <WEBHOOK_SECRET>
```

1. Jenkins: **Manage Jenkins → Credentials → Global → Add Credentials**:
   - Kind **Secret text**
   - Secret `<WEBHOOK_SECRET>`
   - ID `github-webhook-secret`
2. **Manage Jenkins → System** → **GitHub** section → **Advanced** → **Shared secrets → Add** → select `github-webhook-secret` → **Save**.

If your GitHub plugin version doesn't show this option, leave the secret empty in both places (lab only).

### 23.3 Create the webhook in GitHub
1. Repository → **Settings → Webhooks → Add webhook**.
2. Payload URL: `http://<JENKINS_PUBLIC_IP>:8080/github-webhook/` (trailing slash required).
3. Content type: `application/json`. Secret: `<WEBHOOK_SECRET>`.
4. **Let me select individual events**: **Pushes**, **Branch or tag creation**, **Branch or tag deletion**.
5. **Active** → **Add webhook**.
6. **Recent Deliveries** → the `ping` delivery shows response **200**.

### 23.4 Open the observers
- Terminal A (control plane): `kubectl get pods -n springboot-app -w`
- Terminal B (laptop): `while true; do curl -s http://<WORKER_PUBLIC_IP>:30080/api/hello; echo; sleep 2; done`
- Browser: the Jenkins job page.

### 23.5 Push and promote

```bash
git push -u origin feature/version-2
```

Jenkins **creates** the `feature/version-2` job by itself and builds it. Nothing is pushed or deployed, and Terminal B still says Version 1.

```bash
git checkout develop && git merge --no-ff feature/version-2 -m "Merge feature/version-2 into develop" && git push origin develop
```

The `develop` job starts by itself and pushes a new SHA image. Production is unchanged.

```bash
git checkout main && git pull origin main && git merge --no-ff develop -m "Release: Version 2" && git push origin main
```

`main` starts by itself and runs all stages:
- Terminal A shows a new pod `ContainerCreating → Running 1/1`, then an old pod `Terminating`, twice.
- Terminal B flips from `Version 1` to `Version 2` with no failed requests.

(Optionally do the merges as GitHub pull requests. The merge commit on GitHub triggers the same webhook.)

## Verify

```bash
# 1. Deployment spec uses the new SHA tag
kubectl get deployment springboot-app -n springboot-app \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# 2. All pods are new and run that image
kubectl get pods -n springboot-app \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,START:.status.startTime
# 3. New ReplicaSet active, old scaled to 0
kubectl get rs -n springboot-app
# 4. History shows the Jenkins change-cause with build and commit
kubectl rollout history deployment/springboot-app -n springboot-app
# 5. Tag equals the commit on main (run on laptop)
git log -1 --format=%h main
# 6. From the Internet
curl -s http://<WORKER_PUBLIC_IP>:30080/api/hello
```

```json
{"message":"Hello from AWS DevOps Pipeline - Version 2","version":"2","hostname":"springboot-app-…"}
```

GitHub → Webhooks → Recent Deliveries shows `push` events with 200 responses.

**Optional rollback demo**

```bash
kubectl rollout undo deployment/springboot-app -n springboot-app
```

Version 1 returns. Explain that the next `main` build will redeploy whatever `main` contains, so the durable rollback is `git revert` on `main`.

## Production Thinking
- Jenkins is never directly on the Internet: HTTPS via ALB + WAF allow-listing GitHub to `/github-webhook/`, or a webhook relay, or a GitHub App.
- Production deploys add approval gates, canary or blue/green rollouts, and automated rollback on SLO breach.

---

# 24. Troubleshooting

| # | Symptom | Likely cause | Check | Fix |
|---|---|---|---|---|
| 1 | SSH times out | No public IP; public-rt missing `0.0.0.0/0 → IGW` or not associated; rule J1/K1 doesn't match your current IP | EC2 → instance → Networking / Security tabs; `curl checkip.amazonaws.com` | Fix route or association; update source IP |
| 2 | `apt-get update` / `curl github.com` hangs on an instance | Same as #1 (egress path), or outbound rule removed | `ip route` (default via 10.0.1.1); route table in console | Restore IGW route and default outbound rule |
| 3 | DNS names don't resolve | VPC DNS resolution disabled | `resolvectl status`; `describe-vpc-attribute` | Enable DNS resolution and hostnames (§4) |
| 4 | Jenkins UI unreachable | J2 source IP outdated; Jenkins stopped | `systemctl status jenkins`; `ss -tlnp \| grep 8080` | Update J2; `sudo systemctl restart jenkins` |
| 5 | Scan: `Invalid credentials` / 401 | PAT expired, wrong repo access, email used as username | **Validate** button; `curl -H "Authorization: Bearer <PAT>" https://api.github.com/repos/<user>/aws-springboot-devops` | New PAT (§17.1); update `github-creds` |
| 6 | Branch not discovered | No Jenkinsfile on branch; name filter; PR exclusion strategy | Scan Repository Log | Commit the Jenkinsfile; **All branches**; adjust filter |
| 7 | `./mvnw: Permission denied` | File committed without executable bit | `git ls-files -s mvnw` (needs 100755) | `git update-index --chmod=+x mvnw`, commit, push |
| 8 | `release version 21 not supported` | Jenkins running an older JDK | `sudo -u jenkins java -version` | Install `openjdk-21-jdk`; `update-alternatives --config java`; restart Jenkins |
| 9 | `docker: not found` / `permission denied … docker.sock` | Docker missing / `jenkins` not in `docker` group | `id jenkins`; `sudo -u jenkins docker ps` | Install Docker; `usermod -aG docker jenkins`; restart Jenkins |
| 10 | `Set DOCKERHUB_REPO and APP_URL…` | Global properties missing | Manage Jenkins → System | Add both variables (§17.4) |
| 11 | Docker login `unauthorized` | Token expired or Read-only; username wrong | Manual `docker login` on Jenkins host | New Read & Write token; update `dockerhub-creds` |
| 12 | Push `denied: requested access` | `DOCKERHUB_REPO` doesn't match your namespace/repo | Compare with Docker Hub URL | Fix the global property |
| 13 | `kubectl: not found` | kubectl not installed on Jenkins | `sudo -u jenkins which kubectl` | Install (§10.4) |
| 14 | Deploy: `i/o timeout :6443` | Rule K3 missing | `nc -zv <CP_PRIVATE_IP> 6443` from Jenkins | Add K3 (`jenkins-sg` → 6443) |
| 15 | Deploy: `Unauthorized` / `x509` / `Forbidden` | Stale token or CA, wrong server IP, missing RBAC verb | `kubectl auth can-i --list -n springboot-app --as=system:serviceaccount:springboot-app:jenkins-deployer` | Regenerate kubeconfig (§17.2); fix Role |
| 16 | Nodes `NotReady`, CoreDNS Pending, DNS test hangs | Calico missing; K5/K6 rules missing; `SystemdCgroup` false; swap on | `kubectl describe node`; `journalctl -u kubelet`; `grep SystemdCgroup /etc/containerd/config.toml` | Install Calico; add rules; fix containerd; `swapoff -a` |
| 17 | `ImagePullBackOff` | Wrong tag; private repo; arm64 image; Docker Hub `toomanyrequests` (anonymous pull limit per node IP) | `kubectl describe pod …` (Events); `sudo crictl pull <image>` on worker | Fix image; build amd64; for rate limits create a read-only token, `kubectl create secret docker-registry dockerhub-pull -n springboot-app --docker-username=… --docker-password=…`, and add `imagePullSecrets: [{name: dockerhub-pull}]` to the pod spec |
| 18 | `CrashLoopBackOff` / `OOMKilled` | App exits on start; memory limit too low | `kubectl logs <pod> --previous -n springboot-app`; `describe pod` (Last State) | Fix the error; raise the limit |
| 19 | `rollout status` times out | Probes failing (actuator path), not enough CPU/memory on worker | `kubectl describe pod`; `kubectl get events -n springboot-app --sort-by=.lastTimestamp` | Check `probes.enabled`; adjust resources or startupProbe |
| 20 | URL not reachable from Internet | Wrong IP (private); K7 missing; Service has no endpoints (label mismatch) | `kubectl get endpoints springboot-app-svc -n springboot-app`; on worker `curl localhost:30080/api/hello` | Use `<WORKER_PUBLIC_IP>`; add K7; align labels |
| 21 | Pipeline green but old version still served | Tag reused (`apply` printed `unchanged`) | `kubectl rollout history`; compare deployed image with build image | Deploy SHA tags only (never `latest`) |
| 22 | Push doesn't trigger Jenkins | J3 missing; URL lacks `/github-webhook/`; Jenkins IP changed | GitHub → Webhooks → Recent Deliveries | Add hook CIDRs; fix URL; use Elastic IP; **Redeliver** |
| 23 | Webhook delivery 4xx after adding a secret | Secret mismatch between GitHub and Jenkins | Delivery response body; Jenkins system log | Re-enter the same secret on both sides |
| 24 | Everything broke after stop/start | Auto-assigned public IP changed (control plane) | EC2 console | Expected for the control plane (private IPs keep the cluster working); update SSH targets |

---

# 25. Production Architecture

| Area | This lab | Production on AWS |
|---|---|---|
| Accounts / IAM | One account, AdministratorAccess | AWS Organizations, SCPs, Identity Center least-privilege permission sets, CloudTrail |
| Network | 1 AZ, workloads in a public subnet, no NAT | 3 AZs; workloads in private subnets; NAT per AZ and VPC endpoints; Flow Logs |
| Admin access | SSH from one IP | SSM Session Manager, no port 22, no key pairs |
| Kubernetes | kubeadm: 1 control plane, 1 worker | Amazon EKS (managed HA control plane) with managed node groups or Karpenter |
| Ingress | NodePort 30080, HTTP, node public IP | Route 53 → ALB (ACM TLS, WAF) via AWS Load Balancer Controller → pods |
| Registry | Docker Hub public | Amazon ECR private: scan on push, immutable tags, lifecycle rules |
| Secrets | Tokens stored in Jenkins | IAM roles (OIDC / Pod Identity), AWS Secrets Manager, External Secrets Operator |
| Jenkins | Builds on the controller; HTTP on the Internet | Controller with 0 executors; ephemeral agents; ALB + HTTPS + SSO; JCasC; backups |
| Delivery | `kubectl apply` from Jenkins | GitOps (Argo CD/Flux), Helm/Kustomize per environment, approvals, canary or blue/green |
| Observability | `kubectl logs/events` | CloudWatch Container Insights or Prometheus/Grafana; centralized logs (Fluent Bit); tracing (OpenTelemetry); alerting |
| Scaling / resilience | 2 replicas on 1 node | HPA, cluster autoscaling, PodDisruptionBudgets, topology spread across AZs |
| Security in cluster | Flat pod network | NetworkPolicies (default deny), Pod Security Admission, image signing and admission policies |

---

# 26. EKS Evolution

## Context
Students now understand every moving part. In production we hand the undifferentiated parts to AWS.

## Concept
**Recommendation**
- **Lab 1 (this lab):** self-managed kubeadm, chosen for learning visibility.
- **Lab 2:** the same application and pipeline on **Amazon EKS**, chosen for production realism.

| | Option A: kubeadm on EC2 | Option B: EKS |
|---|---|---|
| Shows Kubernetes internals | Strongly | Hidden |
| New concepts | Linux, kubeadm, CNI, security groups | IAM roles, access entries, eksctl/CloudFormation, VPC CNI, LB Controller |
| Live-demo failure points | Cluster bootstrap | IAM authentication from Jenkins; LB Controller |
| Extra cost | None beyond EC2 | Control-plane hourly fee + load balancer |
| Production fit | Low | High |

## Architecture
The storyboard's private subnet and the reserved AZ-b ranges become real.

## Lab: migration outline for Lab 2
1. **Network:**
   - Add `10.0.2.0/24` (public, AZ b) and `10.0.12.0/24` (private, AZ b).
   - Add a NAT Gateway, and point private route tables at it.
   - Tag subnets `kubernetes.io/role/elb=1` (public) and `kubernetes.io/role/internal-elb=1` (private).
2. **Cluster:** `eksctl create cluster` using the existing VPC's private subnets, with a managed node group of 2 × t3.medium.
3. **Registry:** create ECR `aws-springboot-devops` (immutable tags, scan on push). Attach an IAM role to the Jenkins EC2 that allows ECR push.
4. **Access:**
   - Create an EKS **access entry** for the Jenkins role, scoped to namespace `springboot-app`.
   - The Jenkinsfile runs `aws eks update-kubeconfig` instead of using the `k8s-kubeconfig` secret.
5. **Ingress:**
   - Install the AWS Load Balancer Controller (Helm + Pod Identity).
   - Change the Service to `ClusterIP` and add an `Ingress` (`ingressClassName: alb`, `target-type: ip`). Optionally add an ACM certificate.
6. **Pipeline changes:**
   - Docker Push logs in with `aws ecr get-login-password`.
   - `DOCKERHUB_REPO` becomes the ECR URI.
   - Verify calls the ALB DNS name.

**What stays identical:** the application, tests, Dockerfile, Deployment manifest, branching model, Multibranch job, and SHA tagging.

## Verify
- `kubectl get ingress` shows an ALB address.
- A curl through the ALB returns the current version after a push to `main`.

## Production Thinking
EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI) managed by AWS, cluster upgrades via API, and Karpenter for cost-efficient nodes.

---

# 27. Cost Control and Cleanup

## Context
Greenfield labs are cheap to run and expensive to forget.

## Concept
Approximate on-demand prices in us-east-1 (verify current pricing before the session):

| Resource | Created in this lab? | Cost behaviour |
|---|---|---|
| EC2 t3.large ×1, t3.medium ×2 | Yes | About $0.17/hour combined while **running**. t3 Unlimited mode can add CPU-credit charges. |
| EBS gp3 70 GiB total | Yes | About $0.08/GB-month, charged even while instances are **stopped** |
| Public IPv4 (2 Elastic IPs + 1 auto-assigned) | Yes | About $0.005/hour each, **attached or not** |
| VPC, subnets, route tables, IGW, security groups | Yes | Free |
| NAT Gateway | **No** (only in the EKS lab) | Hourly charge plus per-GB processing |
| Load Balancer (ALB/NLB) | **No** (only in the EKS lab) | Hourly charge plus LCU usage |
| EKS cluster | **No** (only in the EKS lab) | About $0.10/hour per cluster plus nodes |

Between sessions, stopping instances saves EC2 cost. EBS and IP charges continue.

## Architecture
Remove everything from storyboard page 24, innermost first.

## Lab: delete in this order

1. **GitHub:**
   - Repository → Settings → Webhooks → delete the webhook.
   - Settings → Developer settings → delete the `jenkins-aws-lab` token.
   - Optionally archive or delete the repository.
2. **Docker Hub:** Account settings → Personal access tokens → delete `jenkins-aws-lab`. Optionally delete the repository.
3. **EC2 → Instances:** select `jenkins`, `k8s-control-plane`, `k8s-worker-1` → **Instance state → Terminate** → wait for *Terminated*. The root volumes are deleted automatically.
4. **EC2 → Elastic IPs:** select both → **Actions → Release Elastic IP addresses**.
5. **EC2 → Volumes:** delete any volume in state `available`.
6. **EC2 → Key Pairs:** delete `devops-lab-key`. Delete the local `.pem` file.
7. **VPC → Your VPCs:** select `devops-lab-vpc` → **Actions → Delete VPC**. The dialog lists the subnets, route tables, Internet Gateway, and security groups it will delete with the VPC. Type `delete` → **Delete**.
   - If it reports dependencies, a remaining network interface or Elastic IP is the usual cause. Remove it and retry.
8. If you built the EKS variant: delete the cluster (`eksctl delete cluster`), ALBs, target groups, NAT Gateway and its Elastic IP, and the ECR repository **before** deleting the VPC.

## Verify
In CloudShell, in the lab Region:

```bash
aws ec2 describe-instances --filters Name=tag:Project,Values=devops-lab \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId'                       # []
aws ec2 describe-addresses --query 'Addresses[].PublicIp'               # []
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'   # []
aws ec2 describe-vpcs --filters Name=tag:Name,Values=devops-lab-vpc --query 'Vpcs[].VpcId'    # []
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'   # []
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'   # []
aws eks list-clusters                                                    # {"clusters": []}
```

The next day, check **Billing → Bills**: EC2 and EBS line items have stopped growing. Keep the budget alert.

## Production Thinking
- Tag-based cost allocation, budgets per team, and scheduled shutdown of non-production environments.
- Infrastructure as code, so `terraform destroy` removes everything reliably.

---

## Live-session checklist

- [ ] Budget, MFA, Region selected
- [ ] VPC `10.0.0.0/16` with DNS hostnames · public `10.0.1.0/24` (auto public IP) · private `10.0.11.0/24`
- [ ] IGW attached · public-rt `0.0.0.0/0 → IGW` associated · private-rt local only
- [ ] `jenkins-sg` J1–J2 · `k8s-nodes-sg` K1–K7
- [ ] 3 instances (encrypted gp3, IMDSv2, tagged) · 2 Elastic IPs · hostnames + `/etc/hosts` · egress test passes
- [ ] Jenkins: Java 21, LTS, Docker, kubectl, wizard done, Pipeline Graph View, 2 executors
- [ ] Kubernetes: both nodes Ready · Calico running · nginx smoke test passed and deleted
- [ ] App builds with `./mvnw` · Version 1 responds locally · `mvnw` is executable in Git
- [ ] GitHub repo with `main`, `develop`, `feature/initial-api`
- [ ] Dockerfile builds locally · Docker Hub repo + Read & Write token · test push OK
- [ ] RBAC + kubeconfig created and copies deleted · `github-creds`, `dockerhub-creds`, `k8s-kubeconfig` · `DOCKERHUB_REPO`, `APP_URL` set
- [ ] Multibranch job: All branches, PR discovery removed, filter, 1-hour scan
- [ ] Jenkinsfile + manifests on `develop` · develop build pushes a SHA tag
- [ ] Release to `main` · all 7 stages green · Version 1 on `http://<WORKER_PUBLIC_IP>:30080/api/hello`
- [ ] J3 GitHub hook CIDRs · webhook secret · ping = 200
- [ ] `feature/version-2` auto-discovered → develop auto-built → main auto-deployed · curl flips to Version 2 · rollout history shows the SHA
- [ ] Production thinking (§25) and EKS evolution (§26) discussed
- [ ] Cleanup (§27) done and verified

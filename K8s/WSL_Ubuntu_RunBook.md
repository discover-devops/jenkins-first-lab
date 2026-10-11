# AWS DevOps CI/CD Lab -- Student Runbook (WSL Ubuntu)

## 1. Objective

Build an end-to-end CI/CD pipeline for a simple NGINX application:

``` text
WSL Ubuntu → GitHub (develop) → Jenkins → Docker Image → Docker Hub
                                      ↓
                               SSH to Minikube EC2
                                      ↓
                                  Kubernetes
                                      ↓
                                   NGINX
```

**Important:** WSL is the developer workstation. Jenkins and Minikube
run on AWS EC2. Do not use Docker locally for this lab.

------------------------------------------------------------------------

## 2. What Students Need

-   Windows + WSL2 + Ubuntu
-   GitHub account
-   Docker Hub account
-   AWS access
-   Jenkins EC2
-   Minikube EC2
-   SSH access to the EC2 instances

Use your own values. Never copy an instructor's IP address or
credentials.

  Value                 Example
  --------------------- -------------------------------------------------
  GitHub repo           `https://github.com/<user>/aws-devops-demo.git`
  Docker Hub repo       `<user>/aws-devops-demo`
  Jenkins               `<JENKINS_IP>:8080`
  Minikube private IP   `10.0.x.x`

------------------------------------------------------------------------

# Activity 1 -- Prepare WSL Ubuntu

Open Ubuntu/WSL:

``` bash
cat /etc/os-release
git --version
ssh -V
```

If Git is missing:

``` bash
sudo apt update
sudo apt install -y git
```

### Explanation

WSL is the developer machine. We use it for Git, GitHub, editing and
SSH. Jenkins performs the Docker build.

------------------------------------------------------------------------

# Activity 2 -- Configure Git

``` bash
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
git config --global --list
```

### Explanation

Git records the author of each commit.

------------------------------------------------------------------------

# Activity 3 -- Create and Clone the GitHub Repository

Create a GitHub repository named:

``` text
aws-devops-demo
```

Clone it:

``` bash
cd ~
git clone https://github.com/<YOUR_GITHUB_USERNAME>/aws-devops-demo.git
cd aws-devops-demo
```

------------------------------------------------------------------------

# Activity 4 -- Create the Develop Branch

``` bash
git checkout -b develop
git push -u origin develop
git branch
```

Expected:

``` text
* develop
```

### Explanation

For this lab:

``` text
develop → Development environment
main    → Production concept
```

All application changes in this lab are made on `develop`.

------------------------------------------------------------------------

# Activity 5 -- Create the Application

Create the directories:

``` bash
mkdir -p k8s
```

Create `index.html`:

``` bash
nano index.html
```

``` html
<!DOCTYPE html>
<html>
<head>
    <title>AWS DevOps Demo</title>
</head>
<body>
    <h1>AWS DevOps Demo Application</h1>
    <h2>Version 1.0</h2>
    <p>Environment: Development</p>
    <p>Deployed by: Jenkins</p>
</body>
</html>
```

Create `Dockerfile`:

``` bash
nano Dockerfile
```

``` dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

Create `README.md`:

``` bash
nano README.md
```

``` markdown
# AWS DevOps Demo

Simple NGINX application used for demonstrating an end-to-end Jenkins CI/CD pipeline.

Version: 1.0
Environment: Development
Deployment: Jenkins + Docker + Kubernetes
```

### Explanation

The Dockerfile creates an NGINX container and copies the HTML page into
NGINX's web directory. Docker will be built by Jenkins.

------------------------------------------------------------------------

# Activity 6 -- Create Kubernetes Manifests

Create `k8s/deployment.yaml`:

``` bash
nano k8s/deployment.yaml
```

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-devops-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: aws-devops-demo
  template:
    metadata:
      labels:
        app: aws-devops-demo
    spec:
      containers:
        - name: aws-devops-demo
          image: <YOUR_DOCKERHUB_USERNAME>/aws-devops-demo:latest
          ports:
            - containerPort: 80
```

Replace `<YOUR_DOCKERHUB_USERNAME>`.

Create `k8s/service.yaml`:

``` bash
nano k8s/service.yaml
```

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: aws-devops-demo
spec:
  type: NodePort
  selector:
    app: aws-devops-demo
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

### Explanation

The Deployment creates two NGINX pods. The Service exposes the
application through NodePort `30080`.

The YAML initially uses `latest`. The Jenkins pipeline later changes the
running image to the current Jenkins `BUILD_NUMBER`.

------------------------------------------------------------------------

# Activity 7 -- Commit the Application

Review:

``` bash
find . -maxdepth 2 -type f | sort
git status
```

Commit and push:

``` bash
git add .
git commit -m "Add AWS DevOps demo application"
git push origin develop
```

------------------------------------------------------------------------

# Activity 8 -- Prepare Minikube EC2

SSH to Minikube:

``` bash
ssh ubuntu@<MINIKUBE_PUBLIC_IP>
```

Verify:

``` bash
kubectl get nodes
minikube status
```

Expected node status:

``` text
Ready
```

Exit:

``` bash
exit
```

### Explanation

Minikube is our development Kubernetes environment. Jenkins will
remotely run `kubectl` on this server.

------------------------------------------------------------------------

# Activity 9 -- Prepare Jenkins EC2

Open:

``` text
http://<JENKINS_PUBLIC_IP>:8080
```

On Jenkins EC2 verify:

``` bash
java -version
git --version
docker --version
kubectl version --client
sudo systemctl status jenkins
```

Give Jenkins Docker permission:

``` bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Test:

``` bash
sudo -u jenkins docker --version
```

### Explanation

Jenkins needs Docker to build and push the application image.

------------------------------------------------------------------------

# Activity 10 -- Configure Jenkins → Minikube SSH

On Jenkins EC2:

``` bash
sudo -u jenkins mkdir -p /var/lib/jenkins/.ssh

sudo -u jenkins ssh-keygen -t rsa -b 4096 \
  -f /var/lib/jenkins/.ssh/id_rsa -N ""
```

Display the public key:

``` bash
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
```

Copy the **public** key.

SSH to Minikube:

``` bash
ssh ubuntu@<MINIKUBE_PUBLIC_IP>
```

Add the Jenkins public key:

``` bash
nano ~/.ssh/authorized_keys
```

Then:

``` bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
exit
```

Test from Jenkins:

``` bash
sudo -u jenkins ssh \
  -i /var/lib/jenkins/.ssh/id_rsa \
  -o IdentitiesOnly=yes \
  ubuntu@<MINIKUBE_PRIVATE_IP> \
  "kubectl get nodes"
```

Expected: the Minikube node is `Ready`.

### Explanation

The private key stays on Jenkins. The public key is placed in Minikube's
`authorized_keys`.

``` text
Jenkins private key
        |
        | SSH
        v
Minikube authorized_keys
```

------------------------------------------------------------------------

# Activity 11 -- Create Docker Hub Repository

Create:

``` text
<YOUR_DOCKERHUB_USERNAME>/aws-devops-demo
```

Create a Docker Hub access token with sufficient permission to push
images.

Do not put the token in GitHub or the Jenkinsfile.

------------------------------------------------------------------------

# Activity 12 -- Create Jenkins Docker Hub Credential

In Jenkins:

``` text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Select:

``` text
Kind: Username with password
Username: <YOUR_DOCKERHUB_USERNAME>
Password: <DOCKER_HUB_ACCESS_TOKEN>
ID: dockerhub-creds
```

Save.

### Explanation

`dockerhub-creds` is only the Jenkins credential ID.

In the Jenkinsfile:

``` groovy
credentialsId: 'dockerhub-creds'
```

Jenkins finds that stored credential.

Then:

``` groovy
usernameVariable: 'DOCKERHUB_USERNAME'
passwordVariable: 'DOCKERHUB_PASSWORD'
```

temporarily maps the stored values to variables.

`passwordVariable` is a Jenkins Pipeline parameter; `DOCKERHUB_PASSWORD`
is the variable name we choose.

------------------------------------------------------------------------

# Activity 13 -- Create Jenkins Minikube Credential

In Jenkins:

``` text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Select:

``` text
Kind: SSH Username with private key
Username: ubuntu
ID: minikube-ssh
```

Paste the private key from:

``` bash
sudo cat /var/lib/jenkins/.ssh/id_rsa
```

Save.

**Never share the private key with other people or commit it to Git.**

------------------------------------------------------------------------

# Activity 14 -- Create the Jenkinsfile

In WSL:

``` bash
nano Jenkinsfile
```

Use:

``` groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = '<YOUR_DOCKERHUB_USERNAME>/aws-devops-demo'
        MINIKUBE_HOST = '<MINIKUBE_PRIVATE_IP>'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build and Push Docker Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKERHUB_USERNAME',
                    passwordVariable: 'DOCKERHUB_PASSWORD'
                )]) {
                    sh '''
                        set -eu
                        docker build -t "$IMAGE_NAME:$BUILD_NUMBER" .
                        echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin
                        docker push "$IMAGE_NAME:$BUILD_NUMBER"
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Minikube') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'minikube-ssh',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -eu
                        REMOTE_DIR="/tmp/aws-devops-demo-$BUILD_NUMBER"
                        SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"

                        ssh $SSH_OPTS "$SSH_USER@$MINIKUBE_HOST" "mkdir -p '$REMOTE_DIR'"

                        scp $SSH_OPTS -r k8s \
                            "$SSH_USER@$MINIKUBE_HOST:$REMOTE_DIR/"

                        ssh $SSH_OPTS "$SSH_USER@$MINIKUBE_HOST" \
                            "kubectl apply -f '$REMOTE_DIR/k8s' &&
                             kubectl set image deployment/aws-devops-demo aws-devops-demo='$IMAGE_NAME:$BUILD_NUMBER' &&
                             kubectl rollout status deployment/aws-devops-demo"
                    '''
                }
            }
        }
    }
}
```

Replace:

``` text
<YOUR_DOCKERHUB_USERNAME>
<MINIKUBE_PRIVATE_IP>
```

### Jenkinsfile in simple words

``` text
Checkout
   ↓
Get code from GitHub

Build and Push
   ↓
Build Docker image
   ↓
Tag with BUILD_NUMBER
   ↓
Push to Docker Hub

Deploy
   ↓
SSH to Minikube
   ↓
Copy k8s files
   ↓
kubectl apply
   ↓
Set new image
   ↓
Wait for rollout
```

------------------------------------------------------------------------

# Activity 15 -- Commit Jenkinsfile

``` bash
git add Jenkinsfile
git commit -m "Add Jenkins CI CD pipeline"
git push origin develop
```

------------------------------------------------------------------------

# Activity 16 -- Create Jenkins Multibranch Pipeline

In Jenkins:

``` text
New Item
→ aws-devops-demo
→ Multibranch Pipeline
```

Configure the repository:

``` text
Repository:
https://github.com/<YOUR_GITHUB_USERNAME>/aws-devops-demo.git
```

For a public repository:

``` text
Credentials: None
```

Build Configuration:

``` text
Mode: by Jenkinsfile
Script Path: Jenkinsfile
```

Save.

Then select:

``` text
Scan Multibranch Pipeline Now
```

Jenkins should discover `develop`.

------------------------------------------------------------------------

# Activity 17 -- Run the Pipeline

Open:

``` text
aws-devops-demo
→ develop
```

Run the build.

The stages should be:

``` text
Checkout
Build and Push Docker Image
Deploy to Minikube
```

For Build #1, the Docker image will be similar to:

``` text
<YOUR_DOCKERHUB_USERNAME>/aws-devops-demo:1
```

The exact tag is the Jenkins `BUILD_NUMBER`.

------------------------------------------------------------------------

# Activity 18 -- Verify Docker Hub

Open Docker Hub and check:

``` text
<YOUR_DOCKERHUB_USERNAME>/aws-devops-demo
```

Confirm that the image tag created by Jenkins exists.

------------------------------------------------------------------------

# Activity 19 -- Verify Kubernetes

SSH to Minikube:

``` bash
ssh ubuntu@<MINIKUBE_PUBLIC_IP>
```

Check:

``` bash
kubectl get pods
kubectl get deployment
kubectl get svc
```

Expected:

``` text
2 pods Running
```

and:

``` text
aws-devops-demo   NodePort   ...   80:30080/TCP
```

------------------------------------------------------------------------

# Activity 20 -- Access the Application

Because this lab uses Minikube with the Docker driver on EC2, use port
forwarding.

On Minikube EC2:

``` bash
kubectl port-forward \
  --address 0.0.0.0 \
  service/aws-devops-demo \
  30080:80
```

Keep this terminal running.

Allow TCP `30080` in the Minikube EC2 security group from your IP.

Open:

``` text
http://<MINIKUBE_PUBLIC_IP>:30080
```

Expected:

``` text
AWS DevOps Demo Application

Version 1.0

Environment: Development

Deployed by: Jenkins
```

------------------------------------------------------------------------

# Activity 21 -- Demonstrate CI/CD with Version 2

Return to WSL.

Edit:

``` bash
nano index.html
```

Change:

``` html
<h2>Version 1.0</h2>
```

to:

``` html
<h2>Version 2.0</h2>
```

Commit and push:

``` bash
git add index.html
git commit -m "Update application to version 2.0"
git push origin develop
```

Jenkins builds the new version.

The flow is:

``` text
Git push
   ↓
GitHub develop
   ↓
Jenkins
   ↓
Docker build
   ↓
Docker Hub
   ↓
Minikube
   ↓
Kubernetes rollout
```

Verify the image:

``` bash
kubectl get deployment aws-devops-demo \
  -o=jsonpath='{.spec.template.spec.containers[0].image}'
```

It should show the current Jenkins build tag.

Refresh:

``` text
http://<MINIKUBE_PUBLIC_IP>:30080
```

You should now see:

``` text
Version 2.0
```

------------------------------------------------------------------------

# Activity 22 -- Understand Branch-to-Environment Mapping

The lab currently demonstrates:

``` text
develop
   ↓
Jenkins
   ↓
Development Kubernetes environment
```

A production design can use:

``` text
develop
   ↓
DEV
   ↓
Testing / QA
   ↓
Approval
   ↓
main
   ↓
Production Jenkins Pipeline
   ↓
PROD
```

The important principle is:

**Develop branch is mapped to development. Main branch is mapped to
production.**

------------------------------------------------------------------------

# Activity 23 -- Understand Docker Image Management

Every successful build can create another image:

``` text
app:101
app:102
app:103
...
app:500
```

This is why container registries such as ECR or Docker Hub need
lifecycle/retention policies.

A real organization may:

-   Keep recent development images
-   Keep production images longer
-   Remove old unused images automatically
-   Preserve images required for rollback
-   Scan images for vulnerabilities

Do not blindly delete images that are still required for running
workloads or rollback.

------------------------------------------------------------------------

# Troubleshooting

## Docker push: "insufficient scopes"

Check the Docker Hub token used by:

``` text
dockerhub-creds
```

It needs permission to push images.

Update the Jenkins credential if required.

------------------------------------------------------------------------

## Jenkins cannot SSH to Minikube

From Jenkins:

``` bash
sudo -u jenkins ssh \
  -i /var/lib/jenkins/.ssh/id_rsa \
  ubuntu@<MINIKUBE_PRIVATE_IP> \
  "kubectl get nodes"
```

Check:

-   Minikube is running
-   Security group permits SSH
-   Jenkins can reach Minikube private IP
-   Jenkins public key is in `authorized_keys`
-   Jenkins credential ID is `minikube-ssh`

------------------------------------------------------------------------

## Docker permission denied

``` bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
sudo -u jenkins docker ps
```

------------------------------------------------------------------------

## Kubernetes pod is not Running

``` bash
kubectl get pods
kubectl describe pod <POD_NAME>
kubectl get events --sort-by=.lastTimestamp
```

------------------------------------------------------------------------

## Application cannot be opened

Check:

``` bash
kubectl get pods
kubectl get svc
```

Restart port forwarding if necessary:

``` bash
kubectl port-forward \
  --address 0.0.0.0 \
  service/aws-devops-demo \
  30080:80
```

Also verify that the EC2 security group permits TCP `30080`.

------------------------------------------------------------------------

# Final Student Checklist

-   [ ] WSL Ubuntu ready
-   [ ] Git configured
-   [ ] GitHub repository created
-   [ ] `develop` branch created
-   [ ] NGINX application created
-   [ ] Dockerfile created
-   [ ] Kubernetes manifests created
-   [ ] Application pushed to GitHub
-   [ ] Minikube is Ready
-   [ ] Jenkins is running
-   [ ] Jenkins can run Docker
-   [ ] Jenkins → Minikube SSH works
-   [ ] Docker Hub repository created
-   [ ] `dockerhub-creds` created
-   [ ] `minikube-ssh` created
-   [ ] Jenkinsfile committed
-   [ ] Multibranch Pipeline created
-   [ ] `develop` discovered
-   [ ] Docker image pushed
-   [ ] Kubernetes pods Running
-   [ ] Version 1.0 visible
-   [ ] Version 2.0 committed and pushed
-   [ ] New Jenkins build completed
-   [ ] Version 2.0 visible

------------------------------------------------------------------------

# Final Architecture

``` text
                         GitHub
                           |
                       develop
                           |
                           v
                    Jenkins Pipeline
                           |
             +-------------+-------------+
             |                           |
             v                           v
       Docker Build                 Credentials
             |                           |
             v                           |
        Docker Hub <---------------------+
             |
             v
       SSH to Minikube EC2
             |
             v
        Kubernetes
             |
       +-----+-----+
       |           |
     Pod 1       Pod 2
       |           |
       +-----+-----+
             |
          Service
             |
             v
           User
```

## Key takeaway

> A developer pushes code to the `develop` branch. Jenkins checks out
> the code, builds a versioned Docker image, pushes it to the container
> registry, connects to the development Kubernetes environment, deploys
> the image, and waits for the rollout to complete.

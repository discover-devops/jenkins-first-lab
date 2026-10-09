
# Activity 3 — Install and Verify Minikube

### Target

```text
EC2 #2
Ubuntu 24.04
     ↓
Docker
     ↓
Minikube
     ↓
Kubernetes
     ↓
kubectl
```

## Step 3.1 — Verify the server

Run:

```bash
hostname
```

Then:

```bash
cat /etc/os-release
```

Then:

```bash
nproc
```

And:

```bash
free -h
```

We expect approximately:

```text
Ubuntu 24.04
2 CPU
4 GiB RAM
```

---

## Step 3.2 — Update Ubuntu

```bash
sudo apt update
sudo apt upgrade -y
```

---

## Step 3.3 — Install Docker

Install prerequisites:

```bash
sudo apt install -y ca-certificates curl
```

Create Docker key directory:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

Download Docker's official key:

```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
```

Set permissions:

```bash
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Add the Docker repository:

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Update:

```bash
sudo apt update
```

Install Docker:

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## Step 3.4 — Start and verify Docker

```bash
sudo systemctl enable docker
```

```bash
sudo systemctl start docker
```

Check:

```bash
sudo systemctl is-active docker
```

Expected:

```text
active
```

Check version:

```bash
docker --version
```

Then:

```bash
sudo docker run --rm hello-world
```

You should see:

```text
Hello from Docker!
```

---

## Step 3.5 — Allow your Ubuntu user to use Docker

Run:

```bash
sudo usermod -aG docker $USER
```

Now **log out of EC2 #2 and SSH back in**.

After reconnecting, verify:

```bash
docker ps
```

It should work **without `sudo`**.

Also verify:

```bash
docker run --rm hello-world
```

---

# Step 3.6 — Install Minikube

We'll use the official Minikube binary.

Download it:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
```

Install it:

```bash
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

Remove the downloaded file:

```bash
rm minikube-linux-amd64
```

Verify:

```bash
minikube version
```

You should get the installed Minikube version.

---

# Step 3.7 — Install kubectl

Install prerequisites:

```bash
sudo apt install -y curl
```

Get the current stable Kubernetes version:

```bash
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
```

Check it:

```bash
echo $KUBECTL_VERSION
```

Download:

```bash
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
```

Download checksum:

```bash
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
```

Verify:

```bash
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
```

Expected:

```text
kubectl: OK
```

Install:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Clean up:

```bash
rm -f kubectl kubectl.sha256
```

Verify:

```bash
kubectl version --client
```

---

# Step 3.8 — Start Minikube

Now we create the Kubernetes environment.

Because we're using Docker as the driver:

```bash
minikube start --driver=docker
```

This may take a few minutes.

Minikube will create a Kubernetes cluster inside Docker.

---

# Step 3.9 — Verify Minikube

First:

```bash
minikube status
```

We want:

```text
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

Then:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   ...   ...
```

Then:

```bash
kubectl get pods -A
```

You should see Kubernetes system pods.

---

# Step 3.10 — Verify Minikube dashboard components

Run:

```bash
kubectl get pods -n kube-system
```

The important thing is that the major system components are running.

Then:

```bash
minikube profile list
```

You should see your Minikube profile.

---

# Step 3.11 — Deploy a simple test application

Before we use Spring Boot, let's prove that Kubernetes actually works.

Create an NGINX deployment:

```bash
kubectl create deployment nginx --image=nginx
```

Check:

```bash
kubectl get deployments
```

Then:

```bash
kubectl get pods
```

We want the NGINX pod to become:

```text
Running
```

---

# Step 3.12 — Expose the test application

Create a service:

```bash
kubectl expose deployment nginx --type=NodePort --port=80
```

Check:

```bash
kubectl get service nginx
```

Then:

```bash
minikube service nginx --url
```

Minikube will give you a URL.

Test it:

```bash
curl $(minikube service nginx --url)
```

You should receive the NGINX HTML response.

This proves:

```text
kubectl
   ↓
Minikube
   ↓
Kubernetes Deployment
   ↓
Pod
   ↓
Service
   ↓
NGINX
```

---

# Step 3.13 — Clean up the test application

We don't need NGINX because our actual application will be Spring Boot.

Delete it:

```bash
kubectl delete service nginx
```

Then:

```bash
kubectl delete deployment nginx
```

Verify:

```bash
kubectl get pods
```

There should be no NGINX application pod.

---

# Step 3.14 — Final verification

Run all of these:

```bash
docker --version
```

```bash
minikube version
```

```bash
kubectl version --client
```

```bash
minikube status
```

```bash
kubectl get nodes
```

```bash
kubectl get pods -A
```

The key result is:

```text
Minikube       
Docker         
kubectl        
Kubernetes     
Node Ready     
Test workload  
```

## Our infrastructure will now look like this

```text
                 AWS
                  │
       ┌──────────┴──────────┐
       │                     │
       ▼                     ▼
   EC2 #1                 EC2 #2
   Jenkins                Minikube
   t3.large               t3.medium
       │                     │
       │                     └── Kubernetes
       │
       └────── CI/CD ────────────►
       
   EC2 #3
   Reserved
```

**Don't do anything with EC2 #3 yet.**

Also, we don't need to expose Minikube to the internet at this stage. Jenkins will eventually communicate with it internally.

Start with **Step 3.1** and proceed through the activity. If something fails, send me the **step number + complete error**, exactly as you did for the Jenkins activity.

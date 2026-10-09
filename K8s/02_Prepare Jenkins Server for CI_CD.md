
# Activity 2 — Prepare Jenkins Server for CI/CD

### Objective

Prepare `devops-lab-jenkins` so Jenkins can eventually execute:

```text
GitHub
   ↓
Jenkins
   ↓
Maven Build & Test
   ↓
Docker Build
   ↓
Docker Hub
   ↓
Kubernetes
```

We will install:

1. Git
2. Maven
3. Docker Engine
4. kubectl
5. Required Jenkins permissions
6. Verify everything

We are **not installing Kubernetes on this server**. Kubernetes will be installed on the other two EC2s later.

---

## Step 2.1 — Update Ubuntu

Run:

```bash
sudo apt update
sudo apt upgrade -y
```

Verify:

```bash
sudo apt update
```

You should not see repository errors.

---

# Step 2.2 — Install Git

Install:

```bash
sudo apt install git -y
```

Verify:

```bash
git --version
```

Expected:

```text
git version ...
```

Also check which Git is being used:

```bash
which git
```

Expected:

```text
/usr/bin/git
```

---

# Step 2.3 — Install Maven

Install Maven:

```bash
sudo apt install maven -y
```

Verify:

```bash
mvn -version
```

You should see something similar to:

```text
Apache Maven 3.x.x
Java version: 21...
Java home: /usr/lib/jvm/...
```

Important: Maven should show **Java 21**.

---

# Step 2.4 — Install Docker Engine

For Docker, we'll use Docker's official Ubuntu repository rather than Ubuntu's older Docker package.

### 2.4.1 Remove conflicting packages

Run:

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt remove -y $pkg
done
```

It's okay if some packages say they aren't installed.

### 2.4.2 Install Docker repository prerequisites

```bash
sudo apt update
sudo apt install ca-certificates curl -y
```

### 2.4.3 Add Docker's official GPG key

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

Then:

```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
```

Set permissions:

```bash
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

### 2.4.4 Add Docker repository

Run:

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 2.4.5 Update package index

```bash
sudo apt update
```

### 2.4.6 Install Docker

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
```

This gives us Docker Engine plus Buildx and Compose.

Docker's official documentation recommends configuring Docker so it can be used by a non-root user. [Jenkins](https://www.jenkins.io/doc/book/installing/docker/)

---

# Step 2.5 — Start and enable Docker

Run:

```bash
sudo systemctl enable docker
```

Then:

```bash
sudo systemctl start docker
```

Verify:

```bash
sudo systemctl status docker
```

You want:

```text
Active: active (running)
```

Press **Q** to exit.

Then:

```bash
docker --version
```

And:

```bash
sudo docker info
```

The `docker info` command should return Docker server information without an error.

---

# Step 2.6 — Give Jenkins access to Docker

This is important.

Jenkins runs as the Linux user:

```text
jenkins
```

Docker normally requires root-level access through its Unix socket.

We'll add Jenkins to the `docker` group:

```bash
sudo usermod -aG docker jenkins
```

Verify:

```bash
id jenkins
```

You should eventually see:

```text
groups=...,docker
```

### Restart Jenkins

```bash
sudo systemctl restart jenkins
```

Now verify Docker access **as the Jenkins user**:

```bash
sudo -u jenkins docker version
```

You should see both:

```text
Client:
...

Server:
...
```

Then test an actual container:

```bash
sudo -u jenkins docker run --rm hello-world
```

You should see:

```text
Hello from Docker!
```

This is a very important checkpoint.

It proves:

```text
Jenkins Linux User
        ↓
Docker CLI
        ↓
Docker Engine
        ↓
Container
```

---

# Step 2.7 — Install kubectl

We need `kubectl` on the Jenkins server because later Jenkins will deploy the application to our Kubernetes cluster.

Use the current Kubernetes installation instructions rather than an old `apt.kubernetes.io` repository.

First install prerequisites:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
```

Then install the current stable `kubectl` binary:

```bash
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
```

Check what version was detected:

```bash
echo $KUBECTL_VERSION
```

Then:

```bash
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
```

Verify the download:

```bash
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
```

Check:

```bash
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
```

Expected:

```text
kubectl: OK
```

Install it:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Verify:

```bash
kubectl version --client
```

You should see the client version.

Clean up:

```bash
rm -f kubectl kubectl.sha256
```

---

# Step 2.8 — Verify kubectl for Jenkins user

Run:

```bash
sudo -u jenkins kubectl version --client
```

This should also work.

At this point Jenkins has the basic tools it will need:

```text
jenkins user
     │
     ├── git
     ├── mvn
     ├── docker
     └── kubectl
```

---

# Step 2.9 — Verify all tools together

Run these commands one by one:

### Git

```bash
git --version
```

### Maven

```bash
mvn -version
```

### Java

```bash
java -version
```

### Docker

```bash
docker --version
```

### kubectl

```bash
kubectl version --client
```

Now verify them as the **Jenkins user**:

```bash
sudo -u jenkins git --version
```

```bash
sudo -u jenkins mvn -version
```

```bash
sudo -u jenkins docker --version
```

```bash
sudo -u jenkins kubectl version --client
```

---

# Step 2.10 — Final Jenkins service verification

Restart Jenkins one final time:

```bash
sudo systemctl restart jenkins
```

Wait a few seconds:

```bash
sleep 5
```

Then:

```bash
sudo systemctl is-active jenkins
```

Expected:

```text
active
```

Check Jenkins port:

```bash
sudo ss -lntp | grep 8080
```

You should see Jenkins listening on port `8080`.

---

# Activity 2 — DONE criteria

We are finished only when all of these are working:

```text
Java 21             
Jenkins LTS         

Git                 
Maven               
Docker Engine       
Docker → Jenkins    
kubectl             

Jenkins service     
Port 8080           
```

The most important test is:

```bash
sudo -u jenkins docker run --rm hello-world
```

If that works, our Jenkins machine is ready to become the **CI/CD engine**.

These choices align with the current Jenkins guidance for Java 21 and Linux installations, and Docker's guidance for allowing non-root users to manage Docker. [Jenkins](https://www.jenkins.io/doc/book/installing/linux)

**Do the activity from Step 2.1 through Step 2.10.** If you get stuck, send me **the exact sub-step number and error output**, e.g. `Step 2.4.4 error`, and we'll fix that specific point.

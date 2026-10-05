
# Complete Step-by-Step Lab

## Target Architecture

```text
                    GitHub
                       |
                       | git push
                       v
                Jenkins Controller
                       |
                  Jenkinsfile
                       |
                       v
                    AgentB
                       |
          +------------+-------------+
          |            |             |
        Maven       Docker        Docker Hub
      Build/Test     Build          Push
                       |
                       v
                  Docker Image
                       |
                       v
                  Docker Container
                       |
                    Port 8080
                       |
                       v
                    Internet
```

And later:

```text
Code Change
    ↓
Git Push
    ↓
Jenkins Build #2
    ↓
New Docker Image :2
    ↓
Docker Hub
    ↓
New Container
    ↓
Browser shows new application
```

---

# PHASE 1 — Understand Our Existing Environment

## Step 1 — Confirm AgentB

### [AGENT B]

SSH into AgentB.

Run:

```bash
hostname
```

Expected:

```text
AgentB
```

Then:

```bash
whoami
```

Expected:

```text
azureuser
```

Then:

```bash
pwd
```

We are only verifying the machine and user.

---

# PHASE 2 — Check Docker

## Step 2 — Check Whether Docker Exists

### [AGENT B]

Run:

```bash
docker --version
```

### If Docker is installed

You will get something similar to:

```text
Docker version ...
```

Continue to Step 3.

### If Docker is NOT installed

You may see:

```text
docker: command not found
```

Then install it.

Run:

```bash
sudo apt update
```

Then:

```bash
sudo apt install -y docker.io
```

Then:

```bash
sudo systemctl enable --now docker
```

Verify:

```bash
docker --version
```

Do not continue until Docker is installed successfully.

---

# PHASE 3 — Verify Docker Service

## Step 3 — Check Docker Service

### [AGENT B]

Run:

```bash
sudo systemctl status docker --no-pager
```

We want:

```text
Active: active (running)
```

If it is not running:

```bash
sudo systemctl start docker
```

Then check again:

```bash
sudo systemctl status docker --no-pager
```

---

# PHASE 4 — Verify Docker Can Actually Run

## Step 4 — Run Docker Test Container

### [AGENT B]

Run:

```bash
sudo docker run hello-world
```

This verifies that Docker can:

```text
Docker client
    ↓
Docker daemon
    ↓
Pull image
    ↓
Create container
    ↓
Run container
```

You should eventually see:

```text
Hello from Docker!
```

At this stage, **we are deliberately using `sudo` only for the test**.

Next we will configure the Jenkins user to use Docker without `sudo`.

---

# PHASE 5 — Give Jenkins User Docker Access

## Step 5 — Identify Jenkins Agent User

### [AGENT B]

Run:

```bash
ps -ef | grep '[j]enkins'
```

We expect to see the Jenkins agent process running as something like:

```text
azureuser
```

Our previous environment uses `azureuser`, but we verify it rather than assume it.

---

# Step 6 — Add Jenkins User to Docker Group

### [AGENT B]

If the Jenkins agent is running as `azureuser`, run:

```bash
sudo usermod -aG docker azureuser
```

Then verify:

```bash
getent group docker
```

You should see `azureuser` in the Docker group.

---

# Step 7 — Refresh Jenkins Agent Session

This step is important.

Adding a user to the Docker group does not automatically give an already-running Jenkins process the new group membership.

We need to restart/reconnect the Jenkins agent.

First, from Jenkins UI:

```text
Manage Jenkins
    ↓
Nodes
    ↓
AgentB
```

Stop/disconnect AgentB and reconnect it.

Then return to AgentB and verify:

```bash
id
```

Look for:

```text
docker
```

in the groups.

---

# Step 8 — Test Docker Without sudo

### [AGENT B]

Run:

```bash
docker ps
```

This should work **without `sudo`**.

This is critical because Jenkins will eventually execute commands such as:

```bash
docker build
docker push
docker run
```

without sudo.

Do not proceed until this works.

---

# PHASE 6 — Check Existing Tomcat

## Step 9 — Check Tomcat

### [AGENT B]

Run:

```bash
sudo systemctl status tomcat --no-pager
```

We expect your existing Tomcat installation to be present.

Why are we checking?

Because our Docker container will eventually use:

```text
AgentB:8080
```

and the existing Tomcat may already be using that port.

---

# Step 10 — Check Port 8080

### [AGENT B]

Run:

```bash
sudo ss -lntp | grep 8080
```

We are checking who is using port 8080.

Do not stop anything yet.

---

# PHASE 7 — Stop Old Tomcat

## Step 11 — Stop Existing Tomcat

### [AGENT B]

Once we confirm that Tomcat is the process using 8080, run:

```bash
sudo systemctl stop tomcat
```

Then:

```bash
sudo systemctl disable tomcat
```

The second command prevents Tomcat from automatically starting after a reboot.

---

# Step 12 — Verify Port 8080 Is Free

### [AGENT B]

Run:

```bash
sudo ss -lntp | grep 8080
```

Ideally, there should be no output.

Now port 8080 is available for:

```text
AgentB
   ↓
Docker
   ↓
Container
   ↓
Tomcat
```

---

# PHASE 8 — Prepare Docker Hub

## Step 13 — Create Docker Hub Repository

### [DOCKER HUB]

Log in to your Docker Hub account:

```text
discoverdevops
```

Create a repository:

```text
addressbook
```

Our Docker image will therefore be:

```text
discoverdevops/addressbook
```

Do not create anything else yet.

---

# PHASE 9 — Create Docker Hub Access Token

## Step 14 — Create Docker Hub Personal Access Token

We should **not use your Docker Hub password in Jenkins**.

Create a Docker Hub Personal Access Token.

The token will be used as the Jenkins credential secret.

Conceptually:

```text
Docker Hub
    |
    | Personal Access Token
    v
Jenkins Credential
    |
    v
Jenkinsfile
```

Do not put the token into:

```text
Jenkinsfile
GitHub
Dockerfile
README
```

---

# PHASE 10 — Jenkins Credential

## Step 15 — Create Jenkins Credential

### [JENKINS UI]

Go to:

```text
Manage Jenkins
    ↓
Credentials
    ↓
System
    ↓
Global credentials
    ↓
Add Credentials
```

Select:

```text
Kind:
Username with password
```

Enter:

```text
Username:
discoverdevops
```

Password:

```text
<your Docker Hub Personal Access Token>
```

Credential ID:

```text
dockerhub-creds
```

Description:

```text
Docker Hub credentials for AddressBook
```

Click:

```text
Create
```

Important:

The Jenkinsfile will refer to:

```text
dockerhub-creds
```

It will never contain the actual token.

---

# PHASE 11 — Prepare Local Git Repository

## Step 16 — Go to Existing Repository

### [LAPTOP]

We are using the same repository.

Run:

```bash
cd /z/2026/Scaler/DevOpsTool_2/Day_5/addressbook
```

Verify:

```bash
pwd
```

Then:

```bash
ls
```

You should have:

```text
README.md
pom.xml
Jenkinsfile
src/
```

---

# PHASE 12 — Create Dockerfile

## Step 17 — Create Dockerfile

### [LAPTOP]

Run:

```bash
touch Dockerfile
```

Verify:

```bash
ls
```

You should now see:

```text
Dockerfile
Jenkinsfile
README.md
pom.xml
src/
```

---

# Step 18 — Edit Dockerfile

### [LAPTOP]

Open:

```bash
code Dockerfile
```

Put this inside:

```dockerfile
FROM tomcat:9.0-jdk21-temurin

RUN rm -rf /usr/local/tomcat/webapps/*

COPY target/addressbook.war /usr/local/tomcat/webapps/addressbook.war

EXPOSE 8080
```

Save.

---

# PHASE 13 — Understand Dockerfile

Before continuing, teach this.

```dockerfile
FROM tomcat:9.0-jdk21-temurin
```

Means:

> Start with an image that already contains Tomcat and Java 21.

Then:

```dockerfile
RUN rm -rf /usr/local/tomcat/webapps/*
```

Means:

> Remove the default Tomcat applications.

Then:

```dockerfile
COPY target/addressbook.war /usr/local/tomcat/webapps/addressbook.war
```

Means:

> Put our AddressBook WAR into Tomcat.

Then:

```dockerfile
EXPOSE 8080
```

Means:

> The application uses container port 8080.

---

# PHASE 14 — Modify Jenkinsfile

## Step 19 — Replace Jenkinsfile

### [LAPTOP]

Open:

```bash
code Jenkinsfile
```

Replace the current Jenkinsfile with:

```groovy
pipeline {

    agent {
        label 'AgentB'
    }

    environment {
        DOCKER_IMAGE = 'discoverdevops/addressbook'
        CONTAINER_NAME = 'addressbook'
        HOST_PORT = '8080'
        CONTAINER_PORT = '8080'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    echo "===== CHECKOUT ====="
                    hostname
                    git log -1 --oneline
                '''
            }
        }

        stage('Compile') {
            steps {
                sh '''
                    echo "===== COMPILE ====="
                    mvn -B clean compile
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    echo "===== TEST ====="
                    mvn -B test
                '''
            }

            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Package') {
            steps {
                sh '''
                    echo "===== PACKAGE ====="
                    mvn -B package -DskipTests
                    ls -lh target/addressbook.war
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    echo "===== DOCKER BUILD ====="

                    docker build \
                      -t ${DOCKER_IMAGE}:${BUILD_NUMBER} \
                      -t ${DOCKER_IMAGE}:latest \
                      .
                '''
            }
        }

        stage('Docker Login and Push') {
            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {

                    sh '''
                        echo "===== DOCKER LOGIN ====="

                        echo "$DOCKER_PASSWORD" | docker login \
                          -u "$DOCKER_USERNAME" \
                          --password-stdin

                        echo "===== DOCKER PUSH ====="

                        docker push ${DOCKER_IMAGE}:${BUILD_NUMBER}
                        docker push ${DOCKER_IMAGE}:latest

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy Container') {
            steps {
                sh '''
                    echo "===== DEPLOY CONTAINER ====="

                    docker rm -f ${CONTAINER_NAME} || true

                    docker pull ${DOCKER_IMAGE}:${BUILD_NUMBER}

                    docker run -d \
                      --name ${CONTAINER_NAME} \
                      -p ${HOST_PORT}:${CONTAINER_PORT} \
                      ${DOCKER_IMAGE}:${BUILD_NUMBER}

                    echo "===== CONTAINER ====="

                    docker ps
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    echo "===== VERIFY ====="

                    for i in $(seq 1 30); do

                        code=$(curl -s -o /dev/null \
                          -w '%{http_code}' \
                          http://localhost:8080/addressbook/ || true)

                        echo "Attempt $i: HTTP $code"

                        if [ "$code" = "200" ]; then
                            echo "DEPLOYMENT VERIFIED"
                            exit 0
                        fi

                        sleep 2

                    done

                    echo "DEPLOYMENT FAILED"
                    docker logs ${CONTAINER_NAME} || true
                    exit 1
                '''
            }
        }
    }
}
```

Save the file.

---

# PHASE 15 — Understand the New Pipeline

The important difference from the previous Jenkinsfile is:

```groovy
agent {
    label 'AgentB'
}
```

Everything happens on AgentB.

The pipeline is:

```text
AgentB
   |
   +-- Checkout
   |
   +-- Compile
   |
   +-- Test
   |
   +-- Package WAR
   |
   +-- Docker Build
   |
   +-- Docker Login
   |
   +-- Docker Push
   |
   +-- Docker Pull
   |
   +-- Docker Run
   |
   +-- Verify
```

---

# PHASE 16 — Understand Image Versioning

This is very important for your demonstration.

Jenkins gives every build a number:

```text
BUILD_NUMBER
```

Therefore:

```text
Build #1
    ↓
discoverdevops/addressbook:1
```

Next:

```text
Build #2
    ↓
discoverdevops/addressbook:2
```

Next:

```text
Build #3
    ↓
discoverdevops/addressbook:3
```

This gives us versioned Docker images.

We also create:

```text
discoverdevops/addressbook:latest
```

but deployment uses the specific build number.

---

# PHASE 17 — Commit Docker Changes

## Step 20 — Check Git

### [LAPTOP]

Run:

```bash
git status
```

You should see:

```text
Dockerfile
Jenkinsfile
```

as modified/untracked changes.

---

# Step 21 — Add Files

Run:

```bash
git add Dockerfile Jenkinsfile
```

Then:

```bash
git status
```

---

# Step 22 — Commit

Run:

```bash
git commit -m "Dockerize AddressBook application"
```

---

# Step 23 — Push

Run:

```bash
git push origin main
```

Now GitHub contains:

```text
addressbook/
├── Dockerfile
├── Jenkinsfile
├── pom.xml
└── src/
```

---

# PHASE 18 — Jenkins Pipeline

## Step 24 — Run Jenkins

### [JENKINS UI]

Open:

```text
addressbook-pipeline
```

Click:

```text
Build Now
```

Watch the stages.

Expected:

```text
Checkout
Compile
Test
Package
Docker Build
Docker Login and Push
Deploy Container
Verify Deployment
```

Do not troubleshoot or change anything until we see the result.

---

# PHASE 19 — Verify Docker Image on AgentB

## Step 25 — Check Images

### [AGENT B]

Run:

```bash
docker images
```

You should see:

```text
discoverdevops/addressbook
```

with a build-number tag.

For example:

```text
discoverdevops/addressbook   1
discoverdevops/addressbook   latest
```

---

# Step 26 — Check Container

Run:

```bash
docker ps
```

You should see:

```text
addressbook
```

---

# Step 27 — Check Exact Image Used

Run:

```bash
docker inspect addressbook --format '{{.Config.Image}}'
```

If this was Jenkins Build #1:

```text
discoverdevops/addressbook:1
```

This proves exactly which image is running.

---

# Step 28 — Check Container Logs

Run:

```bash
docker logs addressbook
```

Tomcat startup messages should appear.

---

# PHASE 20 — Internet Verification

## Step 29 — Browser

### [BROWSER]

Open:

```text
http://20.244.3.100:8080/addressbook/
```

The AddressBook application should load.

If it doesn't load, **stop here**. We will troubleshoot before continuing.

---

# PHASE 21 — Demonstrate Continuous Deployment

Now we deliberately change the application.

## Step 30 — Modify AddressBook

### [LAPTOP]

Open the Java source:

```text
src/main/java/com/example/addressbook/AddressBook.java
```

or the appropriate source file containing the contacts.

Add:

```text
Rahul Choubey
+91-90001-14685
```

Save.

---

# Step 31 — Commit the Application Change

Run:

```bash
git add .
```

Then:

```bash
git commit -m "Add Rahul contact"
```

---

# Step 32 — Push the Change

Run:

```bash
git push origin main
```

---

# PHASE 22 — Run Jenkins Again

## Step 33 — Jenkins Build #2

### [JENKINS UI]

Run:

```text
Build Now
```

Now the build number should increase.

For example:

```text
Build #1
```

becomes:

```text
Build #2
```

The Docker image becomes:

```text
discoverdevops/addressbook:2
```

---

# Step 34 — Show Docker Hub

### [DOCKER HUB]

Open the `addressbook` repository.

You should see:

```text
1
2
latest
```

Now explain:

> "The source code changed, Jenkins created a new Docker image, and that new image was pushed to Docker Hub."

---

# Step 35 — Show the New Container

### [AGENT B]

Run:

```bash
docker inspect addressbook --format '{{.Config.Image}}'
```

Expected:

```text
discoverdevops/addressbook:2
```

Then:

```bash
docker ps
```

The container is running.

---

# Step 36 — Show the Application Change

### [BROWSER]

Refresh:

```text
http://20.244.3.100:8080/addressbook/
```

You should now see the changed application with the new contact.

---

# Final Teaching Story

Now tell your students:

> "We started with our existing Java application.
>
> Maven builds and tests the application.
>
> Instead of deploying the WAR directly to a Tomcat installation on the VM, we package that WAR inside a Docker image.
>
> Jenkins creates the Docker image.
>
> Jenkins authenticates to Docker Hub using a Jenkins-managed credential.
>
> Jenkins pushes the image to Docker Hub.
>
> Jenkins then deploys that exact version as a container on AgentB.
>
> Finally, Jenkins verifies that the application is responding with HTTP 200.
>
> When I change the source code and push again, Jenkins creates a new image, pushes the new version, replaces the old container, and the browser shows the new application."

Final architecture:

```text
Developer
    |
    | git push
    v
GitHub
    |
    v
Jenkins
    |
    v
AgentB
    |
    +---- Maven Build
    |
    +---- Maven Test
    |
    +---- Docker Build
    |          |
    |          v
    |     Docker Image
    |          |
    |          v
    |      Docker Hub
    |          |
    |          v
    |      Docker Pull
    |          |
    |          v
    |   Docker Container
    |          |
    |       Port 8080
    |          |
    |          v
    |       Internet
```

**Important:** We will not jump through this document all at once. For the actual live lab, start at **Step 1**, execute it, and stop. Send me the output. Then we move to Step 2.

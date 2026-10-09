
## Activity 1 — Install and Verify Jenkins LTS

We will do the entire Jenkins installation now. These are based on the current official Jenkins Ubuntu instructions. [Jenkins](https://www.jenkins.io/doc/book/installing/linux/)

### Step 1.1 — Confirm Java

You already did this, but verify once:

```bash
java -version
```

You should have Java 21.

---

### Step 1.2 — Install the Jenkins repository key

Run:

```bash
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
```

Verify:

```bash
ls -l /etc/apt/keyrings/jenkins-keyring.asc
```

---

### Step 1.3 — Add Jenkins LTS repository

Run:

```bash
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
```

Verify:

```bash
cat /etc/apt/sources.list.d/jenkins.list
```

You should see:

```text
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
```

---

### Step 1.4 — Update package repository

```bash
sudo apt update
```

Make sure you don't get a repository/signature error.

---

### Step 1.5 — Install Jenkins

```bash
sudo apt install jenkins -y
```

This creates the Jenkins service and the `jenkins` Linux user. The official package configures Jenkins as a systemd service and uses port **8080** by default. [Jenkins](https://www.jenkins.io/doc/book/installing/linux/)

---

### Step 1.6 — Enable Jenkins at boot

```bash
sudo systemctl enable jenkins
```

---

### Step 1.7 — Start Jenkins

```bash
sudo systemctl start jenkins
```

---

### Step 1.8 — Verify Jenkins service

```bash
sudo systemctl status jenkins
```

You want:

```text
Active: active (running)
```

Press **Q** to exit the status screen.

---

### Step 1.9 — Verify Jenkins is listening on port 8080

Run:

```bash
sudo ss -lntp | grep 8080
```

You should see something listening on:

```text
:8080
```

---

### Step 1.10 — Get the initial Jenkins administrator password

Run:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

**Keep this password.**

Don't post the password here.

---

### Step 1.11 — Open Jenkins in your browser

Your EC2 currently has the public IP shown in your screenshot:

```text
3.111.150.122
```

So from your laptop:

```text
http://3.111.150.122:8080
```

Your Security Group must allow:

```text
TCP 8080 → YOUR IP
```

Then you should get:

**Unlock Jenkins**

Paste the password from Step 1.10.

---

### Step 1.12 — Jenkins initial setup

Choose:

**Install suggested plugins**

Let Jenkins complete the plugin installation.

Then create your first administrator account.

For example:

```text
Username: admin
Password: <your password>
Full name: Rahul Chaubey
Email: <your email>
```

After that, Jenkins should open its dashboard.

---

### Step 1.13 — Final verification

From the EC2 server:

```bash
sudo systemctl is-active jenkins
```

Expected:

```text
active
```

And:

```bash
curl -I http://localhost:8080
```

You should get an HTTP response from Jenkins.

---

### What we have accomplished

At the end of this activity:

```text
AWS EC2
   │
   ├── Ubuntu 24.04
   ├── Java 21
   └── Jenkins LTS
          │
          └── Port 8080
```

The current Jenkins LTS repository is the **`debian-stable`** repository, and the current Jenkins package line supports Java 21. [Jenkins](https://www.jenkins.io/doc/book/installing/linux/)

**Start with Step 1.2 now.** If anything fails, send me something like **“Step 1.2 error”** followed by the output.

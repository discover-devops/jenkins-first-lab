# Jenkins Controller → Agent: Passwordless SSH Setup

## Objective

Configure passwordless SSH from the **Jenkins Controller** to a Jenkins Agent.

This allows Jenkins to connect to the agent automatically without asking for an SSH password.

### Architecture

```text
Jenkins Controller
        |
        | SSH / ED25519
        | Passwordless
        v
   Jenkins Agent
```

Example used in this lab:

```text
Controller:
Hostname: JenkinsController
IP:       20.40.57.112

Agent:
Hostname: AgentA
IP:       20.40.58.37

Agent OS User:
azureuser
```

---

# Step 1 — Verify SSH Server on Agent

Login to the agent:

```bash
ssh azureuser@20.40.58.37
```

Check SSH service:

```bash
sudo systemctl status ssh
```

Expected:

```text
Active: active (running)
```

If SSH is not installed/running:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

---

# Step 2 — Verify Java on the Agent

Jenkins agents require Java.

Run:

```bash
java -version
```

For this lab we installed OpenJDK 21.

Example:

```text
openjdk version "21.0.12.1"
```

If Java is missing:

```bash
sudo apt update
sudo apt install -y openjdk-21-jre
```

Then verify:

```bash
java -version
```

---

# Step 3 — Identify the Jenkins OS User

On the Jenkins Controller:

```bash
ps -ef | grep jenkins
```

Example:

```text
jenkins  9996  1  ... /usr/bin/java ... /usr/share/java/jenkins.war
```

This confirms that Jenkins is running as the Linux user:

```text
jenkins
```

### Important

The SSH key should belong to the **`jenkins` OS user**, not the administrator/login user.

---

# Step 4 — Generate an SSH Key for Jenkins

On the Jenkins Controller:

```bash
sudo -u jenkins ssh-keygen -t ed25519
```

When prompted:

```text
Enter file in which to save the key:
```

Press **Enter** to accept:

```text
/var/lib/jenkins/.ssh/id_ed25519
```

For the passphrase:

```text
Enter passphrase:
```

Press **Enter**.

Confirm the empty passphrase by pressing **Enter** again.

Two files are created:

```text
/var/lib/jenkins/.ssh/id_ed25519
/var/lib/jenkins/.ssh/id_ed25519.pub
```

### Key structure

```text
Private Key:
id_ed25519

Public Key:
id_ed25519.pub
```

The **private key stays on the Jenkins Controller**.

The **public key is copied to the Agent**.

---

# Step 5 — Copy the Public Key to the Agent

From the Jenkins Controller:

```bash
sudo -u jenkins ssh-copy-id azureuser@20.40.58.37
```

The first time, SSH may ask:

```text
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Enter:

```text
yes
```

It will then ask for the Agent's `azureuser` password.

Enter the password once.

Expected result:

```text
Number of key(s) added: 1
```

The public key is now added to:

```text
/home/azureuser/.ssh/authorized_keys
```

on the Agent.

---

# Step 6 — Test Passwordless SSH

This is the most important validation step.

From the Jenkins Controller:

```bash
sudo -u jenkins ssh azureuser@20.40.58.37
```

If configured correctly, SSH should connect directly without asking for the Agent password.

You should see:

```text
azureuser@AgentA:~$
```

Verify the hostname:

```bash
hostname
```

Expected:

```text
AgentA
```

Exit the SSH session:

```bash
exit
```

---

# Step 7 — Understand What We Configured

The final configuration is:

```text
                 Jenkins Controller
                 20.40.57.112
                       |
                       |
                SSH Private Key
                /var/lib/jenkins/
                    .ssh/
                       |
                       v
                 AgentA
                 20.40.58.37
                       |
                       |
              ~/.ssh/authorized_keys
```

The important relationship is:

```text
Controller
    |
    | private key
    v
Agent
    |
    | public key
    v
authorized_keys
```

More precisely:

```text
Controller:
    /var/lib/jenkins/.ssh/id_ed25519
                         |
                         | matches
                         v
Agent:
    /home/azureuser/.ssh/authorized_keys
```

---

# Adding Another Agent Tomorrow

Suppose we provision:

```text
AgentB
20.40.59.40
```

We **do not need to generate a new SSH key on the Controller**.

The existing Jenkins Controller key can be used for another agent.

Assuming AgentB has:

```text
User: azureuser
IP:   20.40.59.40
```

Run from the Jenkins Controller:

```bash
sudo -u jenkins ssh-copy-id azureuser@20.40.59.40
```

Enter the AgentB password once.

Then test:

```bash
sudo -u jenkins ssh azureuser@20.40.59.40
```

Verify:

```bash
hostname
```

Expected:

```text
AgentB
```

That's it.

---

# Reusable Procedure for AgentA / AgentB / AgentC

For every new Jenkins agent:

### On the Agent

```bash
sudo apt update
sudo apt install -y openjdk-21-jre openssh-server
sudo systemctl enable --now ssh
java -version
```

### On the Jenkins Controller

```bash
sudo -u jenkins ssh-copy-id azureuser@<AGENT-IP>
```

Then:

```bash
sudo -u jenkins ssh azureuser@<AGENT-IP>
```

Verify:

```bash
hostname
```

---

# Important Security Notes

### 1. Never copy the private key to the Agent

Do **not** copy:

```text
/var/lib/jenkins/.ssh/id_ed25519
```

to the Agent.

Only the public key should be installed on the Agent.

### 2. The private key belongs to Jenkins

The key should be owned by:

```text
jenkins
```

and protected appropriately.

### 3. Password is only needed during initial setup

The Agent's SSH password is used when running:

```bash
ssh-copy-id
```

After successful configuration, Jenkins can authenticate using the SSH key.

### 4. Test manually before configuring Jenkins

Always verify:

```bash
sudo -u jenkins ssh azureuser@<AGENT-IP>
```

before troubleshooting the Jenkins Node configuration.

If manual SSH works as the `jenkins` user, we have eliminated an entire category of Jenkins configuration problems.

---

# Lab Checkpoint

Before proceeding to Jenkins Node configuration, confirm all of these:

```text
[✓] Agent has Java
[✓] Agent has SSH server
[✓] Jenkins Controller has ED25519 key
[✓] Public key copied to Agent
[✓] Controller can SSH to Agent
[✓] SSH works as the jenkins OS user
[✓] No password required during SSH login
```

Once all checks pass, the environment is ready for:

```text
Jenkins
   ↓
Manage Jenkins
   ↓
Nodes
   ↓
New Node
   ↓
Configure Agent
   ↓
Launch agent via SSH
```


# Runbook 02 — Add a Jenkins Agent Using SSH

## Objective

In this lab, we will add an Ubuntu server as a Jenkins Agent and configure Jenkins Controller to connect to it using SSH.

At the end of this exercise:

```text
Jenkins Controller
20.40.57.112
        |
        | SSH
        | ED25519 authentication
        |
        v
Jenkins Agent
AgentA
20.40.58.37
```

Jenkins will be able to execute jobs on `AgentA`.

---

# 1. Lab Environment

We have two Ubuntu machines.

| Component          | Hostname          | IP             |
| ------------------ | ----------------- | -------------- |
| Jenkins Controller | JenkinsController | `20.40.57.112` |
| Jenkins Agent      | AgentA            | `20.40.58.37`  |

AgentA uses:

```text
OS User: azureuser
Java: OpenJDK 21
```

The Jenkins Controller runs Jenkins as:

```text
jenkins
```

We will therefore configure SSH access from:

```text
jenkins@JenkinsController
```

to:

```text
azureuser@AgentA
```

---

# 2. Prepare the Agent

## 2.1 Verify hostname

On AgentA:

```bash
hostname
```

Expected:

```text
AgentA
```

---

## 2.2 Install Java

Jenkins agents require Java.

Install OpenJDK 21:

```bash
sudo apt update
sudo apt install -y openjdk-21-jre
```

Verify:

```bash
java -version
```

Expected:

```text
openjdk version "21.x.x"
```

---

# 3. Verify SSH Server on Agent

On AgentA:

```bash
sudo systemctl status ssh
```

Expected:

```text
Active: active (running)
```

If SSH is not installed:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

---

# 4. Why Do We Need Passwordless SSH?

Jenkins needs to connect to the Agent automatically.

We don't want Jenkins to stop and ask for an SSH password every time it needs to launch the agent.

Therefore, we configure:

```text
Jenkins Controller
        |
        | SSH private key
        v
AgentA
        |
        | authorized_keys
        v
SSH authentication
```

The important point is:

> Passwordless SSH means passwordless authentication, not unauthenticated access.

The connection is still authenticated using an SSH key.

---

# 5. Why Do We Generate the SSH Key on the Controller?

Jenkins is running on the Controller as the Linux user:

```text
jenkins
```

We verify this with:

```bash
ps -ef | grep jenkins
```

Example:

```text
jenkins  9996  1 ... /usr/bin/java ... jenkins.war
```

Therefore, the SSH key should belong to the `jenkins` user.

Generate the key:

```bash
sudo -u jenkins ssh-keygen -t ed25519
```

Accept the default location:

```text
/var/lib/jenkins/.ssh/id_ed25519
```

Leave the passphrase empty so Jenkins can authenticate automatically.

Two files are created:

```text
/var/lib/jenkins/.ssh/id_ed25519
/var/lib/jenkins/.ssh/id_ed25519.pub
```

---

# 6. Why ED25519 Instead of RSA?

For a new SSH configuration, we use:

```bash
ssh-keygen -t ed25519
```

rather than:

```bash
ssh-keygen -t rsa
```

ED25519 is a modern SSH public-key algorithm and is a good default for new configurations.

The important concept for students is:

```text
Private Key → stays on Controller

Public Key → goes to Agent
```

Never copy the private key to the Agent.

---

# 7. Copy the Public Key to AgentA

From the Jenkins Controller:

```bash
sudo -u jenkins ssh-copy-id azureuser@20.40.58.37
```

The Agent password is required **once** during this setup.

After successful execution, you should see:

```text
Number of key(s) added: 1
```

The public key is added to:

```text
/home/azureuser/.ssh/authorized_keys
```

on AgentA.

---

# 8. Verify Passwordless SSH

From the Jenkins Controller:

```bash
sudo -u jenkins ssh azureuser@20.40.58.37
```

It should connect without asking for the Agent password.

Then:

```bash
hostname
```

Expected:

```text
AgentA
```

Exit:

```bash
exit
```

At this point we have proved:

```text
jenkins user
     |
     | passwordless SSH
     v
azureuser@AgentA
```

---

# 9. Create AgentA in Jenkins

Open:

```text
Jenkins
→ Manage Jenkins
→ Nodes
→ New Node
```

Create:

```text
Name: AgentA
```

Select:

```text
Permanent Agent
```

---

# 10. Configure Number of Executors

Set:

```text
Number of executors: 1
```

## What is an Executor?

An executor is a **Jenkins job execution slot**.

If we have:

```text
AgentA
Executor = 1
```

AgentA can execute one Jenkins job at a time.

```text
AgentA
└── Executor 1
       └── Job running
```

If we configure:

```text
Executors = 2
```

then two jobs can execute concurrently:

```text
AgentA
├── Executor 1 → Job A
└── Executor 2 → Job B
```

### Is an executor the same as a CPU core?

**No.**

An executor is a Jenkins concept representing how many tasks Jenkins is allowed to run concurrently on that node.

The actual CPU, memory, disk and network capacity of the server still matters.

### Why are we using 1?

For our lab, one executor makes the behavior easy to understand and avoids unnecessary resource contention.

---

# 11. Configure Remote Root Directory

Use:

```text
/home/azureuser/jenkins
```

This is the directory on AgentA where Jenkins will maintain its agent-related files and workspaces.

Conceptually:

```text
/home/azureuser/jenkins
├── workspace
├── remoting
└── agent files
```

---

# 12. Configure Labels

For this lab we use:

```text
AgentA
```

So:

```text
Node Name: AgentA
Label:     AgentA
```

## What is a Label?

A label is a logical identifier that Jenkins can use to select an appropriate node for a job.

For example:

```text
AgentA → AgentA
AgentB → AgentB
```

A job can be configured to run on a particular label.

### Node Name vs Label

These are conceptually different.

```text
Node Name
    ↓
Identifies a Jenkins node

Label
    ↓
Identifies a category/capability used for scheduling
```

In a production environment, labels might be:

```text
linux
docker
kubernetes
java
production
```

Multiple agents can have the same label.

For our first lab, keeping:

```text
Label = AgentA
```

makes the setup simple.

---

# 13. Configure Usage

We leave:

```text
Use this node as much as possible
```

This tells Jenkins that this node can be used for jobs whenever it has an available executor.

Later, Jenkins can be configured with more restrictive node usage policies.

---

# 14. Configure Launch Method

Jenkins provides different ways to establish the Controller-Agent relationship.

The two options we encountered are:

```text
Launch agent by connecting it to the controller

Launch agents via SSH
```

For our lab, we choose:

> **Launch agents via SSH**

---

# 15. Launch Agent by Connecting It to the Controller

In this model, the Agent establishes the connection toward Jenkins.

Conceptually:

```text
Agent
  |
  | initiates connection
  v
Jenkins Controller
```

This is useful when the Controller cannot directly initiate a connection to the Agent.

For example, an Agent may be behind a firewall or NAT:

```text
Jenkins Controller
        X
        |
    Firewall
        |
      Agent
```

If outbound connectivity from the Agent to Jenkins is allowed, the Agent can initiate the connection.

---

# 16. Launch Agent via SSH

This is the option we selected.

The Controller initiates the SSH connection:

```text
Jenkins Controller
        |
        | SSH
        v
     AgentA
```

In our environment:

```text
Controller
20.40.57.112
        |
        | SSH
        v
AgentA
20.40.58.37
```

### Why are we choosing SSH?

Because:

1. AgentA is an Ubuntu VM.
2. SSH server is running.
3. Java is installed.
4. Passwordless SSH has already been configured.
5. The Controller can directly reach AgentA.
6. It clearly demonstrates the Controller → Agent architecture.

Therefore SSH is an excellent fit for this lab.

---

# 17. Configure SSH Host

Under:

```text
Launch agents via SSH
```

configure:

```text
Host:
20.40.58.37
```

The Host tells Jenkins:

> Which machine should I connect to?

It could be an IP address or DNS name.

Example:

```text
20.40.58.37
```

or:

```text
agent-a.example.com
```

---

# 18. Configure Jenkins Credentials

Under:

```text
Credentials
```

we select:

> **SSH Username with private key**

## Why?

Because our authentication model is:

```text
Username:
azureuser

Authentication:
SSH private key
```

Therefore this credential type is exactly what we need.

---

# 19. Why Not Username with Password?

We could technically authenticate using:

```text
azureuser + password
```

but we deliberately configured SSH key authentication.

SSH keys are better suited to automated Jenkins connections because Jenkins does not need to interactively enter a password.

---

# 20. Other Credential Types

Students may see several options.

### Username with password

Used when a service requires:

```text
username + password
```

Not our choice here.

### GitHub App

Used for GitHub authentication and integration.

Not our Controller-Agent SSH authentication.

### SSH Username with private key

Used for:

```text
SSH username + private key
```

**This is our choice.**

### Secret file

Used when Jenkins needs a file-based secret.

Not required here.

### Secret text

Useful for tokens, API keys and other textual secrets.

Not required here.

### Certificate

Used for certificate-based authentication.

Not required here.

---

# 21. Jenkins SSH Credential

We configured:

```text
Scope:
Global

ID:
agentA-ssh-key

Description:
SSH key for AgentA

Username:
azureuser
```

The private key is:

```text
/var/lib/jenkins/.ssh/id_ed25519
```

We paste the contents of that private key into Jenkins using:

```text
Private Key → Enter directly
```

The private key must remain protected.

It should never be shared with students or committed to Git.

---

# 22. Why Is the Passphrase Empty?

We generated the SSH key without a passphrase.

This allows Jenkins to use the key automatically without requiring human interaction.

If the key had a passphrase, Jenkins would need an appropriate mechanism to unlock the key.

For an enterprise environment, credential-management policies should be considered carefully.

For this lab:

```text
Passphrase: empty
```

---

# 23. Host Key Verification

Jenkins also asks:

> How should I verify that the SSH server I'm connecting to is actually the expected server?

We selected:

> **Known hosts file Verification Strategy**

---

# 24. What Is `known_hosts`?

SSH maintains trusted server host keys in:

```text
~/.ssh/known_hosts
```

For the Jenkins user, this is typically:

```text
/var/lib/jenkins/.ssh/known_hosts
```

The basic process is:

```text
Jenkins
   |
   | Connect to AgentA
   v
AgentA presents host key
   |
   v
Jenkins checks known_hosts
   |
   +---- Match → Continue
   |
   +---- No match → Reject
```

---

# 25. Why Are We Choosing Known Hosts?

Because it follows the normal SSH trust model.

It helps protect against connecting to an unexpected or impersonating server.

When we first connected:

```bash
sudo -u jenkins ssh-copy-id azureuser@20.40.58.37
```

SSH asked:

```text
Are you sure you want to continue connecting?
```

We accepted AgentA's host key.

That establishes the server identity in the Jenkins user's SSH configuration.

---

# 26. Other Host Key Verification Options

## Manually provided Key Verification Strategy

The expected server host key is explicitly provided to Jenkins.

Conceptually:

```text
Expected host key
       ↓
Jenkins
       ↓
Compare with Agent host key
```

This gives administrators explicit control over the expected host key.

---

## Manually trusted Key Verification Strategy

This also provides an explicitly controlled trust model where specific host keys are trusted.

This can be useful in tightly controlled environments where administrators want to manage host-key trust explicitly.

---

## Non verifying Verification Strategy

This effectively tells Jenkins:

> Do not verify the SSH server's host key.

It is convenient but removes an important SSH security check.

For example, Jenkins could potentially connect to an unexpected server without detecting the mismatch.

Therefore:

**We do not choose this for our lab.**

We want students to learn the secure SSH model rather than simply disable verification.

---

# 27. Two Different SSH Security Questions

This is an excellent interview/teaching concept.

### Question 1

> Who are you?

Answered by:

```text
Username + Private Key
```

In our lab:

```text
azureuser
+
Jenkins private key
```

### Question 2

> Am I really talking to the correct server?

Answered by:

```text
Host Key Verification
```

In our lab:

```text
known_hosts
```

Therefore:

```text
                 SSH Connection
                       |
             +---------+---------+
             |                   |
       Authentication      Host Verification
             |                   |
       Private Key          known_hosts
             |                   |
        "Who am I?"     "Who is the server?"
```

---

# 28. Final Configuration

Our AgentA configuration is approximately:

```text
Name:
AgentA

Description:
Ubuntu Jenkins build and deployment agent

Executors:
1

Remote root directory:
/home/azureuser/jenkins

Label:
AgentA

Usage:
Use this node as much as possible

Launch method:
Launch agents via SSH

Host:
20.40.58.37

Credentials:
agentA-ssh-key

Username:
azureuser

Host Key Verification:
Known hosts file Verification Strategy
```

---

# 29. Final Architecture

```text
                         Jenkins Controller
                         20.40.57.112
                               |
                               |
                     SSH Authentication
                               |
                 +-------------+-------------+
                 |                           |
          Private Key                  Host Verification
                 |                           |
        agentA-ssh-key                  known_hosts
                 |                           |
                 +-------------+-------------+
                               |
                               v
                            AgentA
                         20.40.58.37
                               |
                    +----------+----------+
                    |                     |
                Executor 1             Workspace
                    |                     |
                    +----------+----------+
                               |
                         Jenkins Jobs
```

---

# 30. Final Validation

After saving the node configuration, Jenkins should show `AgentA` in the Nodes list.

Our current Jenkins Nodes screen shows:

```text
AgentA
Linux (amd64)
Clock Difference: In sync
Free Disk Space: 25.57 GiB
Free Temp Space: 25.57 GiB
```

So the Agent has successfully appeared in Jenkins and Jenkins is obtaining system information from it.

The Controller also shows the built-in node:

```text
Built-In Node
Linux (amd64)
```

Therefore we now have:

```text
Jenkins
├── Built-In Node
│
└── AgentA
    └── Linux amd64
```

---

# 31. Reusable Procedure for AgentB / AgentC

Tomorrow, if you create another Ubuntu VM called `AgentB`, the high-level process is:

```text
1. Create AgentB VM
2. Install Java
3. Start SSH
4. Create/verify Jenkins SSH access
5. Add AgentB in Jenkins
6. Configure its remote directory
7. Configure label
8. Configure SSH launch
9. Add SSH credential
10. Configure host-key verification
11. Save
12. Verify AgentB is online
```

The existing Controller SSH key can be used to authenticate to additional agents, provided their `authorized_keys` is configured appropriately.

---

# Student Questions — Quick Revision

### Q: What is an executor?

A Jenkins job execution slot.

### Q: Is an executor the same as a CPU core?

No.

### Q: Why did we use one executor?

To allow one job at a time and keep the lab simple.

### Q: What is a label?

A logical identifier used by Jenkins to select nodes.

### Q: Why did we use `AgentA` as the label?

To keep this introductory lab simple and make it obvious that the job is being targeted to AgentA.

### Q: Why SSH?

Because our Controller can directly reach the Ubuntu Agent and we want to demonstrate Controller → Agent communication.

### Q: What is the alternative to SSH?

The Agent can establish the connection toward the Controller.

### Q: Why did we create the SSH key as the `jenkins` user?

Because Jenkins itself runs as the `jenkins` Linux user.

### Q: Why ED25519?

It is a modern SSH key algorithm suitable for new configurations.

### Q: Where does the private key stay?

On the Jenkins Controller.

### Q: Where does the public key go?

Into the Agent user's:

```text
~/.ssh/authorized_keys
```

### Q: Why do we need Jenkins credentials?

Jenkins needs a managed way to store and use the SSH authentication information.

### Q: Why "SSH Username with private key"?

Because we authenticate using:

```text
azureuser + SSH private key
```

### Q: What is Host Key Verification?

It verifies the identity of the SSH server.

### Q: Why use `known_hosts`?

It follows the standard SSH trust mechanism and avoids blindly trusting any server.

### Q: Why not use "Non verifying"?

Because it disables server identity verification and is not the security model we want students to learn.

---

## Runbook #2 Checkpoint

At this point, students should understand:

```text
VM
 ↓
Java
 ↓
SSH Server
 ↓
SSH Key Authentication
 ↓
Jenkins Credential
 ↓
Host Key Verification
 ↓
Jenkins Node
 ↓
Agent
 ↓
Executor
 ↓
Jenkins Job
```

**Runbook #1:** Passwordless SSH — Controller → Agent
**Runbook #2:** Add Ubuntu Agent to Jenkins via SSH

Our next lab step is **not application development yet**. I recommend one short checkpoint first: **open AgentA in Jenkins and verify its agent log/status**, so we prove that Jenkins can actually launch and maintain the agent connection before building the CI/CD jobs.

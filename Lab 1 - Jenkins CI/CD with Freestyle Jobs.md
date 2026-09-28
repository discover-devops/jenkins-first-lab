# Lab 1 - Jenkins CI/CD with Freestyle Jobs

**From a developer's code to a running Java application on Tomcat, built entirely with Jenkins Freestyle jobs.**

Lab 2 (a separate runbook) rebuilds this same flow as a Jenkinsfile (Pipeline as Code).

Build Automate Architect - Hands-on Lab

---

## How to Use This Runbook

**Key idea: every step tells you WHERE to run it, WHAT to run, and HOW to know it worked.**

- Work through the topics in order. Do not skip ahead. Every topic ends with a **Validate** checklist. Do not move on until every box is true.
- Each command block is meant to be copied and pasted as-is. Anything in angle brackets, such as `<GITHUB_USER>`, is a placeholder you must replace with your own value.
- Every block is tagged with where it runs:

| Tag | Where to run it |
|---|---|
| **[LAPTOP]** | Git Bash on your laptop (this is your "developer workstation") |
| **[AGENT A]** | SSH session on Agent A (CI / build agent) |
| **[AGENT B]** | SSH session on Agent B (CD / deployment agent) |
| **[JENKINS UI]** | Jenkins web console in your browser |
| **[BROWSER]** | A normal browser tab |

**The teaching sequence we follow:**

First make the application work, then make CI work, then make CD work, and finally connect CI and CD so a single `git push` deploys the application.

---

## Lab Environment

| Component | Role | Address |
|---|---|---|
| Jenkins Controller | Jenkins management and orchestration | `http://<CONTROLLER_PUBLIC_IP>:8080` |
| Agent A | CI / build agent | `20.40.58.37` |
| Agent B | CD / deployment agent (Tomcat runs here) | `20.244.3.100` |
| GitHub | Source-code repository | `https://github.com/<GITHUB_USER>/addressbook` |
| Tomcat on Agent B | Application runtime | `http://20.244.3.100:8080/addressbook/` |

Already done for you: Agent A and Agent B are added to the Jenkins Controller, and Java is installed on both.

**Values you will use throughout (write yours down now):**

| Placeholder | Meaning | Your value |
|---|---|---|
| `<GITHUB_USER>` | Your GitHub username | |
| `<CONTROLLER_PUBLIC_IP>` | Public IP of the Jenkins Controller VM | |
| `<ADMIN_USER>` | The Linux user you use to SSH into the VMs | |

### Final Architecture

```text
Developer (laptop)
      |
      | git push
      v
GitHub
      |
      | Jenkins polls (or webhook)
      v
Jenkins Controller  (schedules jobs, stores artifacts)
      |
      +------------------------+
      |                        |
      v                        v
Agent A (label: ci-agent)   Agent B (label: cd-agent)
  Checkout                    Copy WAR from Controller
  Compile                     Place WAR into Tomcat
  Test                        Verify the application
  Package                          |
      |                            v
      | archive addressbook.war   Tomcat :8080
      +--------> Controller ----> Java App ----> Browser
```

---

# PHASE 1 - Lab Architecture and Application

---

## Topic 1 - Understand the Lab Flow and Prepare Jenkins

**Key idea: the Controller decides and schedules, the Agents do the work.** Jenkins is split into one brain and several hands, so builds never compete with the tool that manages them.

**Default Behavior**
- A fresh Jenkins runs every job on the Controller itself (the Built-In Node).
- This is simple, but builds consume the Controller's CPU and disk, and a bad build script can hurt Jenkins itself.

**What Changes in Our Lab**
- The Controller only orchestrates (we set its executors to 0).
- Each job carries a **label**. Jenkins sends `ci-agent` jobs to Agent A and `cd-agent` jobs to Agent B.
- Agent A holds build tools. Agent B holds Tomcat. Neither has the other's software.

**Why It Matters**
- It mirrors a real company: a build farm is separate from the application servers.
- More build capacity later means adding another agent with the same label. No job changes needed.
- The artifact handoff becomes visible: CI produces the WAR, the Controller stores it, CD consumes it.

### Step 1.1 - Confirm both agents are online

**[JENKINS UI]**

1. Open `http://<CONTROLLER_PUBLIC_IP>:8080` and log in.
2. Go to **Manage Jenkins > Nodes**.
3. You should see the Built-In Node, Agent A and Agent B. Agent A and Agent B must not show a red cross or an "offline" message.

### Step 1.2 - Give each agent a label

**[JENKINS UI]**

1. **Manage Jenkins > Nodes > (Agent A) > Configure**
   - **Labels:** `ci-agent`
   - **Usage:** Only build jobs with label expressions matching this node
   - Click **Save**
2. **Manage Jenkins > Nodes > (Agent B) > Configure**
   - **Labels:** `cd-agent`
   - **Usage:** Only build jobs with label expressions matching this node
   - Click **Save**

### Step 1.3 - Stop builds from running on the Controller

**[JENKINS UI]**

1. **Manage Jenkins > Nodes > Built-In Node > Configure**
2. Set **Number of executors** to `0`.
3. Click **Save**.

Do this only after both agents show as online. With 0 executors, any job without a label will wait forever, which is exactly what we want to teach.

### Step 1.4 - Install the plugin we need for CD

**[JENKINS UI]**

1. **Manage Jenkins > Plugins > Available plugins**
2. Search for **Copy Artifact** and tick it.
3. Click **Install** (no restart needed if Jenkins offers "Install without restart").
4. Also confirm these are already under **Installed plugins**: **Git**, **JUnit**, **Pipeline**. If any is missing, install it the same way.

### Step 1.5 - Open port 8080 on Agent B in Azure

Tomcat will listen on port 8080 on Agent B. Your browser must be able to reach it.

**[Azure Portal]**

1. Open the Agent B virtual machine.
2. Go to **Networking** (Network settings) and **Add inbound port rule**.
3. Source: **My IP address**. Destination port ranges: `8080`. Protocol: **TCP**. Action: **Allow**. Name: `Allow-Tomcat-8080`.
4. Click **Add**.

Jenkins on the Controller also uses 8080. That is fine because they are on different VMs. If anyone ever runs both on one VM, the ports clash. Remember this for troubleshooting.

### Validate Topic 1

- [ ] Agent A and Agent B are online in **Manage Jenkins > Nodes**
- [ ] Agent A has label `ci-agent`, Agent B has label `cd-agent`
- [ ] Built-In Node has 0 executors
- [ ] Copy Artifact, Git, JUnit and Pipeline plugins are installed
- [ ] Inbound rule for port 8080 exists on Agent B

---

## Topic 2 - Create the Java Tomcat Application (AddressBook)

**Key idea: a Maven project produces a WAR file, and a WAR is just a zip that Tomcat knows how to run.**

**Default Behavior**
- Maven reads `pom.xml`, follows a fixed lifecycle (compile, test, package) and writes results into a `target/` folder.
- Because the `pom.xml` says `packaging` is `war`, the last step produces `target/addressbook.war`.

**What We Build**
- A tiny AddressBook: a `Contact` class, an `AddressBook` class, five unit tests and one JSP page that lists contacts.

**Why It Matters**
- The unit tests give the Test stage something real to run.
- The page shows a "Version" heading and the host name, so you can visually prove a new build was deployed and where.

### Project Structure

```text
addressbook/
  pom.xml
  .gitignore
  src/
    main/
      java/com/example/addressbook/Contact.java
      java/com/example/addressbook/AddressBook.java
      webapp/index.jsp
    test/
      java/com/example/addressbook/AddressBookTest.java
```

### Step 2.1 - Create the folders

**[LAPTOP]**

```bash
mkdir -p addressbook && cd addressbook
mkdir -p src/main/java/com/example/addressbook
mkdir -p src/main/webapp
mkdir -p src/test/java/com/example/addressbook
```

### Step 2.2 - Create `pom.xml`

**[LAPTOP]** (run inside the `addressbook` folder)

```bash
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.example</groupId>
  <artifactId>addressbook</artifactId>
  <version>1.0</version>
  <packaging>war</packaging>
  <name>AddressBook</name>

  <properties>
    <maven.compiler.release>11</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.10.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <finalName>addressbook</finalName>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.2.5</version>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-war-plugin</artifactId>
        <version>3.4.0</version>
        <configuration>
          <failOnMissingWebXml>false</failOnMissingWebXml>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF
```

The line `<finalName>addressbook</finalName>` is why the WAR is named exactly `addressbook.war` (no version number). Tomcat uses the WAR name as the URL path, so the app will live at `/addressbook/`.

### Step 2.3 - Create the Java classes

**[LAPTOP]**

```bash
cat > src/main/java/com/example/addressbook/Contact.java <<'EOF'
package com.example.addressbook;

public class Contact {
    private final String name;
    private final String phone;
    private final String email;

    public Contact(String name, String phone, String email) {
        this.name = name;
        this.phone = phone;
        this.email = email;
    }

    public String getName()  { return name; }
    public String getPhone() { return phone; }
    public String getEmail() { return email; }
}
EOF
```

```bash
cat > src/main/java/com/example/addressbook/AddressBook.java <<'EOF'
package com.example.addressbook;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class AddressBook {
    private final List<Contact> contacts = new ArrayList<>();

    public void add(Contact contact) {
        if (contact == null) {
            throw new IllegalArgumentException("contact must not be null");
        }
        contacts.add(contact);
    }

    public int size() {
        return contacts.size();
    }

    public List<Contact> getAll() {
        return Collections.unmodifiableList(contacts);
    }

    public Contact findByName(String name) {
        for (Contact c : contacts) {
            if (c.getName().equalsIgnoreCase(name)) {
                return c;
            }
        }
        return null;
    }
}
EOF
```

### Step 2.4 - Create the unit tests

**[LAPTOP]**

```bash
cat > src/test/java/com/example/addressbook/AddressBookTest.java <<'EOF'
package com.example.addressbook;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class AddressBookTest {

    @Test
    void newAddressBookIsEmpty() {
        assertEquals(0, new AddressBook().size());
    }

    @Test
    void addingContactIncreasesSize() {
        AddressBook book = new AddressBook();
        book.add(new Contact("Asha Rao", "+91-90000-00001", "asha@example.com"));
        assertEquals(1, book.size());
    }

    @Test
    void findByNameIgnoresCase() {
        AddressBook book = new AddressBook();
        book.add(new Contact("Asha Rao", "+91-90000-00001", "asha@example.com"));
        assertNotNull(book.findByName("asha rao"));
    }

    @Test
    void findUnknownNameReturnsNull() {
        assertNull(new AddressBook().findByName("Nobody"));
    }

    @Test
    void nullContactIsRejected() {
        assertThrows(IllegalArgumentException.class, () -> new AddressBook().add(null));
    }
}
EOF
```

### Step 2.5 - Create the web page

**[LAPTOP]**

```bash
cat > src/main/webapp/index.jsp <<'EOF'
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="com.example.addressbook.*" %>
<%
    AddressBook book = new AddressBook();
    book.add(new Contact("Asha Rao", "+91-90000-00001", "asha@example.com"));
    book.add(new Contact("Vikram Shah", "+91-90000-00002", "vikram@example.com"));
    book.add(new Contact("Meera Iyer", "+91-90000-00003", "meera@example.com"));

    String host = "unknown";
    try {
        host = java.net.InetAddress.getLocalHost().getHostName();
    } catch (Exception e) {
        host = "unknown";
    }
%>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>AddressBook</title>
  <style>
    body  { font-family: Arial, sans-serif; margin: 40px; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #999; padding: 8px 14px; text-align: left; }
    th    { background: #eee; }
    .meta { color: #555; margin-top: 20px; }
  </style>
</head>
<body>
  <h1>AddressBook - Version 1</h1>
  <p>Contacts stored: <%= book.size() %></p>
  <table>
    <tr><th>Name</th><th>Phone</th><th>Email</th></tr>
    <% for (Contact c : book.getAll()) { %>
    <tr>
      <td><%= c.getName() %></td>
      <td><%= c.getPhone() %></td>
      <td><%= c.getEmail() %></td>
    </tr>
    <% } %>
  </table>
  <p class="meta">Served by host: <%= host %></p>
</body>
</html>
EOF
```

### Step 2.6 - Create `.gitignore`

**[LAPTOP]**

```bash
cat > .gitignore <<'EOF'
target/
*.class
.idea/
*.iml
EOF
```

Build output must never be committed to Git. CI creates it fresh every time.

### Step 2.7 - Validate the application by hand on Agent A

**Key idea: never automate something you have not done by hand first.** If Maven fails manually, it will fail in Jenkins too, and you will lose time guessing why.

We will do this after the code is on GitHub (Topic 3), so continue to Topic 3 now and come back to Step 2.7 right after Step 3.4.

---

## Topic 3 - Create the GitHub Repository and Push the Code

**Key idea: GitHub is the single source of truth. Jenkins never receives code from your laptop, it always pulls from GitHub.**

### Step 3.1 - Create an empty repository

**[BROWSER]**

1. Go to `https://github.com/new`
2. **Repository name:** `addressbook`
3. **Visibility:** Public (so Jenkins agents can clone without credentials in this lab)
4. Do **not** tick "Add a README", ".gitignore" or "license". The repository must be empty.
5. Click **Create repository**.

### Step 3.2 - Create a Personal Access Token (for pushing)

GitHub no longer accepts your account password for `git push`.

**[BROWSER]**

1. GitHub: **Settings > Developer settings > Personal access tokens > Tokens (classic) > Generate new token (classic)**
2. **Note:** `jenkins-lab`, **Expiration:** 30 days, tick the **repo** scope.
3. Click **Generate token** and copy it now. You will paste it as the "password" in the next step.

### Step 3.3 - Push the code

**[LAPTOP]** (inside the `addressbook` folder)

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

git init -b main
git add .
git commit -m "Initial AddressBook application"
git remote add origin https://github.com/<GITHUB_USER>/addressbook.git
git push -u origin main
```

When asked for a username, enter your GitHub username. When asked for a password, paste the token.

### Step 3.4 - Verify the source code

**[BROWSER]** Open `https://github.com/<GITHUB_USER>/addressbook` and confirm you see `pom.xml`, `src/` and `.gitignore`, and that there is **no** `target/` folder.

### Step 2.7 (continued) - Manual build on Agent A

**[AGENT A]**

```bash
ssh <ADMIN_USER>@20.40.58.37
```

Check Java. You need a **JDK** (it must print a `javac` version), not just a JRE:

```bash
java -version
javac -version
```

If `javac` is not found, install a JDK:

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk
```

Install Git and Maven:

```bash
sudo apt-get update
sudo apt-get install -y git maven
mvn -version
```

Clone and build by hand:

```bash
git clone https://github.com/<GITHUB_USER>/addressbook.git ~/manual-check
cd ~/manual-check
mvn -B clean package
```

Look for `Tests run: 5, Failures: 0, Errors: 0` and `BUILD SUCCESS`. Then confirm the WAR:

```bash
ls -l target/addressbook.war
jar tf target/addressbook.war | head -20
```

Clean up so nothing confuses the Jenkins jobs later:

```bash
cd ~
rm -rf ~/manual-check
exit
```

### Validate Phase 1

- [ ] Repository on GitHub contains the project and no `target/` folder
- [ ] `mvn -B clean package` succeeds on Agent A with 5 tests passing
- [ ] `target/addressbook.war` was produced during the manual build
- [ ] `git`, `mvn` and a JDK are available on Agent A

---

# PHASE 2 - CI Pipeline: Individual Jobs

**Key idea for the whole phase: build the assembly line one station at a time.** We create four small jobs so you can see what each stage does and where it breaks. In Phase 3 we combine them.

Naming convention used from now on:

| Job | Purpose |
|---|---|
| `addressbook-ci-1-checkout` | Pull code from GitHub |
| `addressbook-ci-2-compile` | Compile |
| `addressbook-ci-3-test` | Run unit tests |
| `addressbook-ci-4-package` | Build the WAR |

---

## Topic 4 - CI Job 1: Checkout

**Key idea: a Freestyle job with a label runs on the matching agent, gets its own workspace and pulls source code into it.**

### Step 4.1 - Create the job

**[JENKINS UI]**

1. **Dashboard > New Item**
2. Name: `addressbook-ci-1-checkout`
3. Choose **Freestyle project** and click **OK**.

### Step 4.2 - Configure the job

**General**
- Tick **Restrict where this project can be run**
- **Label Expression:** `ci-agent`

**Source Code Management**
- Choose **Git**
- **Repository URL:** `https://github.com/<GITHUB_USER>/addressbook.git`
- **Branches to Build:** `*/main`
- Credentials: `- none -` (the repository is public)

**Build Steps > Add build step > Execute shell**

```bash
echo "===== WHERE AM I ====="
whoami
hostname
pwd
echo "===== WHAT DID WE CHECK OUT ====="
ls -la
git log -1 --oneline
```

Click **Save**.

### Step 4.3 - Run and read the result

1. Click **Build Now**.
2. Open build **#1 > Console Output**.

Look for:
- `Running on <Agent A node name>` near the top (proof it ran on Agent A, not the Controller)
- `hostname` printing Agent A's VM name
- Your project files listed
- `Finished: SUCCESS`

**Write down the user name printed by `whoami`. You will need it in Topic 10.**

### Validate Topic 4

- [ ] Console shows the job ran on Agent A
- [ ] `pom.xml` and `src` are visible in the workspace listing
- [ ] Build is green (SUCCESS)
- [ ] You noted the `whoami` user: ______________

---

## Topic 5 - CI Job 2: Compile

**Key idea: `mvn compile` turns `.java` files into `.class` files, and nothing else.** No tests run and no WAR is made.

### Step 5.1 - Create the job (copy from the first one)

**[JENKINS UI]**

1. **Dashboard > New Item**
2. Name: `addressbook-ci-2-compile`
3. In **Copy from**, type `addressbook-ci-1-checkout`, then click **OK**.

### Step 5.2 - Change the build step

Replace the **Execute shell** contents with:

```bash
echo "===== COMPILE ====="
mvn -B clean compile
echo "===== COMPILED CLASSES ====="
find target/classes -name "*.class"
```

Click **Save**, then **Build Now**.

### Step 5.3 - Prove that compile catches errors (optional but powerful)

**[LAPTOP]**

```bash
cd addressbook
sed -i 's/return name;/return nam;/' src/main/java/com/example/addressbook/Contact.java
git commit -am "Break the build on purpose"
git push
```

Run `addressbook-ci-2-compile` again. It turns **red** with a `cannot find symbol` error. Now fix it:

```bash
git revert --no-edit HEAD
git push
```

Run the job again. It is green.

### Validate Topic 5

- [ ] Console shows `BUILD SUCCESS`
- [ ] Console lists `Contact.class` and `AddressBook.class`
- [ ] (Optional) You saw a red build on a deliberate error, then a green build after the revert

---

## Topic 6 - CI Job 3: Test

**Key idea: `mvn test` compiles first, then runs the unit tests, and a single failing test fails the build.** The result is the quality gate of CI.

### Step 6.1 - Create the job

**[JENKINS UI]**

1. **New Item**, name `addressbook-ci-3-test`, **Copy from** `addressbook-ci-2-compile`, **OK**.

### Step 6.2 - Change the build step and add a test report

**Execute shell:**

```bash
echo "===== TEST ====="
mvn -B clean test
```

**Post-build Actions > Add post-build action > Publish JUnit test result report**
- **Test report XMLs:** `target/surefire-reports/*.xml`

Click **Save**, then **Build Now**.

### Step 6.3 - Verify the test results

1. In the console output, find `Tests run: 5, Failures: 0, Errors: 0`.
2. On the build page, click **Test Result**. You should see 5 tests, all passed. Open the test class to see each test name.

### Step 6.4 - Prove that a failing test stops the pipeline (optional)

**[LAPTOP]**

```bash
cd addressbook
sed -i 's/assertEquals(0, new AddressBook().size());/assertEquals(99, new AddressBook().size());/' src/test/java/com/example/addressbook/AddressBookTest.java
git commit -am "Break a test on purpose"
git push
```

Run the job. The build is **unstable/failed** and the Test Result page shows the failing test. Restore it:

```bash
git revert --no-edit HEAD
git push
```

### Validate Topic 6

- [ ] Console shows 5 tests run, 0 failures
- [ ] **Test Result** page appears on the build and shows 5 passed
- [ ] (Optional) A deliberately broken test made the build fail

---

## Topic 7 - CI Job 4: Package

**Key idea: `mvn package` runs compile and test first, then bundles everything into the WAR.** The WAR is the deliverable of CI.

### Step 7.1 - Create the job

**[JENKINS UI]**

1. **New Item**, name `addressbook-ci-4-package`, **Copy from** `addressbook-ci-3-test`, **OK**.

### Step 7.2 - Change the build step

**Execute shell:**

```bash
echo "===== PACKAGE ====="
mvn -B clean package
echo "===== ARTIFACT ====="
ls -l target/addressbook.war
echo "===== WAR CONTENTS (first lines) ====="
jar tf target/addressbook.war | head -20
```

Keep the JUnit post-build action. Click **Save**, then **Build Now**.

### Validate Topic 7

- [ ] Console shows `BUILD SUCCESS`
- [ ] Console shows `target/addressbook.war` with a file size
- [ ] The WAR listing contains `index.jsp` and `WEB-INF/classes/com/example/addressbook/AddressBook.class`

---

# PHASE 3 - Complete CI Pipeline

---

## Topic 8 - Combine the CI Stages into One Job

**Key idea: one job, several build steps in sequence. If any step fails, Jenkins stops and marks the job failed.**

**Default Behavior**
- Each **Execute shell** step runs in order in the same workspace.
- A non-zero exit code in one step stops the rest.

**Why It Matters**
- Compile, Test and Package are now visible as separate blocks in the console, so a failure tells you exactly which stage broke.
- This is the same idea a Jenkinsfile expresses with named stages, which you will build in Lab 2.

### Step 8.1 - Create the job

**[JENKINS UI]**

1. **New Item**, name `addressbook-ci`, **Freestyle project**, **OK**.

### Step 8.2 - Configure

**General**
- Tick **Restrict where this project can be run**, **Label Expression:** `ci-agent`

**Source Code Management**
- **Git**, **Repository URL:** `https://github.com/<GITHUB_USER>/addressbook.git`, **Branches to Build:** `*/main`

**Build Steps** - add three separate **Execute shell** steps, in this order:

Step 1 - Compile:

```bash
echo "########## STAGE 1: COMPILE ##########"
mvn -B clean compile
```

Step 2 - Test:

```bash
echo "########## STAGE 2: TEST ##########"
mvn -B test
```

Step 3 - Package:

```bash
echo "########## STAGE 3: PACKAGE ##########"
mvn -B package -DskipTests
ls -l target/addressbook.war
```

`-DskipTests` in step 3 only avoids running the tests twice, because Stage 2 already ran them.

**Post-build Actions**
- **Publish JUnit test result report:** `target/surefire-reports/*.xml`

Click **Save**, then **Build Now**.

### Validate Topic 8

- [ ] Console shows the three banners: STAGE 1, STAGE 2, STAGE 3
- [ ] Build is green
- [ ] Test Result shows 5 passed
- [ ] The job ran on Agent A

---

## Topic 9 - CI Artifact Handling

**Key idea: an archived artifact is a file Jenkins copies off the agent and keeps on the Controller, attached to a specific build number.**

**Default Behavior**
- Files produced on an agent stay in the agent's workspace, and the next build (or a workspace cleanup) can overwrite them.

**What Changes When We Archive**
- Jenkins copies `addressbook.war` to the Controller and stores it with build `#N`.
- Anyone (including another job on another agent) can fetch build `#N`'s exact WAR later.

**Why It Matters**
- CD deploys exactly what CI built and tested. Nothing is rebuilt at deploy time.
- You can roll back by redeploying an older build's artifact.

### Step 9.1 - Archive the WAR

**[JENKINS UI]**

1. Open **addressbook-ci > Configure**.
2. **Post-build Actions > Add post-build action > Archive the artifacts**
   - **Files to archive:** `target/addressbook.war`
3. Click **Advanced** and tick **Fingerprint all archived artifacts** (optional, but useful to trace a WAR back to its build).

### Step 9.2 - Allow the CD job to copy the artifact

Jenkins blocks artifact copying by default. We permit the CD job (created in Topic 11) in advance.

In the same **Configure** page, under **General**:

1. Tick **Permission to Copy Artifact**.
2. **Projects to allow copy artifacts to:** `addressbook-cd`

Click **Save**, then **Build Now**.

### Step 9.3 - Verify the artifact

1. Open the build page. Under the build number you should see **Build Artifacts** with `addressbook.war`.
2. On the job's main page, look for **Last Successful Artifacts**.

### Validate Topic 9

- [ ] `addressbook.war` is listed as a build artifact of `addressbook-ci`
- [ ] You can click it and download it
- [ ] "Permission to Copy Artifact" is set for `addressbook-cd`

---

# PHASE 4 - CD / Deployment Pipeline

---

## Topic 10 - Prepare the Deployment Agent (Agent B)

**Key idea: Tomcat is a Java web server. We install it once, run it as a service, and let Jenkins drop WAR files into its `webapps` folder.**

**Default Behavior**
- Tomcat watches `webapps/`. When a new `.war` file appears there, it unpacks it and starts serving it at `/<war-name>/`.

**What We Configure**
- Tomcat is installed in `/opt/tomcat`, owned by the same Linux user that runs the Jenkins agent, so the CD job can copy files into it without `sudo`.
- Tomcat runs as a **systemd service** so it keeps running after a Jenkins build ends. (Processes started directly by a Jenkins build get cleaned up when the build finishes.)

**Why It Matters**
- Real deployments separate "who installs the server" from "who deploys the app". Here we keep it simple, but you should know the trade-off: the Jenkins user can write into Tomcat.

### Step 10.1 - Log in and check Java

**[AGENT B]**

```bash
ssh <ADMIN_USER>@20.244.3.100
java -version
```

If `java` is missing, run `sudo apt-get update && sudo apt-get install -y openjdk-17-jre-headless`.

### Step 10.2 - Set the variables

Replace `<AGENT_USER>` with the `whoami` user you noted in Topic 4 (the user that the Jenkins agent runs as).

**[AGENT B]**

```bash
export TOMCAT_VERSION=9.0.97
export AGENT_USER=<AGENT_USER>
echo "Tomcat $TOMCAT_VERSION will be owned by $AGENT_USER"
id $AGENT_USER
```

`id` must print a user. If it says "no such user", you typed the wrong name.

### Step 10.3 - Download and install Tomcat

**[AGENT B]**

```bash
cd /tmp
curl -fSLO https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
sudo mkdir -p /opt/tomcat
sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz -C /opt/tomcat --strip-components=1
sudo chown -R ${AGENT_USER}: /opt/tomcat
ls -l /opt/tomcat
```

You should see the folders `bin`, `conf`, `lib`, `logs`, `webapps` and more.

### Step 10.4 - Run Tomcat as a service

**[AGENT B]**

```bash
JAVA_HOME_DIR=$(dirname $(dirname $(readlink -f $(which java))))
echo "JAVA_HOME will be: $JAVA_HOME_DIR"

sudo tee /etc/systemd/system/tomcat.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat 9
After=network.target

[Service]
Type=forking
User=${AGENT_USER}
Environment=JAVA_HOME=${JAVA_HOME_DIR}
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
sleep 5
sudo systemctl status tomcat --no-pager
```

You should see `active (running)`.

### Step 10.5 - Validate Tomcat

**[AGENT B]**

```bash
curl -I http://localhost:8080
```

Expect `HTTP/1.1 200`. Then from your laptop:

**[BROWSER]** Open `http://20.244.3.100:8080`. You should see the Apache Tomcat welcome page.

If the page does not load from the browser but `curl` works on the VM, the Azure port 8080 rule from Step 1.5 is the problem.

### Validate Topic 10

- [ ] `sudo systemctl status tomcat` shows active (running)
- [ ] `curl -I http://localhost:8080` returns 200 on Agent B
- [ ] The Tomcat welcome page opens in your browser at `http://20.244.3.100:8080`
- [ ] `/opt/tomcat` is owned by the Jenkins agent user (`ls -ld /opt/tomcat`)

---

## Topic 11 - Create the CD Freestyle Job

**Key idea: the CD job never builds anything. It fetches the WAR that CI archived, places it into Tomcat, and checks the app answers.**

### Step 11.1 - Create the job

**[JENKINS UI]**

1. **New Item**, name `addressbook-cd`, **Freestyle project**, **OK**.

### Step 11.2 - Configure

**General**
- Tick **Restrict where this project can be run**, **Label Expression:** `cd-agent`

**Build Steps > Add build step > Copy artifacts from another project**
- **Project name:** `addressbook-ci`
- **Which build:** Latest successful build
- **Artifacts to copy:** `target/addressbook.war`
- **Target directory:** `incoming`
- Tick **Flatten directories**

**Build Steps > Add build step > Execute shell**

```bash
#!/bin/bash
set -e

echo "===== ARTIFACT RECEIVED ====="
ls -l incoming/addressbook.war

echo "===== REMOVE OLD VERSION ====="
rm -rf /opt/tomcat/webapps/addressbook /opt/tomcat/webapps/addressbook.war

echo "===== DEPLOY NEW VERSION ====="
cp incoming/addressbook.war /opt/tomcat/webapps/addressbook.war

echo "===== WAIT FOR TOMCAT TO UNPACK AND START THE APP ====="
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/addressbook/ || true)
  echo "Attempt $i: HTTP $code"
  if [ "$code" = "200" ]; then
    echo "DEPLOYMENT VERIFIED"
    exit 0
  fi
  sleep 2
done

echo "DEPLOYMENT FAILED: application did not return HTTP 200"
exit 1
```

Click **Save**.

### Step 11.3 - Run it

1. Make sure `addressbook-ci` has at least one green build with an archived WAR (Topic 9).
2. Open `addressbook-cd` and click **Build Now**.
3. Read **Console Output**. You should see `DEPLOYMENT VERIFIED`.

### Step 11.4 - Verify in the browser

**[BROWSER]** Open `http://20.244.3.100:8080/addressbook/`

You should see **AddressBook - Version 1**, a table with three contacts, and "Served by host" showing Agent B's host name.

### Validate Topic 11

- [ ] The CD job ran on Agent B
- [ ] Console shows `DEPLOYMENT VERIFIED`
- [ ] Browser shows the AddressBook page with "Version 1"
- [ ] "Served by host" on the page matches Agent B

---

## Topic 12 - Test the CI to CD Flow (Manually Chained)

**Key idea: this is the real developer loop. Change code, push, build, deploy, see the change.** We run CI and CD by hand for now so you can see each handoff.

### Step 12.1 - The developer changes the code

**[LAPTOP]**

```bash
cd addressbook
sed -i -E 's#<h1>.*</h1>#<h1>AddressBook - Version 2</h1>#' src/main/webapp/index.jsp
git diff
git commit -am "Update page to Version 2"
git push
```

### Step 12.2 - CI builds the new WAR

**[JENKINS UI]** Run **addressbook-ci** with **Build Now**. Wait for green. Note the new build number.

### Step 12.3 - CD deploys it

**[JENKINS UI]** Run **addressbook-cd** with **Build Now**. Wait for `DEPLOYMENT VERIFIED`.

### Step 12.4 - See the change

**[BROWSER]** Refresh `http://20.244.3.100:8080/addressbook/` (use Ctrl+F5). The heading now says **AddressBook - Version 2**.

### Validate Topic 12

- [ ] GitHub shows your latest commit
- [ ] CI produced a new build with a new archived WAR
- [ ] CD deployed it and the browser shows Version 2

---

# PHASE 5 - Pipeline Orchestration

---

## Topic 13 - Connect CI and CD

**Key idea: in Jenkins terms, CI becomes the upstream job and CD becomes the downstream job. Finishing the upstream automatically starts the downstream.**

**Default Behavior**
- Freestyle jobs are independent. Nothing starts a job except a person or a trigger.

**What Changes**
- **Poll SCM** on CI: Jenkins checks GitHub on a schedule and builds when it sees a new commit.
- **Build other projects** on CI: when CI succeeds, it starts CD.

**Why It Matters**
- The developer only does `git push`. Everything else happens on its own.
- The condition "only if stable" is the safety gate: a broken build is never deployed.

### Step 13.1 - Make CI start on new commits

**[JENKINS UI]** **addressbook-ci > Configure > Build Triggers**

- Tick **Poll SCM**
- **Schedule:** `H/2 * * * *`

(This means: check GitHub about every 2 minutes.)

### Step 13.2 - Make CI start CD

**[JENKINS UI]** Same page, **Post-build Actions > Add post-build action > Build other projects**

- **Projects to build:** `addressbook-cd`
- Choose **Trigger only if build is stable**

Click **Save**.

### Step 13.3 - Execute the complete CI/CD flow

**[LAPTOP]**

```bash
cd addressbook
sed -i -E 's#<h1>.*</h1>#<h1>AddressBook - Version 3</h1>#' src/main/webapp/index.jsp
git commit -am "Update page to Version 3"
git push
```

Now do not touch Jenkins. Wait up to 2 minutes and watch the dashboard:

1. `addressbook-ci` starts by itself.
2. When CI finishes green, `addressbook-cd` starts by itself.
3. **[BROWSER]** Refresh `http://20.244.3.100:8080/addressbook/`. It shows **Version 3**.

### Step 13.4 - Understand upstream and downstream

**[JENKINS UI]**

1. Open **addressbook-cd**. The left side shows **Upstream Projects: addressbook-ci**.
2. Open **addressbook-ci**. It shows **Downstream Projects: addressbook-cd**.
3. Open a CD build and read the top of the page: "Started by upstream project addressbook-ci build number N".

### Optional - Instant trigger with a GitHub webhook

Polling has a delay of up to 2 minutes. A webhook makes it instant.

1. GitHub repository **Settings > Webhooks > Add webhook**
2. **Payload URL:** `http://<CONTROLLER_PUBLIC_IP>:8080/github-webhook/`
3. **Content type:** `application/json`, **Just the push event**
4. In `addressbook-ci > Configure > Build Triggers`, tick **GitHub hook trigger for GITScm polling** (requires the GitHub plugin).

Port 8080 of the Controller must be reachable from the internet for this to work.

### Validate Topic 13

- [ ] A `git push` alone triggered CI without you clicking anything
- [ ] CI's success triggered CD automatically
- [ ] The browser shows Version 3
- [ ] Both jobs show the upstream/downstream relationship

---

## Topic 14 - Final End-to-End Demo

**Key idea: a good demo tells a story that everyone can follow.** Follow this run sheet in order.

### The Story

"A developer changes one line. Within minutes the change is live, and nobody touched a server."

### Demo Run Sheet

| Step | What you do | What the audience sees |
|---|---|---|
| 1 | Show `http://20.244.3.100:8080/addressbook/` | Current version on the page |
| 2 | Edit the heading on your laptop | The one-line change |
| 3 | `git push` | GitHub shows the new commit |
| 4 | Open the Jenkins dashboard | CI starts on Agent A |
| 5 | Open CI Console Output | STAGE 1 compile, STAGE 2 test, STAGE 3 package |
| 6 | Open CI build page | Test Result and the archived `addressbook.war` |
| 7 | CD starts automatically | It runs on Agent B |
| 8 | Read CD Console Output | Artifact received, deployed, `DEPLOYMENT VERIFIED` |
| 9 | Refresh the browser | New version is live, host name is Agent B |

### Commands for the demo

**[LAPTOP]**

```bash
cd addressbook
sed -i -E 's#<h1>.*</h1>#<h1>AddressBook - Version 4 - Live Demo</h1>#' src/main/webapp/index.jsp
git commit -am "Live demo change"
git push
```

### Bonus: Show that a broken build is never deployed

**[LAPTOP]**

```bash
cd addressbook
sed -i 's/assertEquals(1, book.size());/assertEquals(2, book.size());/' src/test/java/com/example/addressbook/AddressBookTest.java
git commit -am "Demo: failing test"
git push
```

CI fails at the Test stage, CD never starts, and the browser still shows the previous working version. Then repair it:

```bash
git revert --no-edit HEAD
git push
```

### Validate Topic 14

- [ ] The full path worked with a single `git push`
- [ ] You can explain each box in the final architecture diagram
- [ ] The failing-test demo proved a bad build does not reach Tomcat

---

# Appendix A - Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Job stays at "Waiting for next available executor" | Label typo, agent offline, or Controller has 0 executors and no label was set | Check **Manage Jenkins > Nodes**. Check the label is exactly `ci-agent` or `cd-agent`. |
| `mvn: command not found` | Maven not installed on Agent A | `sudo apt-get install -y maven` on Agent A |
| `release version 11 not supported` or `javac: not found` | Only a JRE is installed, or Java is older than 11 | `sudo apt-get install -y openjdk-17-jdk` on Agent A |
| Git checkout fails: `Authentication failed` or `Repository not found` | Repository is private, or the URL or username is wrong | Make the repository Public, or recheck the URL. |
| Checkout fails: `couldn't find remote ref refs/heads/main` | Branch is not named `main` | Check the branch on GitHub, or fix **Branches to Build** |
| `git push` rejected from the laptop | Wrong password used | Use the Personal Access Token, not your GitHub password |
| Test Result missing on the build page | Report path wrong or tests did not run | Use exactly `target/surefire-reports/*.xml` |
| CD fails: `Unable to find project for artifact copy` | Wrong CI job name in the Copy Artifact step | Use `addressbook-ci` exactly |
| CD fails: not permitted to copy artifacts | Permission not set on the CI job | Redo Step 9.2, exact job name `addressbook-cd` |
| CD fails: `Permission denied` on `/opt/tomcat/webapps` | `/opt/tomcat` not owned by the agent user | On Agent B: `sudo chown -R <AGENT_USER>: /opt/tomcat` |
| CD says `DEPLOYMENT FAILED` | The app did not start | On Agent B: `ls /opt/tomcat/webapps` and `tail -50 /opt/tomcat/logs/catalina.*.log` |
| Browser cannot open port 8080 but `curl` works on Agent B | Azure NSG rule missing | Redo Step 1.5 |
| Tomcat service will not start | Wrong `JAVA_HOME`, or port 8080 already used | `sudo journalctl -u tomcat -n 50 --no-pager` and `sudo ss -ltnp | grep 8080` |
| Browser still shows the old version | Browser cache | Hard refresh with Ctrl+F5 |
| A command works when you type it but fails in Jenkins | Different user or PATH than your manual login | Run `whoami` and `which mvn` inside a Jenkins job on that agent |

---

# Appendix B - Quick Reference

| What | URL or command |
|---|---|
| Jenkins | `http://<CONTROLLER_PUBLIC_IP>:8080` |
| Application | `http://20.244.3.100:8080/addressbook/` |
| Tomcat welcome page | `http://20.244.3.100:8080` |
| Tomcat status (Agent B) | `sudo systemctl status tomcat --no-pager` |
| Tomcat restart (Agent B) | `sudo systemctl restart tomcat` |
| Tomcat logs (Agent B) | `tail -f /opt/tomcat/logs/catalina.out` |
| Deployed apps (Agent B) | `ls -l /opt/tomcat/webapps` |
| Build locally (Agent A) | `mvn -B clean package` |

**Job map**

| Job | Type | Runs on | Purpose |
|---|---|---|---|
| `addressbook-ci-1-checkout` | Freestyle | Agent A | Learn checkout |
| `addressbook-ci-2-compile` | Freestyle | Agent A | Learn compile |
| `addressbook-ci-3-test` | Freestyle | Agent A | Learn tests |
| `addressbook-ci-4-package` | Freestyle | Agent A | Learn packaging |
| `addressbook-ci` | Freestyle | Agent A | Complete CI, archives the WAR |
| `addressbook-cd` | Freestyle | Agent B | Deploys the WAR to Tomcat |

---

# Appendix C - Clean Up After the Lab

**[AGENT B]** Stop Tomcat if you are pausing the lab:

```bash
sudo systemctl stop tomcat
```

**[JENKINS UI]** Disable jobs you no longer need with **Disable Project**, so they do not trigger by accident.

**[Azure Portal]** Stop (deallocate) the Controller, Agent A and Agent B virtual machines when you are done, to avoid charges. Remember the public IPs can change after a stop and start, so update the address values in this runbook, in the Jenkins node settings and in any GitHub webhook if they change.

**[BROWSER]** Delete the Personal Access Token you created in Step 3.2 from GitHub **Settings > Developer settings** once the lab is finished.

---

**Lab 1 complete.** Keep these jobs, the repository and Tomcat as they are. Lab 2 reuses the same agents, the same repository and the same Tomcat.

End of Lab 1.

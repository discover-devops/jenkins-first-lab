# Jenkins CI/CD with Freestyle Jobs --- End-to-End Java/Tomcat Lab

A hands-on Jenkins CI/CD lab that takes a Java web application from
source code to a running application on Apache Tomcat using Jenkins
Freestyle jobs.

The lab demonstrates:

-   Git and GitHub source control
-   Jenkins Controller and Jenkins Agents
-   Freestyle jobs
-   Maven compilation
-   JUnit testing
-   WAR packaging
-   Jenkins artifact archiving
-   Artifact handoff between jobs
-   Apache Tomcat deployment
-   CI/CD visualization with Build Pipeline
-   End-to-end deployment verification

------------------------------------------------------------------------

## Table of Contents

1.  [Lab Overview](#1-lab-overview)
2.  [Architecture](#2-architecture)
3.  [Lab Environment](#3-lab-environment)
4.  [Prerequisites](#4-prerequisites)
5.  [The Application](#5-the-application)
6.  [Project Structure](#6-project-structure)
7.  [Create the AddressBook
    Application](#7-create-the-addressbook-application)
8.  [Push the Application to GitHub](#8-push-the-application-to-github)
9.  [Prepare Jenkins Agents](#9-prepare-jenkins-agents)
10. [Install Jenkins Plugins](#10-install-jenkins-plugins)
11. [Create CI Job 1 --- Checkout](#11-create-ci-job-1--checkout)
12. [Create CI Job 2 --- Compile](#12-create-ci-job-2--compile)
13. [Create CI Job 3 --- Test](#13-create-ci-job-3--test)
14. [Create CI Job 4 --- Package](#14-create-ci-job-4--package)
15. [Archive the WAR Artifact](#15-archive-the-war-artifact)
16. [Create a Build Pipeline View](#16-create-a-build-pipeline-view)
17. [Prepare Agent B and Install
    Tomcat](#17-prepare-agent-b-and-install-tomcat)
18. [Create the CD Job](#18-create-the-cd-job)
19. [Deploy the WAR to Tomcat](#19-deploy-the-war-to-tomcat)
20. [Verify the Application](#20-verify-the-application)
21. [End-to-End CI/CD Flow](#21-end-to-end-cicd-flow)
22. [Change the Application and Deploy a New
    Version](#22-change-the-application-and-deploy-a-new-version)
23. [Optional --- Automatically Connect CI and
    CD](#23-optional--automatically-connect-ci-and-cd)
24. [Troubleshooting](#24-troubleshooting)
25. [What Each Component Does](#25-what-each-component-does)
26. [Production Thinking](#26-production-thinking)
27. [Lab Validation Checklist](#27-lab-validation-checklist)
28. [Cleanup](#28-cleanup)
29. [Next Step --- Pipeline as Code](#29-next-step--pipeline-as-code)

------------------------------------------------------------------------

# 1. Lab Overview

This lab follows a simple story:

> A developer changes application code, pushes it to GitHub, Jenkins
> builds and tests it, creates a WAR artifact, and the artifact is
> deployed to Tomcat on a separate deployment server.

The lab deliberately starts with multiple small Freestyle jobs so that
each CI activity is visible:

``` text
Checkout
   ↓
Compile
   ↓
Test
   ↓
Package
   ↓
Archive WAR
```

The CD side then consumes the archived WAR:

``` text
Archived WAR
   ↓
CD Job
   ↓
Agent B
   ↓
Tomcat
   ↓
Browser
```

The important principle is:

``` text
CI produces the artifact.
CD deploys the artifact.
```

The deployment job does not rebuild the Java application.

------------------------------------------------------------------------

# 2. Architecture

## 2.1 High-Level Architecture

``` text
                    Developer
                        |
                        | git push
                        v
                    GitHub
                        |
                        | source code
                        v
              +---------------------+
              |  Jenkins Controller  |
              |   Orchestration      |
              +----------+----------+
                         |
             +-----------+-----------+
             |                       |
             v                       v
      +-------------+         +-------------+
      |   Agent A   |         |   Agent B   |
      |     CI      |         |     CD      |
      +-------------+         +-------------+
      | Checkout    |         | Tomcat      |
      | Compile     |         | WAR Deploy  |
      | Test        |         | Verification|
      | Package     |         +------+------+
      +------+------+                |
             |                       |
             | addressbook.war       |
             +-----> Jenkins <-------+
                         |
                         v
                    Browser
```

## 2.2 Roles

### Jenkins Controller

The Controller is the orchestration layer.

It:

-   Stores Jenkins job configuration
-   Schedules jobs
-   Coordinates agents
-   Stores archived artifacts
-   Displays build history and results

The Controller does not need to perform the Java build in this lab.

### Agent A --- CI

Agent A performs the build work:

``` text
Git checkout
     ↓
Maven compile
     ↓
JUnit tests
     ↓
WAR package
```

### Agent B --- CD

Agent B is the deployment server:

``` text
Receive WAR
     ↓
Copy WAR into Tomcat webapps
     ↓
Tomcat deploys application
     ↓
HTTP verification
```

------------------------------------------------------------------------

# 3. Lab Environment

The reference environment used for this lab contains three machines.

  --------------------------------------------------------------------------
  Machine                 Role                       Example
  ----------------------- -------------------------- -----------------------
  Jenkins Controller      Jenkins                    Controller VM
                          management/orchestration   

  Agent A                 CI/build agent             AgentA

  Agent B                 CD/deployment agent +      AgentB
                          Tomcat                     
  --------------------------------------------------------------------------

In the reference implementation:

``` text
Jenkins Controller
20.40.57.112

Agent A
20.40.58.37

Agent B
20.244.3.100
```

For a public/shared lab, replace these addresses with your own VM
addresses rather than hard-coding infrastructure-specific values into
the application repository.

The reference Jenkins node names used in the working implementation are:

``` text
AgentA
AgentB
```

The Jenkins Controller is the orchestration layer.

------------------------------------------------------------------------

# 4. Prerequisites

You need:

-   A Linux Jenkins Controller
-   Two Jenkins agents
-   Java installed on both agents
-   Maven installed on Agent A
-   Git
-   A GitHub repository
-   Network access between Jenkins and the agents
-   Apache Tomcat on Agent B
-   TCP port 8080 accessible from the browser for Tomcat verification

You should also have administrative access to the VMs so that Java,
Maven, Tomcat, and system services can be configured.

------------------------------------------------------------------------

# 5. The Application

The application is a deliberately small Java web application called
**AddressBook**.

It contains:

-   A `Contact` model
-   An `AddressBook` class
-   Five JUnit tests
-   A JSP page displaying contacts
-   A host-name display so that deployment to Agent B can be visually
    confirmed

The application is packaged as:

``` text
addressbook.war
```

Tomcat deploys that WAR at:

``` text
/addressbook/
```

------------------------------------------------------------------------

# 6. Project Structure

The project structure is:

``` text
addressbook/
├── pom.xml
├── .gitignore
└── src/
    ├── main/
    │   ├── java/
    │   │   └── com/
    │   │       └── example/
    │   │           └── addressbook/
    │   │               ├── Contact.java
    │   │               └── AddressBook.java
    │   └── webapp/
    │       └── index.jsp
    └── test/
        └── java/
            └── com/
                └── example/
                    └── addressbook/
                        └── AddressBookTest.java
```

------------------------------------------------------------------------

# 7. Create the AddressBook Application

## 7.1 Create the directories

On the developer laptop:

``` bash
mkdir -p addressbook
cd addressbook

mkdir -p src/main/java/com/example/addressbook
mkdir -p src/main/webapp
mkdir -p src/test/java/com/example/addressbook
```

Verify:

``` bash
pwd
find . -maxdepth 5 -type d
```

------------------------------------------------------------------------

## 7.2 Create `pom.xml`

Create `pom.xml`:

``` bash
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">

  <modelVersion>4.0.0</modelVersion>

  <groupId>com.example</groupId>
  <artifactId>addressbook</artifactId>
  <version>1.0</version>
  <packaging>war</packaging>

  <name>AddressBook</name>

  <properties>
    <maven.compiler.release>21</maven.compiler.release>
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

### Why Java 21?

The reference Agent A and Agent B environment uses OpenJDK 21.

The compiler configuration therefore targets Java 21:

``` xml
<maven.compiler.release>21</maven.compiler.release>
```

If your build agent uses another JDK, align this value with the
JDK/compiler installed on that agent.

------------------------------------------------------------------------

## 7.3 Create `Contact.java`

``` bash
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

------------------------------------------------------------------------

## 7.4 Create `AddressBook.java`

``` bash
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

------------------------------------------------------------------------

## 7.5 Create the JUnit tests

``` bash
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
        assertThrows(
            IllegalArgumentException.class,
            () -> new AddressBook().add(null)
        );
    }
}
EOF
```

------------------------------------------------------------------------

## 7.6 Create `index.jsp`

``` bash
cat > src/main/webapp/index.jsp <<'EOF'
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="com.example.addressbook.*" %>

<%
    AddressBook book = new AddressBook();

    book.add(new Contact(
        "Asha Rao",
        "+91-90000-00001",
        "asha@example.com"
    ));

    book.add(new Contact(
        "Vikram Shah",
        "+91-90000-00002",
        "vikram@example.com"
    ));

    book.add(new Contact(
        "Meera Iyer",
        "+91-90000-00003",
        "meera@example.com"
    ));

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
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
        }

        table {
            border-collapse: collapse;
        }

        th, td {
            border: 1px solid #999;
            padding: 8px 14px;
            text-align: left;
        }

        th {
            background: #eee;
        }

        .meta {
            color: #555;
            margin-top: 20px;
        }
    </style>
</head>

<body>

<h1>AddressBook - Version 1</h1>

<p>Contacts stored: <%= book.size() %></p>

<table>
    <tr>
        <th>Name</th>
        <th>Phone</th>
        <th>Email</th>
    </tr>

    <% for (Contact c : book.getAll()) { %>
    <tr>
        <td><%= c.getName() %></td>
        <td><%= c.getPhone() %></td>
        <td><%= c.getEmail() %></td>
    </tr>
    <% } %>
</table>

<p class="meta">
    Served by host: <%= host %>
</p>

</body>
</html>
EOF
```

------------------------------------------------------------------------

## 7.7 Create `.gitignore`

``` bash
cat > .gitignore <<'EOF'
target/
*.class
*.log
.idea/
.vscode/
EOF
```

------------------------------------------------------------------------

# 8. Push the Application to GitHub

## 8.1 Initialize Git

From inside the `addressbook` directory:

``` bash
git init -b main
```

Check:

``` bash
git status
```

------------------------------------------------------------------------

## 8.2 Commit the application

``` bash
git add .
git commit -m "Initial AddressBook application"
```

------------------------------------------------------------------------

## 8.3 Add the GitHub repository

Example:

``` bash
git remote add origin https://github.com/<GITHUB_USER>/addressbookNew.git
```

Verify:

``` bash
git remote -v
```

------------------------------------------------------------------------

## 8.4 Push

``` bash
git push -u origin main
```

Verify the GitHub repository contains:

``` text
.gitignore
pom.xml
src/
```

There should be no `target/` directory in Git.

------------------------------------------------------------------------

# 9. Prepare Jenkins Agents

The reference lab uses:

``` text
Controller → orchestration
AgentA     → CI
AgentB     → CD + Tomcat
```

## 9.1 Verify Agent A

SSH to Agent A and check:

``` bash
java -version
javac -version
mvn -version
git --version
```

The reference environment uses Java 21.

### Important lesson: JRE vs JDK

The Java runtime may be installed while the Java compiler is missing.

A successful:

``` bash
java -version
```

does not guarantee that:

``` bash
javac -version
```

will work.

The CI build requires `javac`.

If `javac` is missing on Ubuntu:

``` bash
sudo apt update
sudo apt install -y openjdk-21-jdk
```

Verify:

``` bash
javac -version
```

Expected:

``` text
javac 21.x
```

------------------------------------------------------------------------

## 9.2 Verify Agent B

SSH to Agent B:

``` bash
ssh <USER>@<AGENT_B_IP>
```

Verify:

``` bash
whoami
hostname
java -version
```

The reference environment uses:

``` text
User: azureuser
Hostname: AgentB
Java: OpenJDK 21
```

------------------------------------------------------------------------

# 10. Install Jenkins Plugins

From Jenkins:

``` text
Manage Jenkins
    ↓
Plugins
    ↓
Available plugins
```

Install/verify:

-   Git
-   JUnit
-   Copy Artifact
-   Build Pipeline

The **Copy Artifact** plugin is required for the CD job to consume the
WAR produced by CI.

The **Build Pipeline** plugin is useful for visualizing the Freestyle
job chain.

------------------------------------------------------------------------

# 11. Create CI Job 1 --- Checkout

Create:

``` text
addressbook-ci-1-checkout
```

Choose:

``` text
Freestyle project
```

## General

Enable:

``` text
Restrict where this project can be run
```

Enter:

``` text
AgentA
```

## Source Code Management

Select:

``` text
Git
```

Repository:

``` text
https://github.com/<GITHUB_USER>/addressbookNew.git
```

Branch:

``` text
*/main
```

For a public repository:

``` text
Credentials: - none -
```

## Build Step

Add:

``` text
Execute shell
```

Use:

``` bash
echo "===== WHERE AM I ====="
whoami
hostname
pwd

echo "===== WHAT DID WE CHECK OUT ====="
ls -la

echo "===== LATEST COMMIT ====="
git log -1 --oneline
```

Save and click:

``` text
Build Now
```

Expected:

``` text
Building remotely on AgentA
```

and:

``` text
Finished: SUCCESS
```

------------------------------------------------------------------------

# 12. Create CI Job 2 --- Compile

Create by copying:

``` text
addressbook-ci-1-checkout
```

New name:

``` text
addressbook-ci-2-compile
```

Keep the job on:

``` text
AgentA
```

Replace the Execute Shell step with:

``` bash
echo "===== COMPILE ====="

mvn -B clean compile

echo "===== COMPILED CLASSES ====="

find target/classes -name "*.class"
```

Save and build.

Expected:

``` text
BUILD SUCCESS
```

and:

``` text
Contact.class
AddressBook.class
```

------------------------------------------------------------------------

## Important Build Issue: `release version not supported`

If you see:

``` text
Fatal error compiling:
error: release version 21 not supported
```

check:

``` bash
java -version
javac -version
mvn -version
```

If `java` works but `javac` does not exist, install the JDK:

``` bash
sudo apt update
sudo apt install -y openjdk-21-jdk
```

Then:

``` bash
javac -version
```

The Jenkins job and Maven must have access to the compiler.

------------------------------------------------------------------------

# 13. Create CI Job 3 --- Test

Copy:

``` text
addressbook-ci-2-compile
```

Create:

``` text
addressbook-ci-3-test
```

Keep:

``` text
AgentA
```

Replace Execute Shell with:

``` bash
echo "===== TEST ====="

mvn -B test

echo "===== TEST REPORTS ====="

find target/surefire-reports -type f -maxdepth 1 -print
```

Build the job.

Expected:

``` text
Tests run: 5
Failures: 0
Errors: 0
Skipped: 0
```

and:

``` text
BUILD SUCCESS
```

Test reports will be under:

``` text
target/surefire-reports/
```

------------------------------------------------------------------------

# 14. Create CI Job 4 --- Package

Copy:

``` text
addressbook-ci-3-test
```

Create:

``` text
addressbook-ci-4-package
```

Keep:

``` text
AgentA
```

Use:

``` bash
echo "===== PACKAGE ====="

mvn -B package -DskipTests

echo "===== WAR FILE ====="

ls -lh target/addressbook.war
```

Expected:

``` text
BUILD SUCCESS
```

and:

``` text
target/addressbook.war
```

Example:

``` text
-rw-rw-r-- ... target/addressbook.war
```

At this point CI has produced the deployable artifact.

------------------------------------------------------------------------

# 15. Archive the WAR Artifact

Creating a WAR in the workspace is not enough.

The WAR must be archived by Jenkins so another job can consume it.

Open:

``` text
addressbook-ci-4-package
    ↓
Configure
```

Go to:

``` text
Post-build Actions
    ↓
Add post-build action
    ↓
Archive the artifacts
```

Enter:

``` text
target/addressbook.war
```

Save.

Run the package job again.

Open the successful build and verify:

``` text
Build Artifacts
    addressbook.war
```

This is an important distinction:

``` text
WAR exists in workspace
        ≠
WAR is archived by Jenkins
```

The CD job needs the second one.

------------------------------------------------------------------------

# 16. Create a Build Pipeline View

A visual pipeline makes the Freestyle flow easier to understand.

Install:

``` text
Build Pipeline
```

Then create a Build Pipeline view.

Configure the pipeline so that the jobs appear as:

``` text
addressbook-ci-1-checkout
              ↓
addressbook-ci-2-compile
              ↓
addressbook-ci-3-test
              ↓
addressbook-ci-4-package
```

The view is useful for seeing build status across the CI chain.

All four green jobs indicate that each stage completed successfully.

------------------------------------------------------------------------

# 17. Prepare Agent B and Install Tomcat

Agent B is the deployment server.

## 17.1 Verify Java

On Agent B:

``` bash
java -version
```

The reference environment uses Java 21.

------------------------------------------------------------------------

## 17.2 Define variables

``` bash
export TOMCAT_VERSION=9.0.97
export AGENT_USER=azureuser

echo "Tomcat $TOMCAT_VERSION will be owned by $AGENT_USER"
```

Verify:

``` bash
id $AGENT_USER
```

------------------------------------------------------------------------

## 17.3 Download and install Tomcat

``` bash
cd /tmp

curl -fSLO https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz

sudo mkdir -p /opt/tomcat

sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz \
  -C /opt/tomcat \
  --strip-components=1

sudo chown -R ${AGENT_USER}: /opt/tomcat

ls -l /opt/tomcat
```

You should see:

``` text
bin
conf
lib
logs
temp
webapps
work
```

------------------------------------------------------------------------

## 17.4 Create a systemd service

Determine Java home:

``` bash
JAVA_HOME_DIR=$(dirname $(dirname $(readlink -f $(which java))))

echo "JAVA_HOME will be: $JAVA_HOME_DIR"
```

Create the service:

``` bash
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
```

Reload systemd:

``` bash
sudo systemctl daemon-reload
```

Enable and start Tomcat:

``` bash
sudo systemctl enable --now tomcat
```

Check:

``` bash
sudo systemctl status tomcat --no-pager
```

Expected:

``` text
Active: active (running)
```

------------------------------------------------------------------------

## 17.5 Validate Tomcat

On Agent B:

``` bash
curl -I http://localhost:8080
```

Expected:

``` text
HTTP/1.1 200
```

------------------------------------------------------------------------

## 17.6 Open TCP port 8080

The browser must be able to reach Tomcat.

In the Azure Portal:

``` text
Agent B VM
    ↓
Networking
    ↓
Add inbound port rule
```

Use:

``` text
Source: My IP address
Destination port: 8080
Protocol: TCP
Action: Allow
Name: Allow-Tomcat-8080
```

Using your own public IP as the source is preferable to opening port
8080 to the entire Internet.

------------------------------------------------------------------------

# 18. Create the CD Job

Create:

``` text
addressbook-cd
```

Choose:

``` text
Freestyle project
```

## 18.1 Run the CD job on Agent B

Under:

``` text
General
```

enable:

``` text
Restrict where this project can be run
```

Enter:

``` text
AgentB
```

------------------------------------------------------------------------

## 18.2 Copy the archived WAR

Under:

``` text
Build Steps
    ↓
Add build step
    ↓
Copy artifacts from another project
```

Use:

``` text
Project name:
addressbook-ci-4-package
```

Use:

``` text
Which build:
Latest successful build
```

Artifacts:

``` text
target/addressbook.war
```

Target directory:

``` text
incoming
```

Enable:

``` text
Flatten directories
```

The flow is now:

``` text
addressbook-ci-4-package
             |
             | archived WAR
             v
       addressbook-cd
             |
             v
     incoming/addressbook.war
```

------------------------------------------------------------------------

# 19. Deploy the WAR to Tomcat

Add another build step:

``` text
Execute shell
```

Use:

``` bash
#!/bin/bash
set -e

echo "===== ARTIFACT RECEIVED ====="

ls -l incoming/addressbook.war

echo "===== REMOVE OLD VERSION ====="

rm -rf /opt/tomcat/webapps/addressbook
rm -f /opt/tomcat/webapps/addressbook.war

echo "===== DEPLOY NEW VERSION ====="

cp incoming/addressbook.war /opt/tomcat/webapps/addressbook.war

echo "===== WAIT FOR TOMCAT TO DEPLOY ====="

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

echo "DEPLOYMENT FAILED: application did not return HTTP 200"

exit 1
```

Save the job.

------------------------------------------------------------------------

## 19.1 Artifact Copy Permission

If CD reports:

``` text
Failed to copy artifacts
```

go to:

``` text
addressbook-ci-4-package
    ↓
Configure
    ↓
General
```

Enable:

``` text
Permission to Copy Artifact
```

Then specify:

``` text
addressbook-cd
```

Save the CI job.

Run the package job again if necessary so there is a current archived
WAR.

Then rerun CD.

------------------------------------------------------------------------

# 20. Verify the Application

Run:

``` text
addressbook-cd
    ↓
Build Now
```

Open:

``` text
Console Output
```

A successful deployment should show:

``` text
===== ARTIFACT RECEIVED =====

incoming/addressbook.war

===== REMOVE OLD VERSION =====

===== DEPLOY NEW VERSION =====

===== WAIT FOR TOMCAT TO DEPLOY =====

Attempt 1: HTTP 404
Attempt 2: HTTP 404
...
Attempt 5: HTTP 200

DEPLOYMENT VERIFIED

Finished: SUCCESS
```

The temporary `404` responses are expected while Tomcat is unpacking and
starting the WAR.

The important final result is:

``` text
HTTP 200
DEPLOYMENT VERIFIED
Finished: SUCCESS
```

------------------------------------------------------------------------

## 20.1 Verify from the Browser

Open:

``` text
http://<AGENT_B_IP>:8080/addressbook/
```

The page should display:

``` text
AddressBook - Version 1
```

and the contacts:

``` text
Asha Rao
Vikram Shah
Meera Iyer
```

The page should also show:

``` text
Served by host: AgentB
```

This proves that the application is actually running on Agent B.

------------------------------------------------------------------------

# 21. End-to-End CI/CD Flow

At this point the complete manual flow is:

``` text
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
Agent A
    |
    +--> Checkout
    |
    +--> Compile
    |
    +--> Test
    |
    +--> Package
             |
             v
     addressbook.war
             |
             v
     Jenkins Artifact
             |
             v
       addressbook-cd
             |
             v
          Agent B
             |
             v
          Tomcat
             |
             v
        HTTP 200
             |
             v
          Browser
```

This demonstrates the central CI/CD principle:

``` text
Source code
    ↓
Build
    ↓
Test
    ↓
Package
    ↓
Artifact
    ↓
Deploy
    ↓
Verify
```

------------------------------------------------------------------------

# 22. Change the Application and Deploy a New Version

This is the most useful demonstration of the lab.

Suppose the application currently shows:

``` text
AddressBook - Version 1
```

Change it to:

``` text
AddressBook - Version 2
```

On the laptop:

``` bash
cd ~/addressbook

sed -i -E \
's#<h1>.*</h1>#<h1>AddressBook - Version 2</h1>#' \
src/main/webapp/index.jsp
```

Check the change:

``` bash
git diff
```

Commit:

``` bash
git add src/main/webapp/index.jsp
git commit -m "Update AddressBook to Version 2"
```

Push:

``` bash
git push
```

Now the source repository contains the new version.

------------------------------------------------------------------------

## 22.1 Run CI

Run:

``` text
addressbook-ci-1-checkout
addressbook-ci-2-compile
addressbook-ci-3-test
addressbook-ci-4-package
```

Confirm that:

-   Checkout is successful
-   Compile is successful
-   All five tests pass
-   WAR is created
-   WAR is archived

------------------------------------------------------------------------

## 22.2 Run CD

Run:

``` text
addressbook-cd
```

Confirm:

``` text
DEPLOYMENT VERIFIED
```

------------------------------------------------------------------------

## 22.3 Verify the new version

Refresh:

``` text
http://<AGENT_B_IP>:8080/addressbook/
```

The browser should now show:

``` text
AddressBook - Version 2
```

This demonstrates that a source-code change became a deployed
application change through CI/CD.

------------------------------------------------------------------------

# 23. Optional --- Automatically Connect CI and CD

Once the individual CI and CD stages are understood, they can be
connected.

The target is:

``` text
git push
   ↓
CI
   ↓
Package
   ↓
CD
   ↓
Tomcat
```

For a Freestyle implementation, the CI job can trigger the CD job after
a successful build.

For example, configure the upstream CI job with:

``` text
Post-build Actions
    ↓
Build other projects
```

Projects:

``` text
addressbook-cd
```

Use:

``` text
Trigger only if build is stable
```

This creates a safety gate:

``` text
CI SUCCESS
    ↓
CD STARTS

CI FAILURE
    ↓
CD DOES NOT START
```

GitHub polling or a webhook can then be used to initiate CI when source
code changes.

A simple polling example is:

``` text
H/2 * * * *
```

This checks approximately every two minutes.

For a production implementation, a GitHub webhook is generally
preferable to frequent polling.

------------------------------------------------------------------------

# 24. Troubleshooting

## 24.1 `javac: command not found`

Symptom:

``` text
Command 'javac' not found
```

Cause:

Only a Java runtime is installed.

Fix on Agent A:

``` bash
sudo apt update
sudo apt install -y openjdk-21-jdk
```

Verify:

``` bash
javac -version
```

------------------------------------------------------------------------

## 24.2 `release version 21 not supported`

Symptom:

``` text
error: release version 21 not supported
```

Check:

``` bash
java -version
javac -version
mvn -version
```

The Maven compiler must have access to a JDK that supports the
configured release.

------------------------------------------------------------------------

## 24.3 `mvn: command not found`

Install Maven on Agent A:

``` bash
sudo apt update
sudo apt install -y maven
```

Verify:

``` bash
mvn -version
```

------------------------------------------------------------------------

## 24.4 CD cannot copy the WAR

Symptom:

``` text
Failed to copy artifacts
```

Check all of the following:

1.  The CI job actually archived the WAR.
2.  `target/addressbook.war` is listed under Build Artifacts.
3.  The CD project name is correct.
4.  The Copy Artifact plugin is installed.
5.  The source CI job permits `addressbook-cd`.

The permission is configured in:

``` text
addressbook-ci-4-package
    ↓
Configure
    ↓
Permission to Copy Artifact
```

and:

``` text
addressbook-cd
```

must be allowed.

------------------------------------------------------------------------

## 24.5 CD says `DEPLOYMENT FAILED`

On Agent B:

``` bash
ls -l /opt/tomcat/webapps
```

Check Tomcat logs:

``` bash
tail -50 /opt/tomcat/logs/catalina.out
```

Check service status:

``` bash
sudo systemctl status tomcat --no-pager
```

Restart if necessary:

``` bash
sudo systemctl restart tomcat
```

------------------------------------------------------------------------

## 24.6 Browser cannot access port 8080

If this works:

``` bash
curl -I http://localhost:8080
```

but the browser cannot access:

``` text
http://<AGENT_B_IP>:8080
```

check the Azure Network Security Group.

Allow:

``` text
TCP 8080
```

Prefer:

``` text
Source: My IP address
```

for a lab environment.

------------------------------------------------------------------------

## 24.7 Jenkins job works manually but fails in Jenkins

Jenkins may run under a different user or environment.

Add:

``` bash
whoami
hostname
pwd
which java
which javac
which mvn
echo "$JAVA_HOME"
```

to the Jenkins build step.

Compare Jenkins' environment with the interactive SSH session.

------------------------------------------------------------------------

## 24.8 Tomcat is running but the application returns 404

Check:

``` bash
ls -l /opt/tomcat/webapps
```

You should see:

``` text
addressbook.war
addressbook/
```

Check:

``` bash
curl -I http://localhost:8080/addressbook/
```

Tomcat may simply still be unpacking the WAR.

------------------------------------------------------------------------

# 25. What Each Component Does

## GitHub

Stores the source code.

``` text
Developer
   ↓
git push
   ↓
GitHub
```

------------------------------------------------------------------------

## Jenkins Controller

Coordinates the workflow.

It knows:

-   Which job to run
-   Which agent should execute it
-   Which artifacts have been archived
-   Whether builds succeeded or failed

------------------------------------------------------------------------

## Agent A

Performs CI work:

``` text
Checkout
Compile
Test
Package
```

------------------------------------------------------------------------

## Maven

Maven manages the Java build lifecycle.

The important lifecycle steps are:

``` text
compile
   ↓
test
   ↓
package
```

------------------------------------------------------------------------

## WAR

The WAR is the deployable Java web application.

``` text
target/addressbook.war
```

------------------------------------------------------------------------

## Jenkins Artifact Archive

The archive creates a stable handoff between CI and CD.

``` text
Agent A
   |
   | WAR
   v
Jenkins Artifact Store
   |
   v
CD Job
```

------------------------------------------------------------------------

## Agent B

Runs the deployment environment.

``` text
Agent B
   |
   +-- Tomcat
   +-- addressbook.war
```

------------------------------------------------------------------------

## Tomcat

Tomcat runs the Java web application.

The WAR:

``` text
addressbook.war
```

becomes:

``` text
/addressbook/
```

------------------------------------------------------------------------

# 26. Production Thinking

This lab intentionally keeps the implementation simple enough to
understand.

In a production environment, several areas would normally be improved.

## Artifact Management

Instead of relying only on Jenkins archived artifacts, organizations may
use:

-   Nexus
-   JFrog Artifactory
-   Cloud artifact repositories
-   Object storage

The principle remains the same:

``` text
Build once
Store artifact
Deploy the same artifact
```

------------------------------------------------------------------------

## Deployment Strategy

This lab performs a direct deployment into Tomcat.

Production environments may use:

-   Blue/green deployment
-   Rolling deployment
-   Canary deployment
-   Kubernetes deployments
-   Immutable infrastructure

------------------------------------------------------------------------

## Credentials

This lab uses a public GitHub repository for simplicity.

Production systems should use appropriate Jenkins credentials for
private repositories and deployment systems.

Do not place passwords, tokens, or private keys directly inside:

``` text
Jenkinsfile
Shell scripts
Source code
Git repositories
```

------------------------------------------------------------------------

## Security

Production systems should also consider:

-   TLS
-   Secrets management
-   Least-privilege access
-   Network segmentation
-   Restricted security groups
-   Artifact integrity
-   Dependency scanning
-   SAST
-   DAST
-   Container/image scanning
-   Audit logging

------------------------------------------------------------------------

## Jenkins Controller

The Controller should generally be treated as an
orchestration/control-plane component rather than a general-purpose
build server.

Dedicated agents provide better separation between:

``` text
Jenkins management
```

and:

``` text
Build execution
```

------------------------------------------------------------------------

# 27. Lab Validation Checklist

## Application

-   [ ] `pom.xml` exists
-   [ ] `Contact.java` exists
-   [ ] `AddressBook.java` exists
-   [ ] `AddressBookTest.java` exists
-   [ ] `index.jsp` exists
-   [ ] `.gitignore` exists

## GitHub

-   [ ] Repository exists
-   [ ] `main` branch exists
-   [ ] Source code is pushed
-   [ ] `target/` is not committed

## Agent A

-   [ ] Java installed
-   [ ] `javac` available
-   [ ] Maven installed
-   [ ] Git installed
-   [ ] Jenkins agent online

## Jenkins CI

-   [ ] Checkout job succeeds
-   [ ] Compile job succeeds
-   [ ] Test job succeeds
-   [ ] Five tests pass
-   [ ] Package job succeeds
-   [ ] WAR exists
-   [ ] WAR is archived

## Agent B

-   [ ] Java installed
-   [ ] Tomcat installed
-   [ ] Tomcat service active
-   [ ] Port 8080 accessible
-   [ ] `/opt/tomcat` is writable by the Jenkins agent user

## Jenkins CD

-   [ ] CD runs on Agent B
-   [ ] WAR is copied from CI
-   [ ] WAR is copied into Tomcat
-   [ ] Application returns HTTP 200
-   [ ] `DEPLOYMENT VERIFIED` appears

## Browser

-   [ ] `/addressbook/` loads
-   [ ] AddressBook page appears
-   [ ] Contacts are displayed
-   [ ] Served-by-host shows AgentB

------------------------------------------------------------------------

# 28. Cleanup

If the lab is being paused, stop Tomcat:

``` bash
sudo systemctl stop tomcat
```

If the lab infrastructure is hosted in Azure, stop/deallocate the VMs
when they are no longer needed to avoid unnecessary compute charges.

If public IPs change after stopping and restarting VMs, update the
relevant Jenkins and network configuration.

If a GitHub Personal Access Token was created specifically for the lab,
revoke it when it is no longer required.

------------------------------------------------------------------------

# 29. Next Step --- Pipeline as Code

This lab uses Freestyle jobs deliberately so that each CI/CD activity is
visible.

The next evolution is to represent the same workflow as a Jenkinsfile.

The Freestyle architecture:

``` text
Checkout Job
      ↓
Compile Job
      ↓
Test Job
      ↓
Package Job
      ↓
CD Job
```

can eventually become:

``` text
pipeline {
    stages {
        stage('Checkout') {
            ...
        }

        stage('Compile') {
            ...
        }

        stage('Test') {
            ...
        }

        stage('Package') {
            ...
        }

        stage('Deploy') {
            ...
        }
    }
}
```

The important transition is:

``` text
Freestyle Configuration
        ↓
Pipeline as Code
        ↓
Jenkinsfile
        ↓
Version-controlled CI/CD
```

The Freestyle implementation in this lab provides the conceptual
foundation for understanding that transition.

------------------------------------------------------------------------

# Final Architecture

The completed lab can be summarized as:

``` text
                         DEVELOPER
                             |
                             | git push
                             v
                         GITHUB
                             |
                             v
                  +---------------------+
                  | JENKINS CONTROLLER  |
                  |   Orchestration     |
                  +----------+----------+
                             |
             +---------------+---------------+
             |                               |
             v                               v
      +--------------+                +--------------+
      |    AGENT A   |                |    AGENT B   |
      |      CI      |                |      CD      |
      +--------------+                +--------------+
      |              |                |              |
      | Checkout     |                | Copy WAR     |
      | Compile      |                | Deploy WAR   |
      | Test         |                | Verify HTTP  |
      | Package      |                |              |
      +------+-------+                +------+-------+
             |                               |
             | addressbook.war               |
             +-----------> Jenkins <---------+
                                             |
                                             v
                                         TOMCAT
                                             |
                                             v
                                      /addressbook/
                                             |
                                             v
                                         BROWSER
```

The core lesson is simple:

``` text
CODE
 ↓
BUILD
 ↓
TEST
 ↓
PACKAGE
 ↓
ARTIFACT
 ↓
DEPLOY
 ↓
VERIFY
```

That is the complete CI/CD journey demonstrated by this lab.

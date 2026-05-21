# Homelab DevOps Setup & GitLab CI/CD Guide

This guide details the step-by-step process to configure your newly provisioned Proxmox VMs, install GitLab CE, register a GitLab Runner, and establish the continuous deployment flow for your Node.js application.

---

## 1. Newly Provisioned Virtual Machines (Debian 12)

Your Proxmox server (`192.168.8.171`) now has two specialized Debian 12 VMs running under VM IDs `200` and `201`:

- **VM 200 (DevOps GitLab Server)**:
  - **Hostname**: `gitlab-debian12`
  - **Specs**: 4 Cores, 6GB RAM, 50GB Disk space.
  - **Purpose**: Runs GitLab CE (Code Repository, Container Registry, CI/CD Engine).
- **VM 201 (Production & Runner Server)**:
  - **Hostname**: `prod-debian12`
  - **Specs**: 2 Cores, 3GB RAM, 30GB Disk space.
  - **Purpose**: Runs GitLab Runner (Docker executor) and hosts the live Node.js web application.

---

## 2. VM 200: Installing GitLab CE (Self-Hosted)

The most robust and clean way to self-host GitLab CE on a Debian 12 VM is using **Docker Compose**.

### Step A: Connect to VM 200
SSH into your GitLab VM (replace `<GITLAB_VM_IP>` with the IP printed by the provisioning script or found in Proxmox):
```bash
ssh debian@<GITLAB_VM_IP>
```

### Step B: Install Docker & Docker Compose
Run the official Docker convenience script to install Docker:
```bash
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker debian
newgrp docker
```

### Step C: Deploy GitLab CE via Docker Compose
Create a directory for GitLab and deploy it:
```bash
mkdir -p ~/gitlab && cd ~/gitlab
```

Create a `docker-compose.yml` file:
```yaml
services:
  gitlab:
    image: 'gitlab/gitlab-ce:latest'
    restart: always
    hostname: 'gitlab.local'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://<GITLAB_VM_IP>'
        gitlab_rails['initial_root_password'] = 'SuperSecureGitLabPassword123'
        # Enable Container Registry
        registry_external_url 'http://<GITLAB_VM_IP>:5050'
        gitlab_rails['registry_enabled'] = true
    ports:
      - '80:80'
      - '443:443'
      - '2222:22'
      - '5050:5050'
    volumes:
      - './config:/etc/gitlab'
      - './logs:/var/log/gitlab'
      - './data:/var/opt/gitlab'
```
> [!IMPORTANT]
> Replace `<GITLAB_VM_IP>` with the actual IP address of VM 200 in the `external_url` and `registry_external_url` configs!

Start GitLab (this takes ~3-5 minutes to perform its first boot):
```bash
docker compose up -d
```

### Step D: Retrieve GitLab Root Password
To log into GitLab, open your web browser and go to `http://<GITLAB_VM_IP>`. The username is `root`.
If you did not specify an initial root password, retrieve the auto-generated one from:
```bash
sudo docker exec -it gitlab-gitlab-1 grep 'Password:' /etc/gitlab/initial_root_password
```

---

## 3. VM 201: Configuring Docker, GitLab Runner, & Production Env

VM 201 acts as both our isolated CI/CD runner and the production host for our containerized app.

### Step A: Connect to VM 201
```bash
ssh debian@<PROD_VM_IP>
```

### Step B: Install Docker & Docker Compose
```bash
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker debian
newgrp docker
```

### Step C: Install GitLab Runner
Download the official GitLab Runner binary and start it inside a lightweight docker container (or install native system service). Running it inside Docker is highly recommended:
```bash
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

### Step D: Register the Runner with GitLab CE
1. In your web browser, navigate to GitLab (`http://<GITLAB_VM_IP>`), log in, and create a blank project for your Node App.
2. Go to **Settings > CI/CD > Runners** (expand the section).
3. Click **New project runner**. Set tags (e.g. `docker`, `homelab`) and click **Create runner**.
4. Copy the registration command or token provided.
5. Register the runner by running this command on VM 201:
```bash
docker exec -it gitlab-runner gitlab-runner register \
  --url "http://<GITLAB_VM_IP>/" \
  --clone-url "http://<GITLAB_VM_IP>/" \
  --registration-token "<YOUR_RUNNER_REGISTRATION_TOKEN>" \
  --executor "docker" \
  --docker-image "docker:24.0.7" \
  --description "Homelab Debian 12 Docker Runner" \
  --docker-privileged \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"
```
> [!WARNING]
> The `--docker-privileged` flag and mounting `/var/run/docker.sock` are crucial. They enable Docker-in-Docker (`dind`) inside your pipeline so the runner can build and push your Node.js application image!

---

## 4. Configuring SSH Deployment Keys

To allow the GitLab CI/CD pipeline to deploy seamlessly to VM 201:

1. **Generate a Deployment SSH key pair** on Andrii's host (or directly in GitLab):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/gitlab_deploy_key -N ""
   ```
2. **Authorize the public key** on VM 201:
   Copy the content of `~/.ssh/gitlab_deploy_key.pub` and add it to VM 201's authorized keys list:
   ```bash
   ssh debian@<PROD_VM_IP> "echo '$(cat ~/.ssh/gitlab_deploy_key.pub)' >> ~/.ssh/authorized_keys"
   ```

---

## 5. Setting up GitLab CI/CD Environment Variables

In GitLab CE, navigate to your project **Settings > CI/CD > Variables**, click **Add variable**, and input:

1. `SSH_PRIVATE_KEY`: Paste the *entire* private key content of your deployment key (from `~/.ssh/gitlab_deploy_key`). Make sure to hit enter on the last line.
2. `PROD_VM_IP`: The IP address of your production VM 201.
3. `CI_REGISTRY_USER`: `root` (or your GitLab username).
4. `CI_REGISTRY_PASSWORD`: Your GitLab access password or a **Personal Access Token** with `read_registry` and `write_registry` permissions (highly recommended).

---

## 6. Pushing Code and Triggering the Pipeline

Now, initialize git in your local project and push it to your new GitLab server:
```bash
cd /home/andrii/Playground/node_app/node
git init
git remote add origin http://<GITLAB_VM_IP>/root/<project-name>.git
git add .
git commit -m "feat: complete devops pipeline initialization"
git push -u origin master
```

As soon as you push:
1. **GitLab** will trigger the `.gitlab-ci.yml` pipeline.
2. **VM 201's Runner** will fetch the job, execute linting and unit testing.
3. If tests pass, it will compile the Docker image and push it to **VM 200's Container Registry** (`:latest` and `:commit-sha`).
4. Finally, it will connect to **VM 201** via SSH, pull the new container image, and run `docker compose up -d`!
5. Open `http://<PROD_VM_IP>:3000` in your browser to see your glassmorphic dark-mode DevOps dashboard alive and displaying host metrics!

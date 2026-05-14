# SSH Setup for ZeroClaw Agent

This guide describes how to securely grant the ZeroClaw agent access to other machines in your local network.

## Best Practice: Dedicated Agent Key

We recommend giving the agent its own SSH key rather than re-using your personal user key.

- **Auditing**: Remote logs will clearly show actions performed by the agent.
- **Security**: You can revoke the agent's access without affecting your own.
- **Least Privilege**: You can restrict the agent's key to specific commands using `authorized_keys` options on the remote host.

## Step-by-Step Setup

### 1. Generate the Agent Keypair

Run this on the host machine where the Uplift stack is installed:

```bash
# Create a dedicated directory for agent SSH data
mkdir -p ~/.zeroclaw/ssh

# Generate an Ed25519 keypair with no passphrase
ssh-keygen -t ed25519 -f ~/.zeroclaw/ssh/id_ed25519_agent -N "" -C "ZeroClaw Agent @ $(hostname)"
```

### 2. Configure Docker Mounts

Update your `docker-compose.yml` to mount the dedicated SSH directory into the ZeroClaw container:

```yaml
services:
  zeroclaw:
    # ...
    volumes:
      - ./.zeroclaw:/zeroclaw-data/.zeroclaw
      - ./workspace:/zeroclaw-data/workspace
      - ~/.zeroclaw/ssh:/zeroclaw-data/.ssh:ro # Mount the agent keys
```

### 3. Update ZeroClaw Policy

Ensure your `.zeroclaw/config.toml` permits SSH execution and access to the key directory:

```toml
[autonomy]
# Explicitly allow the ssh command
allowed_commands = ["*", "ssh"]

# Allow the agent to read its own keys
allowed_roots = ["~/.ssh"]

# (Recommended) Enable Host Network mode if resolving .local hostnames
# network_mode: host in docker-compose.yml
```

### 4. Authorize the Agent on Remote Hosts

Copy the agent's public key to every machine it needs to manage:

```bash
ssh-copy-id -i ~/.zeroclaw/ssh/id_ed25519_agent.pub <remote-user>@<remote-host>
```

### 5. Verify Access

Ask the agent to check the remote host:

> "Run `ssh <remote-user>@<remote-host> uname -a` and use `approved=true`."

## Security & Multi-User Access (RBAC)

In a lab or production environment, you often need **Role-Based Access Control (RBAC)**. This means granting different levels of permission based on who is talking to the agent.

ZeroClaw provides several layers of protection to ensure your privileged "DevOps" agent remains secure.

### Multi-Tiered Access Strategies

Currently, ZeroClaw enforces a single `SecurityPolicy` per running daemon. If you need a two-tier system (e.g., a "Public" bot for general chat and a "DevOps" bot for SSH tasks), we recommend the **Multi-Agent Strategy**:

#### 1. The Admin Agent (Privileged)
*   **Permissions**: `allowed_commands = ["*", "ssh"]`, `level = "full"`.
*   **Access**: `allowed_users = ["U12345"]` (Only your team's Slack IDs).
*   **Credentials**: Uses the dedicated `id_ed25519_agent` SSH key.
*   **Deployment**: Runs as a separate Docker service in `docker-compose.yml`.

#### 2. The Operator Agent (Restricted)
*   **Permissions**: `allowed_commands = ["ls", "git", "grep"]`, `level = "supervised"`.
*   **Access**: `allowed_users = ["*"]` (Responds to everyone in the lab).
*   **Credentials**: **No SSH keys mounted**.
*   **Safety**: Even if the LLM is tricked, the `ssh` binary isn't allowed by policy, and no keys exist in its environment.

### Channel-Level Identity

ZeroClaw automatically tracks the unique identity of every sender across all channels (Slack, Discord, Matrix, etc.).

*   **Audit Trail**: Every action performed via SSH is logged with the `sender_id` of the user who requested it.
*   **Rate Limiting**: Each user has an independent "Action Budget." If one user spans the bot, they will be rate-limited without affecting the devops team's ability to use the agent.

### Configuring Your Devops Team

To restrict your privileged agent to specific users, update your `config.toml`:

```toml
[channels.slack]
enabled = true
# List the Slack Member IDs of your authorized DevOps team
allowed_users = ["U01ABCDEFGH", "U02IJKLMNOP"] 
```

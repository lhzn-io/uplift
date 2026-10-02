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

`docker-compose.yml` mounts the dedicated SSH directory into the admin agent only. The container's `HOME` is `/zeroclaw-data`, so this is the agent's `~/.ssh`:

```yaml
services:
  zeroclaw-admin:
    # ...
    volumes:
      - ~/.zeroclaw/ssh:/zeroclaw-data/.ssh:ro # Mount the agent keys
```

The mount is read-only, so the agent cannot add host keys itself. Record them on the Jetson host instead, which also pins them:

```bash
ssh-keyscan -t ed25519 <remote-host> >> ~/.zeroclaw/ssh/known_hosts
```

### 3. Update ZeroClaw Policy

Ensure your `.zeroclaw/config.toml` permits SSH execution and access to the key directory:

```toml
[autonomy]
# Explicitly allow the ssh command
allowed_commands = ["*", "ssh"]

# Allow the agent to read its own keys
allowed_roots = ["~/.ssh"]
```

Use unicast DNS names or addresses for remote hosts. mDNS (`.local`) names do not resolve from inside a container or across a routed VPN.

### 4. Authorize the Agent on Remote Hosts

Copy the agent's public key to every machine it needs to manage:

```bash
ssh-copy-id -i ~/.zeroclaw/ssh/id_ed25519_agent.pub <remote-user>@<remote-host>
```

Then restrict the key on each remote host. ZeroClaw's sandbox confines the agent on the Jetson; these options confine what a leaked or misused agent key can do elsewhere. Edit the copied line in the remote `~/.ssh/authorized_keys` so it starts with:

```text
from="<jetson-ip>",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 AAAA... ZeroClaw Agent @ <jetson-host>
```

*   `from=` limits the key to the Jetson's own address (use a fixed DHCP reservation so it does not change).
*   The `no-*` options stop the key being used as a tunnel or to reach a forwarded agent.
*   Where the agent only needs a fixed task, add `command="..."` to pin it to that one command.

Changing `authorized_keys` on another host is a change to that host's access policy; agree it with the host's owner first.

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

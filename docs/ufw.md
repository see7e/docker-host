# UFW
**UFW** stands for **Uncomplicated Firewall**. It is **not a firewall itself** in the sense of a packet-filtering engine. Instead, it's a **management tool** that makes it easier to configure the Linux firewall.

Here's the relationship:

* **Firewall**: The security mechanism that filters network traffic according to rules (allow, deny, reject, etc.).
* **UFW**: A command-line interface that creates and manages firewall rules for the underlying Linux firewall.

### How it works
On modern Linux systems:
```
Your commands
      │
      ▼
    UFW (easy-to-use interface)
      │
      ▼
iptables / nftables (kernel firewall framework)
      │
      ▼
Linux kernel filters network packets
```

Historically, UFW configured **iptables**. On many modern distributions, including recent Ubuntu releases, UFW uses the **nftables** backend while preserving the same simple interface.

### Why use UFW?
Managing firewall rules directly with `iptables` or `nft` can be complex. UFW simplifies common tasks.

For example:
```bash
sudo ufw enable
```

Enable the firewall.  Allow SSH:
```bash
sudo ufw allow 22
```

or
```bash
sudo ufw allow ssh
```

Allow HTTP:
```bash
sudo ufw allow 80
```

Block a port:
```bash
sudo ufw deny 23
```

See the current rules:
```bash
sudo ufw status
```

### Example
Suppose your server runs:
* SSH on port 22
* A web server on port 80

You could configure UFW like this:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw enable
```

This means:
* ❌ Block all incoming connections by default.
* ✅ Allow outgoing connections.
* ✅ Permit SSH access.
* ✅ Permit web traffic.

### Analogy
Think of it like this:
* **Firewall** = the security guard at the building entrance.
* **UFW** = the receptionist who gives the security guard clear instructions about who may enter.

The security guard actually enforces the rules; the receptionist simply provides an easier way to manage them.

### Other firewall management tools
UFW is one of several tools that manage Linux firewalls. Others include:
* **firewalld** (common on Fedora, RHEL, and CentOS)
* Direct use of **nft** (the native nftables command-line tool)
* Direct use of **iptables** (older but still widely encountered)

In short, **UFW is a user-friendly interface for configuring the Linux firewall**, making it much easier to define and manage network access rules without working directly with the underlying firewall framework.

You can check whether **UFW is enabled** with:
```bash
sudo ufw status
```

Typical outputs:
**Enabled:**

```text
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
```

**Disabled:**
```text
Status: inactive
```

### Get more details
To see numbered rules:
```bash
sudo ufw status numbered
```

To see verbose information, including default policies:
```bash
sudo ufw status verbose
```

Example:
```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip
```

### Check the systemd service
You can also check whether the UFW service is enabled at boot:
```bash
systemctl status ufw
```

or
```bash
systemctl is-enabled ufw
```

Keep in mind that **the systemd service being enabled is not the same as the firewall being active**. The most reliable command to determine whether UFW is currently enforcing firewall rules is:

```bash
sudo ufw status
```

If it reports `Status: active`, UFW is enabled and filtering traffic. If it reports `Status: inactive`, it is not.

# FastDeploy: High-Performance FastAPI Deployment Script 🚀

**FastDeploy** is a battle-tested, production-ready Bash script designed to deploy **FastAPI** applications on **Ubuntu** and **Debian** servers with a single command. It automates the entire stack configuration, optimizing for maximum performance and security.

---

## 🏗️ Architecture & Modular Design

FastDeploy has been engineered with a modular architecture for easy maintenance and extensibility.

```
.
├── FastDeploy.sh            # Main entry point (orchestrator)
└── lib/
    ├── core/                # Core utilities (logging, input validation)
    ├── system/              # System prep (kernel tuning, prereqs, network)
    ├── app/                 # App setup (git clone, python venv)
    └── services/            # Service config (Systemd, Nginx, Cleanup)
```

---

## ⚡ FastDeploy vs. Docker 🐳

Why choose a "Bare Metal" script over Docker?

| Feature | FastDeploy (Bare Metal) | Docker / Containers |
| :--- | :--- | :--- |
| **Performance** | **Native Performance**: Runs directly on the OS kernel. No overlayfs overhead, no bridge networking overhead. Ideal for high-throughput, low-latency APIs. | **Near-Native**: Slight overhead due to namespace isolation, NAT/Bridge networking, and filesystem layering. |
| **Complexity** | **Simple**: Standard Linux tools (Systemd, Nginx). Easy to debug with standard commands (`systemctl`, `journalctl`, `htop`). | **High**: Requires ongoing management of images, containers, networks, and potentially orchestration (K8s/Compose). |
| **Resource Usage** | **Minimal**: No Docker daemon RAM/CPU footprint. Every byte of RAM goes to your app and OS cache. | **Moderate**: Docker daemon and containerd use resources. Each container allocates its own userspace. |
| **Persistence** | **Native**: Files are on the disk. Database is a standard service. No concepts of "ephemeral" storage to manage. | **Ephemeral**: Requires volume mounting and management for data persistence. |
| **Updates** | **Standard**: `apt upgrade` updates the OS. `git pull` updates the app. | **Image-based**: Requires rebuilding and redeploying images for every OS or App change. |
| **Ideal For** | **Single Server / VPS**: Perfect for dedicated deployments where raw performance and simplicity are key. | **Microservices / Clusters**: Better for complex, distributed applications needing orchestration. |

**Choose FastDeploy if:** You want your API to scream fast on a VPS without the cognitive load of managing container orchestration.

---

## ✨ Features

- **Automated Stack Setup**: Nginx (Reverse Proxy), Systemd (Process Management), Uvicorn (ASGI Server).
- **Kernel Tuning**: Applies `sysctl` optimizations (BBR congestion control, increased file descriptors, TCP stack tuning) for high concurrency.
- **Security First**: Creates a dedicated system user, sets strict permissions, configures Nginx security headers, and enables UFW (optional/system dependent).
- **SSL Ready**: Integrated Let's Encrypt (Certbot) support or Cloudflare guidance.
- **Zero Downtime**: Nginx configured with `upstream` keep-alives and smooth reloading.
- **Interactive**: Guided "Easy Mode" for beginners and "Advanced Mode" for power users.
- **Lifecycle Management**: Built-in tools to update configurations (scale workers, tune limits) or uninstall apps cleanly.

## 🚀 Quick Start

1.  **Download & Run**:
    ```bash
    wget https://raw.githubusercontent.com/your-repo/FastDeploy/main/FastDeploy.sh
    chmod +x FastDeploy.sh
    sudo ./FastDeploy.sh
    ```

2.  **Follow the Prompts**:
    - Choose **Install**.
    - Enter your **GitHub Repo URL**.
    - Enter your **Domain Name**.
    - Sit back as FastDeploy configures your server.

## 🔄 Update & Uninstallation

FastDeploy includes built-in commands to manage your application lifecycle.

### Update Configurations
Run the script and select **Configure** (`C`) to:
- **Scale Resources**: Adjust Systemd CPU/Memory limits and Worker counts on the fly.
- **Tune Performance**: Modify Uvicorn concurrency, backlog, and Nginx compression levels.
- **Update Domains**: Change your application's domain name or port.

### Uninstall
Run the script and select **Uninstall** (`U`) to cleanly remove:
- The Systemd service and Nginx configuration.
- The application directory and virtual environment.
- The dedicated system user and group.

## ☁️ Recommended Hosting

Get **€20 in cloud credits** on **Hetzner Cloud** to try FastDeploy risk-free!
[**Claim your €20 here**](https://hetzner.cloud/?ref=kY6yiSVTkbbr)

## 🛠️ Requirements

- **OS**: Ubuntu 20.04/22.04/24.04, Debian 11/12/13
- **User**: Root or user with sudo privileges.
- **Ports**: 80/443 (HTTP/HTTPS) and a custom port for Uvicorn (script will suggest one).

## 📂 What it Does

1.  **System Prep**: Updates packages, installs `nginx`, `git`, `python3-venv`, `certbot`.
2.  **Kernel Optimization**: Enables BBR, increases max open files (`fs.file-max`), optimizes TCP backlog.
3.  **App Setup**: Clones your repo, creates a venv, installs dependencies.
4.  **Service Creation**:
    - Generates a **Systemd** service (`your-app.service`) for Uvicorn with resource limits (`MemoryMax`, `CPUQuota`).
    - Generates an **Nginx** block (`/etc/nginx/sites-available/your-app`) with caching, compression, and timeouts tuned for APIs.
5.  **Launch**: Starts the app and reloads Nginx.

## 🤝 Contributing

Modules are located in `lib/`. Feel free to submit PRs for new features or optimizations!

## 📄 License

This project is licensed under the GNU License - see the [LICENSE](LICENSE.md) file for details.
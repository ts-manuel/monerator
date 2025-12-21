# Monero P2Pool XMRIG Setup

![monerator-menu](https://github.com/user-attachments/assets/6daf1551-58f9-4283-8b43-1c862a7c6475)

<details open="open">
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#introduction">Introduction</a></li>
    <li><a href="#features">Features</a></li>
    <li><a href="#requirements">Requirements</a></li>
    <li><a href="#installation">Installation</a></li>
    <li><a href="#configuration">Configuration</a></li>
    <li><a href="#usage">Usage</a></li>
    <ol>
      <li><a href="#available-commands">Available Commands</a></li>
      <li><a href="#examples">Examples</a></li>
      <li><a href="#service-management">Service Management</a></li>
    </ol>
    <li><a href="#important-notes">Important Notes</a></li>
    <li><a href="#troubleshooting">Troubleshooting</a></li>
    <li><a href="#references">References</a></li>
  </ol>
</details>


## Introduction

**Monerator** is an automation tool that simplifies the setup of **Monero**, **P2Pool**, and **XMRig**.  
Each component can be installed and configured independently using user-editable configuration files located in the `config/` directory, allowing full control over the installation process.

Monerator is compatible with **Ubuntu and Debian-based Linux distributions**.
Work is based on monerominer by Mik: https://github.com/mik-tf/monerominer

## Features

- Automated installation of:
  - Monero daemon
  - P2Pool
  - XMRig
- Modular design: install only the components you need
- Per-component configuration via editable config files
- Designed for reproducible and customizable setups
- Minimal dependencies, simple execution
- Systemd service integration
- Service management commands
- Mining statistics monitoring

## Requirements

- Monero Wallet Address
- Ubuntu/Debian based system
- Minimum 2GB RAM (4GB+ recommended)
- Multi-core CPU
- Sudo privileges
- Internet connection

To create a new Monero wallet, consult the Monero documentation:
- [GUI Wallet](https://www.getmonero.org/downloads/#gui)
- [CLI Wallet](https://www.getmonero.org/downloads/#cli)

## Installation

```bash
git clone https://github.com/ts-manuel/monerator.git

cd monerator

./monerator install
```

## Configuration

All configuration files are stored in the `config/` directory.

Each component (**Monero**, **P2Pool**, **XMRig**) has its own configuration file, which can be edited by the user before running the installer to customize:
- Installation behavior
- Runtime options
- Network and mining parameters

This allows fine-grained control without modifying the main script.

## Usage

```bash
# From the monarator directory
./monerator [COMMAND]
```

### Available Commands

- `install` - Run installation and setup
- `uninstall` - Remove installed componets
- `start` - Start all mining services
- `stop` - Stop all mining services
- `status` - Show status of all services
- `logs` - Show logs for each componet
- `delete_logs` - Delete lof files
- `help` - Show help message

### Examples

```bash
./monerator install   # Run installation and setup
./monerator uninstall # Remove installed componets
./monerator logs      # Show logs for each componet
```

### Service Management

The script creates and manages three systemd services:
1. `monerod.service` - Monero blockchain daemon
2. `p2pool.service` - P2Pool mining node
3. `xmrig.service` - CPU mining service

```bash
./monerator start    # Start all services
./monerator stop     # Stop all services
./monerator status   # Check service status
```
## Important Notes

- Ensure your wallet address is correct
- Consider using P2Pool Mini for hashrates < 50 kH/s
- Keep your system updated and secured
- Initial blockchain sync may take several days
- Mining rewards go directly to your wallet
- Use at your own risk

## Troubleshooting

If you encounter issues:
1. Check service status: `./monerator status`
2. View service logs: `journalctl -u [service-name]`
3. Ensure sufficient disk space for blockchain
4. Verify CPU compatibility with RandomX
5. Check mining logs: `./monerator logs`

## References

For more information on Monero and P2Pool:
- [Monero Documentation](https://www.getmonero.org/resources/user-guides/)
- [P2Pool Documentation](https://github.com/SChernykh/p2pool)
- [XMRig Documentation](https://xmrig.com/docs)

This work is based on monerominer by Mik: https://github.com/mik-tf/monerominer

We are not endorsing Monero nor are a partner of Monero. This is for educational purpose only.
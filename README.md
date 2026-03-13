<!-- markdownlint-disable MD041 -->

# Censys - Google SecOps SOAR Integration

This repository contains the Google SecOps SOAR dashboard for the Censys integration, providing operational visibility into integration usage and effectiveness.

---

## Google SecOps SOAR Integration

### Repository Contents

| Component           | Description                                               | Path                                                                                 |
| ------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **Dashboards**      | Pre-built dashboards for monitoring integration usage and effectiveness | [`Dashboards/`](./Dashboards/)               |

> 📖 **Documentation:**
>
> - [Dashboards Documentation](./Dashboards/README.md)
> - [User Guide](./docs/Censys%20-%20Google%20SecOps%20SOAR%20Integration%20-%20User%20Guide.pdf)

---

## Overview

The Censys Google SecOps SOAR integration enables security teams to automate asset intelligence gathering, infrastructure analysis, and threat investigation workflows. This dashboard provides operational visibility to monitor integration usage and measure automation value.

---

## Quick Start

### 1. Install the Censys Integration

Install the Censys integration from the Google SecOps Content Hub:

1. Navigate to **Content Hub > Response Integrations**
2. Search for "Censys"
3. Click **Install** and configure with your Censys API credentials

For detailed installation instructions, refer to the [User Guide](./docs/).

### 2. Import Dashboard

Import the pre-built dashboard to monitor integration usage:

1. Navigate to **Dashboards & Reports > Dashboards**
2. Click **New dashboard** > **Import from JSON**
3. Upload the [Censys SOAR Dashboard.json](./Dashboards/Censys%20SOAR%20Dashboard.json)

See the [Dashboards Documentation](./Dashboards/README.md) for panel descriptions and best practices.

---


## Dashboard Overview

The Censys SOAR Dashboard provides visibility into:

- **Action Execution Metrics:** Monitor Censys action usage and automation volume
- **Usage Patterns:** Visualize integration adoption across your SOC
- **Popular Actions:** Identify the most frequently used Censys capabilities

For detailed panel descriptions and insights, see the [Dashboards Documentation](./Dashboards/README.md).

---


## Prerequisites

- Google SecOps SOAR instance
- Censys API credentials (API ID, API Secret, Organization ID)

---


## References

- [Google SecOps SOAR Documentation](https://cloud.google.com/chronicle/docs/secops/google-secops-soar-toc)
- [Google SecOps Dashboards](https://cloud.google.com/chronicle/docs/soar/dashboards)
- [Censys User Guide](./docs/Censys%20-%20Google%20SecOps%20SOAR%20Integration%20-%20User%20Guide.pdf)

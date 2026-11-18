<!-- markdownlint-disable MD041 -->

# Censys - Google SecOps Integrations

This repository contains Google SecOps content for Censys:

- **SOAR:** a dashboard that provides operational visibility into usage and effectiveness of the Censys SOAR integration.
- **SIEM:** the Censys Supplier Risk (SR) integration, which ingests Censys supplier risk events into Google SecOps SIEM, normalizes them to UDM, and visualizes and alerts on them.

---

## Repository Contents

| Component                        | Description                                                                  | Path                                                   |
| -------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------ |
| **SOAR Dashboards**              | Pre-built dashboards for monitoring SOAR integration usage and effectiveness | [`Dashboards/`](./Dashboards/)                         |
| **SIEM Ingestion Script**        | Cloud Function ZIP and the deployment script for Censys SR ingestion         | [`siem/ingestion_script/`](./siem/ingestion_script/)   |
| **SIEM Parser**                  | CBN parser (`.conf`) that normalizes Censys SR risk events to UDM            | [`siem/parser/`](./siem/parser/)                       |
| **SIEM Dashboard**               | Censys - Supplier Risk Overview dashboard (JSON)                             | [`siem/dashboard/`](./siem/dashboard/)                 |
| **SIEM Detection Rule**          | YARA-L rule for open HIGH/CRITICAL supplier risks                            | [`siem/rule/`](./siem/rule/)                           |
| **Documentation**                | User guides                                                                  | [`docs/`](./docs/)                                     |

```text
.
├── Dashboards/                  # SOAR dashboard
├── docs/                        # User guides
└── siem/
    ├── ingestion_script/        # Cloud Function ZIP + censys_deploy.sh
    ├── parser/                  # CBN parser (.conf)
    ├── dashboard/               # Censys - Supplier Risk Overview.json
    └── rule/                    # censys_sr_open_high_critical_risk.yaral
```

---

## Google SecOps SOAR Integration

> 📖 **Documentation:**
>
> - [Dashboards Documentation](./Dashboards/README.md)
> - [User Guide](./docs/Censys%20-%20Google%20SecOps%20SOAR%20Integration%20-%20User%20Guide.pdf)

### Overview

The Censys Google SecOps SOAR integration enables security teams to automate asset intelligence gathering, infrastructure analysis, and threat investigation workflows. This dashboard provides operational visibility to monitor integration usage and measure automation value.

### Quick Start

#### 1. Install the Censys Integration

Install the Censys integration from the Google SecOps Content Hub:

1. Navigate to **Content Hub > Response Integrations**
2. Search for "Censys"
3. Click **Install** and configure with your Censys API credentials

For detailed installation instructions, refer to the [User Guide](./docs/).

#### 2. Import Dashboard

Import the pre-built dashboard to monitor integration usage:

1. Navigate to **Dashboards & Reports > Dashboards**
2. Click **New dashboard** > **Import from JSON**
3. Upload the [Censys SOAR Dashboard.json](./Dashboards/Censys%20SOAR%20Dashboard.json)

See the [Dashboards Documentation](./Dashboards/README.md) for panel descriptions and best practices.

### Dashboard Overview

The Censys SOAR Dashboard provides visibility into:

- **Action Execution Metrics:** Monitor Censys action usage and automation volume
- **Usage Patterns:** Visualize integration adoption across your SOC
- **Popular Actions:** Identify the most frequently used Censys capabilities

For detailed panel descriptions and insights, see the [Dashboards Documentation](./Dashboards/README.md).

### Prerequisites

- Google SecOps SOAR instance
- Censys API credentials (API ID, API Secret, Organization ID)

---

## Google SecOps SIEM Integration (Censys Supplier Risk)

### Overview

The Censys Supplier Risk (SR) integration brings supplier risk findings from the Censys Platform into Google SecOps SIEM:

```text
Cloud Scheduler (cron) → Cloud Function → Censys /v1/supplychains/default/risk-events → Google SecOps Ingestion API
                                                                                              │
                                    CBN parser (UDM) → Dashboard + Detection rule  ◄──────────┘
```

1. A **Cloud Function**, triggered by **Cloud Scheduler**, polls the Censys risk-events API and ingests one log per risk event into Google SecOps with the log type `CENSYS_SUPPLIER_RISK_CUSTOM`. Progress is checkpointed in a GCS bucket.
2. The **parser** normalizes each risk event to UDM (target IP/hostname/port, network protocols, and a `security_result` with the risk, severity, confidence, supplier and status).
3. The **dashboard** visualizes supplier risk posture, and the **detection rule** raises alerts for open HIGH/CRITICAL risks.

### Prerequisites

- Google SecOps instance with permission to manage log types, parsers, dashboards and rules (`chronicle.admin` or equivalent)
- GCP project with the Cloud Functions, Cloud Run, Cloud Build, Artifact Registry, Cloud Scheduler, Cloud Storage, Secret Manager and Chronicle APIs enabled (the deployment script enables them)
- Censys Platform Organization ID and a Personal Access Token (PAT) with Supply Chain Intelligence access
- Access to Google Cloud Shell (or a machine with the `gcloud` CLI)

### Deployment Order

Deploy the components in this order. The parser must be active **before** data is ingested: logs ingested before the parser is active are not normalized, and parsers do not re-process historical logs.

| Step | Component        | Path                                                 |
| ---- | ---------------- | ---------------------------------------------------- |
| 1    | Log type         | Google SecOps UI                                     |
| 2    | Parser           | [`siem/parser/`](./siem/parser/)                     |
| 3    | Ingestion script | [`siem/ingestion_script/`](./siem/ingestion_script/) |
| 4    | Dashboard        | [`siem/dashboard/`](./siem/dashboard/)               |
| 5    | Detection rule   | [`siem/rule/`](./siem/rule/)                         |

### 1. Create the Custom Log Type

1. In Google SecOps, go to **Settings > SIEM Settings > Available Log Types**.
2. Use **Search** to confirm that `CENSYS_SUPPLIER_RISK_CUSTOM` does not exist yet. If it exists, skip to the next step.
3. Click **Create Custom Log Type** and, under **Create a custom log type on your own**, enter:

   | Field              | Value                  |
   | ------------------ | ---------------------- |
   | **Vendor/Product** | `Censys Supplier Risk` |
   | **Log Type**       | `CENSYS_SUPPLIER_RISK` |

4. Click **Create Log Type**. Google SecOps appends the `_CUSTOM` suffix, so the log type is created as `CENSYS_SUPPLIER_RISK_CUSTOM`. Do not type the suffix yourself.
5. Wait about **10 minutes** before using the log type.

### 2. Create the Parser

The parser configuration is in [`siem/parser/`](./siem/parser/).

1. Go to **Settings > SIEM Settings > Parsers** and click **Create Parser**.
2. In the **Log Source** list, select `CENSYS_SUPPLIER_RISK_CUSTOM`, select **Start with Raw Logs Only**, and click **Create**.
3. Replace the contents of the **Parser Code Terminal** with the contents of the `.conf` file from [`siem/parser/`](./siem/parser/).
4. Click **Load** to load a raw log (or **Edit** and paste a sample Censys risk event), then click **Preview** and check the UDM output.
5. Click **Validate**, then **Submit**.
6. Wait about **20 minutes**. On the **Parsers** page, the parser should show as **Custom** and **Active**.

Key UDM mappings:

| Censys field                                           | UDM field                                                  |
| ------------------------------------------------------ | ---------------------------------------------------------- |
| `id`                                                   | `metadata.product_log_id`                                  |
| `occurred_at` / `inserted_at`                          | `metadata.event_timestamp` / `metadata.collected_timestamp` |
| `risk_instance.platform_url`                           | `metadata.url_back_to_product`                             |
| `risk_instance.host.ip` / `web.hostname`               | `target.ip` / `target.hostname`                            |
| `risk_instance.service.port` / `web.port`              | `target.port`                                              |
| `risk_instance.service.protocol` / `transport_protocol` | `network.application_protocol` / `network.ip_protocol`     |
| `risk_instance.id`                                     | `security_result.threat_id`                                |
| `risk_instance.risk_name` / `risk_type_id`             | `security_result.threat_name` / `security_result.rule_id`  |
| `risk_instance.severity`                               | `security_result.severity`                                 |
| `risk_instance.confidence`                             | `security_result.confidence` / `security_result.confidence_score` |
| `risk_instance.score`                                  | `security_result.risk_score`                               |
| `risk_instance.suppliers[]`                            | `security_result.associations` (id, name)                  |
| `change_type`, `status`, `asset_type`, `supply_chain_id`, `evidence`, `resolve_reason`, `rapid_response`, `remediations`, `tags` | `security_result.detection_fields` |

### 3. Deploy the Ingestion Script

[`siem/ingestion_script/`](./siem/ingestion_script/) contains:

- The Cloud Function source code ZIP (`censys_supplier_risk.zip`)
- `censys_deploy.sh`, which creates and configures all GCP resources

Run the deployment script in Google Cloud Shell:

1. Open the [Google Cloud Console](https://console.cloud.google.com) and click **Activate Cloud Shell**.
2. Upload `censys_deploy.sh` and the Cloud Function ZIP to Cloud Shell.
3. Make the script executable and run it:

   ```bash
   chmod +x censys_deploy.sh
   ./censys_deploy.sh
   ```

4. Answer the prompts:

   | Prompt                        | Required | Description                                                                                               |
   | ----------------------------- | -------- | --------------------------------------------------------------------------------------------------------- |
   | GCP Project ID                | Yes      | Project that hosts the Cloud Function, Cloud Scheduler, bucket and secrets                                |
   | GCP Region                    | No       | Region for the deployed resources (default `us-central1`)                                                 |
   | Path to the ZIP file          | Yes      | Local path of the Cloud Function ZIP                                                                      |
   | `CHRONICLE_CUSTOMER_ID`       | Yes      | Google SecOps customer ID                                                                                 |
   | `CHRONICLE_PROJECT_NUMBER`    | No       | Project number of the Google SecOps instance, if it differs from the deployment project                  |
   | `CHRONICLE_REGION`            | No       | Google SecOps region (default `us`)                                                                       |
   | `CHRONICLE_SERVICE_ACCOUNT`   | No       | Path to a service account JSON file; stored in Secret Manager. If omitted, the Cloud Function's default service account is used |
   | `CENSYS_ORGANIZATION_ID`      | Yes      | Censys Platform Organization ID (UUID)                                                                    |
   | `CENSYS_API_KEY`              | Yes      | Censys Personal Access Token; stored in Secret Manager                                                    |
   | `CENSYS_SUPPLIER_NAMES`       | No       | Pipe-separated (`\|`) supplier display names to ingest, e.g. `Supplier A\|Supplier B`                     |
   | `CENSYS_RISK_NAMES`           | No       | Pipe-separated (`\|`) risk display names to ingest                                                        |
   | `CENSYS_INSERTED_AFTER_TIME`  | No       | RFC3339 start point for the first run (default `1970-01-01T00:00:00Z`, full history)                      |
   | `CENSYS_SEVERITY`             | No       | Pipe-separated severities: `LOW\|MEDIUM\|HIGH\|CRITICAL`                                                  |
   | `CENSYS_CHANGE_TYPES`         | No       | Pipe-separated change types: `opened\|resolved\|reopened`                                                 |
   | `CENSYS_RAPID_RESPONSE`       | No       | `true` or `false`; omit to include both                                                                   |
   | CRON schedule                 | No       | Cloud Scheduler schedule (default `*/5 * * * *`)                                                          |

   Leave the optional filters blank to ingest all risk events.

5. The script enables the required APIs, grants IAM roles to the service account, creates the GCS bucket and the Secret Manager secrets, uploads the ZIP, deploys the Cloud Function (`censys-sr-secops-function`) and creates the Cloud Scheduler job (`censys-sr-secops-scheduler`).

To verify ingestion, run this UDM search in Google SecOps after the first scheduled run:

```text
metadata.log_type = "CENSYS_SUPPLIER_RISK_CUSTOM"
```

### 4. Import the Dashboard

1. In Google SecOps, go to **Dashboards & Reports > Dashboards**.
2. Click **New dashboard** > **Import from JSON**.
3. Upload [`Censys - Supplier Risk Overview.json`](./siem/dashboard/Censys%20-%20Supplier%20Risk%20Overview.json) and click **Import**.

| Panel                             | Description                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------- |
| Open Risk Count by Severity       | Risk instances currently open (latest event per risk instance), grouped by severity |
| Risk Events by Category           | Open risk events ranked by risk category                                            |
| Open vs. Closed Risks             | Open vs. closed risk events over the selected time range                            |
| Supplier Risk Ranking             | Suppliers ranked by open risk event count                                           |
| Top 20 Risks by Open Risk Count   | Risk types (e.g. CVE IDs) ranked by open risk event count                           |
| Rapid Response Events             | Events flagged for rapid response                                                   |

Filters: **Time**, **Severity**, **Risk Category**, **Status** and **Supplier**. "Currently open" counts depend on the time range: an instance is counted only if its latest event falls inside it, so use a long range (for example 90 days) for those panels.

### 5. Configure the Detection Rule

[`censys_sr_open_high_critical_risk.yaral`](./siem/rule/censys_sr_open_high_critical_risk.yaral) (**Censys SR - Open High/Critical Supplier Risk**) generates a detection when a supplier risk instance is opened or reopened with **HIGH** or **CRITICAL** severity. Events are grouped by risk instance ID over a 24-hour window, so each open risk produces at most one detection per day. The risk score is 90 for CRITICAL and 70 for HIGH.

1. In Google SecOps, go to **Detection > Rules & Detections > Rules Editor**.
2. Click **New**, paste the contents of the `.yaral` file, and click **Save New Rule**.
3. Turn on **Live Rule** and **Alerting** for the rule.

### Moving to the Published Parser

This version uses the custom log type `CENSYS_SUPPLIER_RISK_CUSTOM` and a custom parser. Once Google publishes the Censys parser, data is normalized under the prebuilt log type `CENSYS_SUPPLIER_RISK`. To move to it:

1. Change `GOOGLE_SECOPS_DATA_TYPE` in the ingestion script's `constant.py` to `"CENSYS_SUPPLIER_RISK"`, then rebuild and redeploy the Cloud Function.
2. Change `metadata.log_type = "CENSYS_SUPPLIER_RISK_CUSTOM"` to `"CENSYS_SUPPLIER_RISK"` in each dashboard panel query and in the detection rule.
3. Optionally, delete the custom parser once new events appear under `CENSYS_SUPPLIER_RISK`.

Events already ingested remain under `CENSYS_SUPPLIER_RISK_CUSTOM`. To cover both during the transition, match both log types in the dashboard and rule queries.

---

## References

- [Google SecOps SOAR Documentation](https://cloud.google.com/chronicle/docs/secops/google-secops-soar-toc)
- [Google SecOps Dashboards](https://cloud.google.com/chronicle/docs/soar/dashboards)
- [Censys User Guide (SOAR)](./docs/Censys%20-%20Google%20SecOps%20SOAR%20Integration%20-%20User%20Guide.pdf)
- [Create a custom log type](https://docs.cloud.google.com/chronicle/docs/event-processing/request-log-type#create_a_custom_log_type)
- [Configure custom parsers](https://docs.cloud.google.com/chronicle/docs/event-processing/configure-custom-parsers)
- [Google SecOps Ingestion API](https://cloud.google.com/chronicle/docs/reference/ingestion-api)
- [Censys Supply Chain Risk Events API](https://docs.censys.com/reference/v1-supply-chain-list-risk-events)

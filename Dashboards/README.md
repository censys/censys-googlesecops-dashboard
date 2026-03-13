# Censys SOAR Dashboard

This dashboard provides pre-built visualizations to help security teams monitor and measure the value delivered by Censys actions and playbooks in Google SecOps SOAR. These dashboards provide visibility into integration usage and playbook effectiveness.

---

## Import Censys Dashboards into Google SecOps

Complete the following steps to import the dashboard:

1. [Log in](https://cloud.google.com/chronicle/docs/log-in-to-ui) to your Google SecOps instance.

2. In the navigation bar, click **Dashboards & Reports > Dashboards**.

3. Click **New dashboard** and then select **Import from JSON**. The **Import dashboard** confirmation dialog appears.

4. Click the **Upload dashboard files** button. The **Select file** dialog appears. Select the dashboard JSON file: [Censys SOAR Dashboard.json](./Censys%20SOAR%20Dashboard.json)

5. The selected dashboard file will appear in the table. Click **Import** to complete the process.

The dashboard will be imported and available for use in your Google SecOps instance.

---

## Dashboard Filters

### Time Filter

The dashboard includes a time filter that allows you to control the time range for all panels.

**Description:** This filter updates all dashboard panels based on the selected time range, showing only actions and playbooks executed during that period.

**Default:** Last 7 days

---

## Available Dashboard Panels

The Censys SOAR Dashboard includes the following panels to provide comprehensive visibility into your Censys integration usage:

### **Total Playbook Runs**

**Description:** Displays the total count of unique successful playbook executions that included Censys Actions.

**Metric Type:** Counter

**Use Case:** Track the overall adoption and usage of Censys-powered automation workflows within your SOC. This metric helps measure the integration's impact on automated incident response.

**Note:** Re-run playbook executions will not be counted in this panel to ensure accurate unique execution counts.

---

### **Total Action Runs**

**Description:** Shows the total count of Censys Actions executed via playbooks only. Manual action executions are not included in this metric.

**Metric Type:** Counter

**Use Case:** Monitor the volume of automated Censys enrichment and investigation actions performed by playbooks. This helps quantify the automation value delivered by the integration.

**Note:** This panel specifically tracks automated action runs within playbook executions. Manual action invocations from cases are excluded from this count to focus on automation metrics.

---

### **Playbook Distribution**

**Description:** A pie chart visualization showing the distribution of different playbooks utilizing the Censys Integration.

**Visualization:** Pie Chart

**Use Case:** Understand which Censys playbooks are most frequently used in your environment. This helps identify the most valuable automation workflows and can guide decisions on which playbooks to optimize or expand.

**Insights:**
- Identify the most popular Censys playbooks in your SOC
- Understand which use cases (enrichment, rescan, history, infrastructure discovery) are most valuable
- Guide resource allocation and playbook optimization efforts

---

### **Most Popular Actions & Playbooks**

**Description:** A table listing which Censys integration actions are used most frequently and in which specific SOC playbooks.

**Visualization:** Table

**Table Columns:**
- **Action Name:** Name of the Censys action (e.g., Enrich IPs, Get Host History, Get Related Infrastructure)
- **Playbook Name:** Name of the playbook(s) using this action
- **Total Action Executions:** Number of times the action has been executed

**Use Case:** Gain detailed insights into action-level usage patterns and understand which Censys capabilities are most valuable to your security operations.

**Insights:**
- Identify the most frequently used Censys actions
- Understand which playbooks leverage specific Censys capabilities
- Optimize playbook design based on action usage patterns
- Measure the value of specific Censys features (enrichment vs. historical analysis vs. infrastructure discovery)

---

## References

- [Google SecOps Dashboards Documentation](https://cloud.google.com/chronicle/docs/soar/dashboards)
- [Censys Playbooks Documentation](../Playbooks/README.md)

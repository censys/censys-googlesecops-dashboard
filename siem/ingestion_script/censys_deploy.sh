#!/usr/bin/env bash
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Interactive deployment script for the Censys Supplier Risk
# Google SecOps SIEM connector.
#
# Usage: bash censys_deploy.sh

set -euo pipefail

# --- Configuration Variables ---
PROJECT_ID=""
REGION=""
GCS_BUCKET_NAME="censys-sr-bucket"
LOCAL_ZIP_PATH=""
CF_ZIP_FILE="censys_sr_function.zip"
CF_NAME="censys-sr-secops-function"
SCHEDULER_NAME="censys-sr-secops-scheduler"
PROJECT_NUMBER=""
DEFAULT_SA_EMAIL=""
CRON_TIME="*/5 * * * *"   # Every 5 minutes (steady-state polling)
TIMEOUT_SECONDS="3600s"     # 60 minutes

# --- Cloud Function Environment Variables ---
CHRONICLE_CUSTOMER_ID=""
CHRONICLE_SERVICE_ACCOUNT=""
CHRONICLE_REGION="us"
CHRONICLE_PROJECT_NUMBER=""
CENSYS_API_KEY_VALUE=""
CENSYS_API_KEY_SECRET_ID=""
CHRONICLE_SERVICE_ACCOUNT_SECRET_ID=""
CENSYS_ORGANIZATION_ID=""
CENSYS_SUPPLIER_NAMES=""
CENSYS_RISK_NAMES=""
CENSYS_INSERTED_AFTER_TIME="1970-01-01T00:00:00Z"
CENSYS_SEVERITY=""
CENSYS_CHANGE_TYPES=""
CENSYS_RAPID_RESPONSE=""

print_message() {
    local color="$1"
    local message="$2"
    case "$color" in
        "green")  echo -e "\033[32m${message}\033[0m" ;;
        "red")    echo -e "\033[31m${message}\033[0m" >&2 ;;
        "yellow") echo -e "\033[33m${message}\033[0m" ;;
        *)        echo "${message}" ;;
    esac
}

check_error() {
    local exit_code=$?
    local step_name="$1"
    if [ $exit_code -ne 0 ]; then
        print_message "red" "\nERROR: Step '$step_name' failed with exit code $exit_code."
        print_message "red" "Exiting script due to error."
        exit $exit_code
    else
        print_message "green" "SUCCESS: Step '$step_name' completed."
    fi
}

escape_yaml_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    echo "$value"
}

# Validates that every pipe-separated ('|') token in $2 is a member of the
# space-separated allowed-values list in $3 (case-insensitive; blank values
# are permitted, since these are all optional filters). Exits with a clear
# error naming the offending env var, the invalid token, and the allowed
# list if validation fails — consistent with how required-field checks
# elsewhere in this script fail fast rather than re-prompting.
validate_enum_psv() {
    local var_name="$1"
    local value="$2"
    local allowed="$3"

    [[ -z "$value" ]] && return 0

    local raw_token token allowed_value match
    IFS='|' read -ra tokens <<< "$value"
    for raw_token in "${tokens[@]}"; do
        token="$(echo "$raw_token" | xargs)"
        [[ -z "$token" ]] && continue
        match="false"
        for allowed_value in $allowed; do
            if [[ "${token,,}" == "${allowed_value,,}" ]]; then
                match="true"
                break
            fi
        done
        if [[ "$match" == "false" ]]; then
            print_message "red" "ERROR: $var_name contains invalid value '$token'. Allowed values: ${allowed// /, }."
            exit 1
        fi
    done
}

# Validates that $2 is an RFC3339 timestamp with an explicit 'Z' or
# timezone offset suffix (e.g. 1970-01-01T00:00:00Z). Mirrors the runtime
# check in utility.validate_rfc3339_env — failing fast here at deploy time
# instead of only discovering a malformed value on the Cloud Function's
# first invocation.
validate_rfc3339() {
    local var_name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|z|[+-][0-9]{2}:[0-9]{2})$ ]]; then
        print_message "red" "ERROR: $var_name must be an RFC3339 timestamp with an explicit 'Z' or timezone offset, e.g. 1970-01-01T00:00:00Z. Got: '$value'."
        exit 1
    fi
}

# Trims each pipe-separated ('|') token in $1 (dropping any that end up
# empty, e.g. from a stray double-pipe or trailing pipe) and rejoins with
# "|". Whitespace within a token (e.g. a two-word name) is left untouched
# — only the leading/trailing whitespace around each token is normalized.
# `read -r` already trims the overall line, but whitespace around internal
# pipes (e.g. "A   |   B") is otherwise left as typed.
#
# Pipe, not comma, is the delimiter: a comma inside an env var's value
# breaks manual deployment via `gcloud ... --set-env-vars`, which itself
# uses comma to separate different KEY=VALUE pairs.
# Example: " Trushit Vyas     |      Swetal Patel " -> "Trushit Vyas|Swetal Patel"
trim_and_normalize_psv() {
    local value="$1"
    local raw_token token result=""

    IFS='|' read -ra tokens <<< "$value"
    for raw_token in "${tokens[@]}"; do
        token="$(echo "$raw_token" | xargs)"
        [[ -z "$token" ]] && continue
        if [[ -z "$result" ]]; then
            result="$token"
        else
            result="$result|$token"
        fi
    done

    echo "$result"
}

prompt_for_input() {
    print_message "yellow" "--- GCP Deployment Configuration ---"

    read -r -p "Enter your GCP Project ID (e.g., my-project-12345) (Required): " PROJECT_ID
    [[ -z "$PROJECT_ID" ]] && { print_message "red" "ERROR: Project ID cannot be empty."; exit 1; }

    local default_region="us-central1"
    read -r -p "Enter your GCP Region [default: $default_region]: " temp_var
    REGION=${temp_var:-$default_region}

    print_message "yellow" "NOTE: You MUST first create the Cloud Function zip and upload it to GCS."
    read -r -p "Enter local full path to the zip file: " LOCAL_ZIP_PATH
    [[ -z "$LOCAL_ZIP_PATH" ]] && { print_message "red" "ERROR: Local ZIP Path cannot be empty."; exit 1; }
    [[ ! -f "$LOCAL_ZIP_PATH" ]] && { print_message "red" "ERROR: File not found at $LOCAL_ZIP_PATH."; exit 1; }

    print_message "yellow" "\n--- Chronicle / Google SecOps Configuration ---"
    read -r -p "Enter CHRONICLE_CUSTOMER_ID (Required): " CHRONICLE_CUSTOMER_ID
    [[ -z "$CHRONICLE_CUSTOMER_ID" ]] && { print_message "red" "ERROR: Chronicle Customer ID cannot be empty."; exit 1; }

    print_message "yellow" "IMPORTANT: If the GCP project hosting Cloud Scheduler differs from the Google SecOps project, provide the Chronicle Project Number."
    read -r -p "Enter CHRONICLE_PROJECT_NUMBER (Optional, press Enter to use current project number): " CHRONICLE_PROJECT_NUMBER

    local default_chronicle_region="us"
    read -r -p "Enter CHRONICLE_REGION [default: $default_chronicle_region]: " temp_var
    CHRONICLE_REGION=${temp_var:-$default_chronicle_region}

    read -r -p "Enter path to CHRONICLE_SERVICE_ACCOUNT JSON file (Optional — stored in Secret Manager if provided): " CHRONICLE_SA_PATH
    if [[ -n "$CHRONICLE_SA_PATH" ]]; then
        [[ ! -f "$CHRONICLE_SA_PATH" ]] && { print_message "red" "ERROR: Service account JSON file not found at $CHRONICLE_SA_PATH."; exit 1; }
        CHRONICLE_SERVICE_ACCOUNT=$(<"$CHRONICLE_SA_PATH")
    fi

    print_message "yellow" "\n--- Censys Supplier Risk Configuration ---"
    read -r -p "Enter CENSYS_ORGANIZATION_ID (UUID, Required): " CENSYS_ORGANIZATION_ID
    [[ -z "$CENSYS_ORGANIZATION_ID" ]] && { print_message "red" "ERROR: CENSYS_ORGANIZATION_ID cannot be empty."; exit 1; }

    read -r -p "Enter CENSYS_API_KEY value (Required — stored in Secret Manager): " CENSYS_API_KEY_VALUE
    [[ -z "$CENSYS_API_KEY_VALUE" ]] && { print_message "red" "ERROR: CENSYS_API_KEY cannot be empty."; exit 1; }

    read -r -p "Enter CENSYS_SUPPLIER_NAMES (Optional, pipe-separated '|' display names, e.g. 'Supplier A|Supplier B', resolved via GET /v1/supplychains/default/suppliers): " CENSYS_SUPPLIER_NAMES
    CENSYS_SUPPLIER_NAMES=$(trim_and_normalize_psv "$CENSYS_SUPPLIER_NAMES")

    read -r -p "Enter CENSYS_RISK_NAMES (Optional, pipe-separated '|' risk display names, e.g. 'Exposed SMTP Service|Weak TLS Cipher', resolved via GET /v1/supplychains/default/risks): " CENSYS_RISK_NAMES
    CENSYS_RISK_NAMES=$(trim_and_normalize_psv "$CENSYS_RISK_NAMES")

    local default_inserted_after_time="1970-01-01T00:00:00Z"
    read -r -p "Enter CENSYS_INSERTED_AFTER_TIME — first-run watermark seed, RFC3339 (e.g. 1970-01-01T00:00:00Z for full history) [default: $default_inserted_after_time]: " temp_var
    CENSYS_INSERTED_AFTER_TIME=${temp_var:-$default_inserted_after_time}
    validate_rfc3339 "CENSYS_INSERTED_AFTER_TIME" "$CENSYS_INSERTED_AFTER_TIME"

    print_message "yellow" "\n--- Optional risk-events filters (leave blank for 'include everything') ---"
    read -r -p "Enter CENSYS_SEVERITY (Optional, pipe-separated '|': LOW|MEDIUM|HIGH|CRITICAL): " CENSYS_SEVERITY
    CENSYS_SEVERITY=$(trim_and_normalize_psv "$CENSYS_SEVERITY")
    validate_enum_psv "CENSYS_SEVERITY" "$CENSYS_SEVERITY" "LOW MEDIUM HIGH CRITICAL"

    read -r -p "Enter CENSYS_CHANGE_TYPES (Optional, pipe-separated '|': opened|resolved|reopened): " CENSYS_CHANGE_TYPES
    CENSYS_CHANGE_TYPES=$(trim_and_normalize_psv "$CENSYS_CHANGE_TYPES")
    validate_enum_psv "CENSYS_CHANGE_TYPES" "$CENSYS_CHANGE_TYPES" "opened resolved reopened"

    read -r -p "Enter CENSYS_RAPID_RESPONSE (Optional, true or false — omit for both): " CENSYS_RAPID_RESPONSE
    CENSYS_RAPID_RESPONSE=$(trim_and_normalize_psv "$CENSYS_RAPID_RESPONSE")
    validate_enum_psv "CENSYS_RAPID_RESPONSE" "$CENSYS_RAPID_RESPONSE" "true false"

    local default_schedule="*/5 * * * *"
    read -r -p "Enter CRON Schedule [default: $default_schedule]: " temp_var
    CRON_TIME=${temp_var:-$default_schedule}

    print_message "green" "Configuration collected."
}

enable_apis() {
    print_message "yellow" "\n--- Enabling Required GCP APIs ---"
    local APIS=(
        cloudfunctions.googleapis.com
        run.googleapis.com
        cloudbuild.googleapis.com
        artifactregistry.googleapis.com
        logging.googleapis.com
        cloudscheduler.googleapis.com
        pubsub.googleapis.com
        storage-component.googleapis.com
        secretmanager.googleapis.com
        chronicle.googleapis.com
        cloudresourcemanager.googleapis.com
    )
    for api in "${APIS[@]}"; do
        if ! gcloud services list --project="$PROJECT_ID" --filter="NAME:$api" --format="value(NAME)" | grep -q "$api"; then
            print_message "yellow" "Enabling $api..."
            gcloud services enable "$api" --project="$PROJECT_ID"
            check_error "Enabling API $api"
        else
            print_message "green" "$api is already enabled."
        fi
    done
}

configure_default_service_account() {
    print_message "yellow" "\n--- Configuring Permissions for Default Compute Engine Service Account ---"
    PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
    if [[ -n "$CHRONICLE_PROJECT_NUMBER" ]]; then
        print_message "yellow" "Using provided Chronicle Project Number: $CHRONICLE_PROJECT_NUMBER"
    else
        CHRONICLE_PROJECT_NUMBER=$PROJECT_NUMBER
        print_message "yellow" "Using current Project Number as Chronicle Project Number: $CHRONICLE_PROJECT_NUMBER"
    fi
    check_error "Fetching Project Number"
    DEFAULT_SA_EMAIL="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
    print_message "yellow" "Target Service Account: $DEFAULT_SA_EMAIL"

    local ROLES=(
        "roles/chronicle.editor"
        "roles/cloudscheduler.jobRunner"
        "roles/secretmanager.admin"
        "roles/storage.admin"
        "roles/run.invoker"
        "roles/cloudbuild.builds.builder"
    )
    for ROLE in "${ROLES[@]}"; do
        print_message "yellow" "Ensuring role $ROLE on $DEFAULT_SA_EMAIL..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$DEFAULT_SA_EMAIL" \
            --role="$ROLE" \
            --condition=None --no-user-output-enabled
        echo "Attempted to add $ROLE."
    done
    print_message "green" "IAM role binding attempts complete. Verify in IAM console if needed."
}

# Adds a new version to a Secret Manager secret only if its value differs
# from the current latest version (or no version exists yet). Secret
# Manager versions are immutable and append-only, so calling
# `gcloud secrets versions add` unconditionally on every deploy run creates
# a brand-new version each time even when the value hasn't changed at all —
# this guards against that by diffing first.
# Args: $1 = secret name, $2 = value to store.
# Sets SECRET_VERSION_ID to the resulting (or existing) version's resource name.
add_secret_version_if_changed() {
    local secret_name="$1"
    local new_value="$2"
    local current_value=""
    local has_existing_version="false"

    if current_value=$(gcloud secrets versions access latest --secret="$secret_name" --project="$PROJECT_ID" 2>/dev/null); then
        has_existing_version="true"
    fi

    if [[ "$has_existing_version" == "true" && "$current_value" == "$new_value" ]]; then
        print_message "green" "Secret $secret_name value unchanged — skipping new version."
    else
        print_message "yellow" "Adding new version to Secret $secret_name..."
        echo -n "$new_value" | gcloud secrets versions add "$secret_name" \
            --data-file=- \
            --project="$PROJECT_ID"
        check_error "Adding new version to Secret $secret_name"
    fi

    SECRET_VERSION_ID=$(gcloud secrets versions describe "latest" \
        --secret="$secret_name" \
        --project="$PROJECT_ID" \
        --format='value(name)')
    check_error "Fetching latest version ID for Secret $secret_name"
}

create_secrets() {
    print_message "yellow" "\n--- Managing Censys Secrets in Secret Manager ---"

    local API_KEY_SECRET_NAME="censys-api-key"
    if ! gcloud secrets describe "$API_KEY_SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
        print_message "yellow" "Creating secret $API_KEY_SECRET_NAME..."
        gcloud secrets create "$API_KEY_SECRET_NAME" \
            --replication-policy="automatic" \
            --project="$PROJECT_ID"
        check_error "Creating Secret $API_KEY_SECRET_NAME"
    else
        print_message "green" "Secret $API_KEY_SECRET_NAME already exists."
    fi

    add_secret_version_if_changed "$API_KEY_SECRET_NAME" "$CENSYS_API_KEY_VALUE"
    CENSYS_API_KEY_SECRET_ID="$SECRET_VERSION_ID"

    if [[ ! "$CENSYS_API_KEY_SECRET_ID" =~ ^projects/.*/secrets/.*/versions/.* ]]; then
        print_message "red" "ERROR: Could not retrieve a valid Access Token Secret Resource ID. Got: $CENSYS_API_KEY_SECRET_ID"
        exit 1
    fi
    print_message "green" "CENSYS_API_KEY Secret ID: $CENSYS_API_KEY_SECRET_ID"

    if [[ -n "$CHRONICLE_SERVICE_ACCOUNT" ]]; then
        local CHRONICLE_SA_SECRET_NAME="chronicle-service-account"
        if ! gcloud secrets describe "$CHRONICLE_SA_SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
            print_message "yellow" "Creating secret $CHRONICLE_SA_SECRET_NAME..."
            gcloud secrets create "$CHRONICLE_SA_SECRET_NAME" \
                --replication-policy="automatic" \
                --project="$PROJECT_ID"
            check_error "Creating Secret $CHRONICLE_SA_SECRET_NAME"
        else
            print_message "green" "Secret $CHRONICLE_SA_SECRET_NAME already exists."
        fi

        add_secret_version_if_changed "$CHRONICLE_SA_SECRET_NAME" "$CHRONICLE_SERVICE_ACCOUNT"
        CHRONICLE_SERVICE_ACCOUNT_SECRET_ID="$SECRET_VERSION_ID"

        if [[ ! "$CHRONICLE_SERVICE_ACCOUNT_SECRET_ID" =~ ^projects/.*/secrets/.*/versions/.* ]]; then
            print_message "red" "ERROR: Could not retrieve a valid Chronicle SA Secret Resource ID."
            exit 1
        fi
        print_message "green" "CHRONICLE_SERVICE_ACCOUNT Secret ID: $CHRONICLE_SERVICE_ACCOUNT_SECRET_ID"
    fi
}

create_bucket() {
    GCS_BUCKET_NAME="${GCS_BUCKET_NAME}-${PROJECT_ID}"
    print_message "yellow" "\n--- Managing GCS Bucket ($GCS_BUCKET_NAME) ---"
    if ! gcloud storage buckets describe "gs://$GCS_BUCKET_NAME" --project="$PROJECT_ID" &>/dev/null; then
        print_message "yellow" "Creating GCS bucket gs://$GCS_BUCKET_NAME in $REGION..."
        gcloud storage buckets create "gs://$GCS_BUCKET_NAME" --project="$PROJECT_ID" --location="$REGION"
        check_error "Creating GCS bucket gs://$GCS_BUCKET_NAME"
    else
        print_message "green" "Bucket gs://$GCS_BUCKET_NAME already exists."
    fi
}

upload_cf_zip() {
    print_message "yellow" "\n--- Uploading Cloud Function ZIP file ---"
    local GCS_URI="gs://$GCS_BUCKET_NAME/$CF_ZIP_FILE"
    print_message "yellow" "Uploading $LOCAL_ZIP_PATH to $GCS_URI"
    gcloud storage cp "$LOCAL_ZIP_PATH" "$GCS_URI"
    check_error "Uploading $LOCAL_ZIP_PATH to $GCS_URI"
}

deploy_cloud_function() {
    print_message "yellow" "\n--- Deploying Cloud Function ($CF_NAME) ---"

    local ENV_VARS_FILE=".env_vars_temp.yaml"
    local ESC_CHRONICLE_CUSTOMER_ID
    ESC_CHRONICLE_CUSTOMER_ID=$(escape_yaml_value "${CHRONICLE_CUSTOMER_ID}")
    local ESC_CHRONICLE_PROJECT_NUMBER
    ESC_CHRONICLE_PROJECT_NUMBER=$(escape_yaml_value "${CHRONICLE_PROJECT_NUMBER}")
    local ESC_CHRONICLE_REGION
    ESC_CHRONICLE_REGION=$(escape_yaml_value "${CHRONICLE_REGION}")
    local ESC_GCS_BUCKET_NAME
    ESC_GCS_BUCKET_NAME=$(escape_yaml_value "${GCS_BUCKET_NAME}")
    local ESC_CENSYS_API_KEY_SECRET_ID
    ESC_CENSYS_API_KEY_SECRET_ID=$(escape_yaml_value "${CENSYS_API_KEY_SECRET_ID}")
    local ESC_CENSYS_ORGANIZATION_ID
    ESC_CENSYS_ORGANIZATION_ID=$(escape_yaml_value "${CENSYS_ORGANIZATION_ID}")
    local ESC_CENSYS_INSERTED_AFTER_TIME
    ESC_CENSYS_INSERTED_AFTER_TIME=$(escape_yaml_value "${CENSYS_INSERTED_AFTER_TIME}")

    cat > "$ENV_VARS_FILE" <<EOF
CHRONICLE_CUSTOMER_ID: "${ESC_CHRONICLE_CUSTOMER_ID}"
CHRONICLE_PROJECT_NUMBER: "${ESC_CHRONICLE_PROJECT_NUMBER}"
CHRONICLE_REGION: "${ESC_CHRONICLE_REGION}"
GCP_BUCKET_NAME: "${ESC_GCS_BUCKET_NAME}"
CENSYS_API_KEY: "${ESC_CENSYS_API_KEY_SECRET_ID}"
CENSYS_ORGANIZATION_ID: "${ESC_CENSYS_ORGANIZATION_ID}"
CENSYS_INSERTED_AFTER_TIME: "${ESC_CENSYS_INSERTED_AFTER_TIME}"
EOF

    if [[ -n "$CHRONICLE_SERVICE_ACCOUNT_SECRET_ID" ]]; then
        local ESC_SA
        ESC_SA=$(escape_yaml_value "${CHRONICLE_SERVICE_ACCOUNT_SECRET_ID}")
        echo "CHRONICLE_SERVICE_ACCOUNT: \"${ESC_SA}\"" >> "$ENV_VARS_FILE"
    fi

    if [[ -n "$CENSYS_SUPPLIER_NAMES" ]]; then
        local ESC_NAMES
        ESC_NAMES=$(escape_yaml_value "${CENSYS_SUPPLIER_NAMES}")
        echo "CENSYS_SUPPLIER_NAMES: \"${ESC_NAMES}\"" >> "$ENV_VARS_FILE"
    fi

    if [[ -n "$CENSYS_RISK_NAMES" ]]; then
        local ESC_RISK_NAMES
        ESC_RISK_NAMES=$(escape_yaml_value "${CENSYS_RISK_NAMES}")
        echo "CENSYS_RISK_NAMES: \"${ESC_RISK_NAMES}\"" >> "$ENV_VARS_FILE"
    fi

    # Optional risk-events filters — only written when the operator set them,
    # so an unset filter is omitted from the request entirely (never sent
    # empty) rather than being pinned to a blank value.
    if [[ -n "$CENSYS_SEVERITY" ]]; then
        local ESC_SEVERITY
        ESC_SEVERITY=$(escape_yaml_value "${CENSYS_SEVERITY}")
        echo "CENSYS_SEVERITY: \"${ESC_SEVERITY}\"" >> "$ENV_VARS_FILE"
    fi

    if [[ -n "$CENSYS_CHANGE_TYPES" ]]; then
        local ESC_CHANGE_TYPES
        ESC_CHANGE_TYPES=$(escape_yaml_value "${CENSYS_CHANGE_TYPES}")
        echo "CENSYS_CHANGE_TYPES: \"${ESC_CHANGE_TYPES}\"" >> "$ENV_VARS_FILE"
    fi

    if [[ -n "$CENSYS_RAPID_RESPONSE" ]]; then
        local ESC_RAPID_RESPONSE
        ESC_RAPID_RESPONSE=$(escape_yaml_value "${CENSYS_RAPID_RESPONSE}")
        echo "CENSYS_RAPID_RESPONSE: \"${ESC_RAPID_RESPONSE}\"" >> "$ENV_VARS_FILE"
    fi

    local GCS_SOURCE="gs://$GCS_BUCKET_NAME/$CF_ZIP_FILE"

    print_message "yellow" "Using env vars file: $ENV_VARS_FILE"
    print_message "yellow" "Using Source: $GCS_SOURCE"
    print_message "yellow" "Using Service Account: $DEFAULT_SA_EMAIL"

    gcloud functions deploy "$CF_NAME" \
        --env-vars-file="$ENV_VARS_FILE" \
        --gen2 \
        --runtime python312 \
        --region="$REGION" \
        --source="$GCS_SOURCE" \
        --entry-point=main \
        --service-account="$DEFAULT_SA_EMAIL" \
        --trigger-http \
        --no-allow-unauthenticated \
        --memory=8GiB \
        --timeout="$TIMEOUT_SECONDS"
    local deploy_exit_code=$?

    rm -f "$ENV_VARS_FILE"

    if [ $deploy_exit_code -ne 0 ]; then
        print_message "red" "\nERROR: Deploying Cloud Function $CF_NAME failed."
        exit $deploy_exit_code
    else
        print_message "green" "SUCCESS: Cloud Function $CF_NAME deployed."
    fi
}

configure_scheduler() {
    print_message "yellow" "\n--- Configuring Cloud Scheduler ($SCHEDULER_NAME) ---"
    local CLOUD_FUNCTION_URL
    CLOUD_FUNCTION_URL=$(gcloud functions describe "$CF_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(serviceConfig.uri)" 2>/dev/null || \
        echo "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${CF_NAME}")
    print_message "yellow" "Cloud Function URL: $CLOUD_FUNCTION_URL"
    print_message "yellow" "Schedule: $CRON_TIME (Timeout: $TIMEOUT_SECONDS)"

    if gcloud scheduler jobs describe "$SCHEDULER_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        print_message "yellow" "Scheduler job $SCHEDULER_NAME already exists. Deleting to recreate..."
        gcloud scheduler jobs delete "$SCHEDULER_NAME" --location="$REGION" --project="$PROJECT_ID" --quiet
        check_error "Deleting existing Scheduler job $SCHEDULER_NAME"
    fi

    print_message "yellow" "Creating Scheduler job $SCHEDULER_NAME..."
    gcloud scheduler jobs create http "$SCHEDULER_NAME" \
        --schedule="$CRON_TIME" \
        --uri="$CLOUD_FUNCTION_URL" \
        --http-method=POST \
        --attempt-deadline=1m \
        --oidc-service-account-email="$DEFAULT_SA_EMAIL" \
        --location="$REGION" \
        --time-zone=UTC \
        --project="$PROJECT_ID"
    check_error "Creating Cloud Scheduler job $SCHEDULER_NAME"
}

main() {
    print_message "green" "Starting GCP Deployment Script for Censys Supplier Risk..."
    prompt_for_input

    print_message "yellow" "\n--- Setting gcloud Configuration ---"
    gcloud config set project "$PROJECT_ID"
    check_error "Setting gcloud project to $PROJECT_ID"

    enable_apis
    configure_default_service_account
    create_bucket
    create_secrets
    upload_cf_zip
    deploy_cloud_function
    configure_scheduler

    print_message "green" "\n--- Deployment Complete ---"
    print_message "green" "All components deployed and configured."
    print_message "yellow" "Next Steps:"
    print_message "yellow" "1. Verify Cloud Function logs for any errors."
    print_message "yellow" "2. Check Cloud Scheduler job for successful runs."
    print_message "yellow" "3. Monitor Censys SR risk event ingestion in Google SecOps."
    print_message "yellow" "4. To force a resync/backfill, manually clear the 'risk_events_inserted_after_time'"
    print_message "yellow" "   and 'risk_events_inserted_after_event_id' keys from the GCS checkpoint"
    print_message "yellow" "   file (censys_checkpoint.json) — the next run re-seeds from CENSYS_INSERTED_AFTER_TIME."
}

main

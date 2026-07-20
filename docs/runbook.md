# Runbook

## Prerequisites
- Terraform >= 1.6
- AWS CLI configured with credentials for the target account (`aws sts get-caller-identity`)
- An AWS region (default eu-west-2; see `terraform/environments/*/terraform.tfvars`)
- The Logi-Track app is deployed from source by user-data (no Docker build needed);
  Docker is only needed if you want to run Wazuh locally.

## 1. Bootstrap remote state + pipeline OIDC (one time)
```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # already provided; edit if the bucket name collides
terraform init
terraform apply
```
This creates the S3 state bucket + DynamoDB lock table. Leave `create_pipeline_oidc = false`
for now. Once the GitHub repo exists, set `create_pipeline_oidc = true` and
`github_repo = "owner/repo"`, re-apply, then set the repo secret `AWS_PIPELINE_ROLE_ARN`
to the `pipeline_role_arn` output.

## 2. Provision Environment A (first proving apply, local state)
The first apply can run on **local state** (backend.tf stays commented). `terraform.tfvars`
is already provided.
```bash
cd terraform/environments/environment-a
terraform init
terraform plan      # review: VPC, ALB, ASG, RDS, S3 app-artifact bucket, IAM, etc.
terraform apply
terraform output    # note app_url (the ALB DNS)
```
To switch to remote state instead: apply `terraform/bootstrap`, uncomment `backend.tf`
(the bucket name is already aligned), then `terraform init -migrate-state`.

### Verify the app actually booted
Give the instance a few minutes after apply, then:
```bash
# 1. Browse the app
curl -I "http://$(terraform output -raw app_url)/"      # expect HTTP 200

# 2. Read the bootstrap log via SSM (no SSH needed)
INSTANCE_ID=$(aws ec2 describe-instances --region eu-west-2 \
  --filters "Name=tag:Name,Values=env-a-app" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2
#   then, on the instance:
#     sudo tail -n 100 /var/log/logitrack-bootstrap.log   # ends with "[bootstrap] complete"
#     systemctl status logitrack-web logitrack-worker redis6
```
If the ALB target is unhealthy, the usual causes are: migrations failing (RDS not
reachable / creds), `collectstatic` erroring, or `ALLOWED_HOSTS` missing the health-check
host — all visible in the bootstrap log and `journalctl -u logitrack-web`.

## 2b. Provision Environment B
Same as above from `terraform/environments/environment-b` (uses `env-b` tfvars).

## 3. Run the attack pipeline
Trigger the `attack-pipeline` workflow (`workflow_dispatch`, pick `environment-a` or
`environment-b`) or push to `main`. Requires the repo secret `AWS_PIPELINE_ROLE_ARN`
(role assumed via GitHub OIDC). Stages run in order:
Terraform → Trivy → Prowler → Nuclei → Stratus Red Team → CDI.
The Prowler stage records **CBCS_baseline**; the CDI stage injects the Table 3.3 drift
scenarios, re-scans for **CBCS_current**, computes **CDI**, then reverts the drift.

## 4. Collect metrics
CBCS and CDI are produced by the pipeline (artefacts `cbcs-baseline-*`, `cdi-*`). To compute
locally from a Prowler CIS compliance report:
```bash
cd metrics
pip install -r requirements.txt
python compute_metrics.py cbcs --input 'path/to/*cis_3.0_aws_foundations*.csv' \
  --output data/cbcs_baseline_environment-b.json
python compute_metrics.py cdi --baseline data/cbcs_baseline_environment-b.json \
  --current data/cbcs_current_environment-b.json
```
Drift scenarios (Table 3.3) live in `drift/drift_scenarios.yaml`; apply/revert with
`python drift/run_drift.py --apply|--revert --env B`.

## 5. Tear down (cost control)
```bash
cd terraform/environments/environment-a
terraform destroy
```

## Logi-Track deployment notes

The real Logi-Track Django app (`app/logi-track/`) is deployed by the compute module's
user-data, not the placeholder `http.server`. Both environments run an identical app
topology (controlled variable): **Gunicorn + Celery + local Redis under systemd**.

**How it is delivered.** Terraform packages `app/logi-track/` into a zip
(`modules/app_artifact`) and uploads it to a private, encrypted S3 bucket per environment.
Each instance pulls and unpacks it at boot — Env B via the S3 VPC endpoint + a scoped
`s3:GetObject` on the artifact bucket; Env A via its broad baseline role.

**Boot sequence (`user_data.sh.tftpl`).** Install `python3.12` + `redis6`; start Redis;
resolve credentials (Env B: one JSON secret from Secrets Manager; Env A: plaintext from
Terraform); write `/etc/logitrack/app.env`; create a venv and `pip install` the pinned
`requirements.txt`; `collectstatic` + `migrate` against RDS Postgres; start
`logitrack-web` (Gunicorn) and `logitrack-worker` (Celery) services.

**Configuration wired via env vars** (read by `mylogistics/settings.py`): `SECRET_KEY`
(generated fresh), `DEBUG=False` (selects the Postgres backend), `ALLOWED_HOSTS`
(ALB DNS + instance private IP + localhost), `CSRF_TRUSTED_ORIGINS` (`http://<alb-dns>`),
`DB_*` (from RDS), `CELERY_BROKER_URL`/`CELERY_RESULT_BACKEND` (`redis://localhost:6379/0`).

**Zero Trust vs baseline secret handling.** In Env B the DB creds, `SECRET_KEY` and email
fields live in one Secrets Manager secret (CMK-encrypted) fetched at boot. In Env A the
same values are injected as plaintext user-data — an intentional baseline weakness.

**Security-header baseline (finding, not a bug we fix).** The app ships with HSTS and
secure cookies **disabled** (`settings.py` lines 141–147: `SECURE_HSTS_SECONDS=0`,
`SESSION_COOKIE_SECURE=False`, `CSRF_COOKIE_SECURE=False`). This is the SME insecure-by-
default posture and is treated as a result. **The baseline missing-header state therefore
comes from the app config itself, independent of drift scenario D7** — D7 only injects an
*additional* header-removal marker for the Nuclei channel; it is not the source of the
baseline finding.

**Known non-fatal items.** Email is disabled (SMTP backend hardcoded, creds left blank);
the contact-form path calls `send_async_email.delay()`, so that Celery task will fail
asynchronously if the form is ever submitted — it does not affect boot or browsing.
`virtual_scanner.py` is copied to `/opt/logitrack/app` but not run as a service (interactive
CLI; its `API_URL` tuple/IP is a separate known issue). The ALB target-group health check
targets `/` (the app has no `/health` route).

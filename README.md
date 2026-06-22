# mini-SOAR

Mini-SOAR is a small security orchestration, automation, and response project built around a Flask API that analyzes Wazuh alerts, decides a remediation action, and generates a Markdown incident report.

This repository contains several directories, including:

- `mini-soar/claude-agent` — the core Flask SOAR agent and Docker deployment.
- `custom-integrations/` — integration helpers for a custom n8n workflow.
- `custom-n8n/` — custom n8n node or integration files.
- `wazuh-n8n-lab/` — Wazuh and n8n lab environment files and Docker configuration.

> If you only want the SOAR agent itself, the main service is in `mini-soar/claude-agent`.

## Features

- HTTP endpoints for health checks and alert analysis
- Uses a Groq/Claude model via `groq` client
- Automatically returns a JSON verdict and incident report
- Can execute blocking and account-lock actions via system commands
- Docker-ready deployment
- Optional Slack notifications in GitHub workflows and Wazuh integration
- Optional Grafana visualization support for alert dashboards

## Repository layout

```text
.
├─ custom-integrations/
├─ custom-n8n/
├─ mini-soar/
│  └─ claude-agent/
│     ├─ app.py
│     ├─ Dockerfile
│     └─ .env (local, ignored)
├─ wazuh-n8n-lab/
└─ README.md
```

## Requirements

- Docker
- Git
- A valid `GROQ_API_KEY`
- Optional: Wazuh lab components if you want to integrate with the full environment
- Optional: GitHub secret `SLACK_WEBHOOK` to enable Slack notifications in the `wazuh-docker` workflows
- Optional: Grafana for dashboard visualization

## Setup

### 1. Create the `.env` file

In `mini-soar/claude-agent/`, create a `.env` file with at least:

```ini
GROQ_API_KEY=your_groq_api_key_here
```

Do not commit `.env` to Git. The repository already uses `.gitignore` to exclude environment files.

### 2. Build the Docker image

From `mini-soar/claude-agent`:

```powershell
cd "c:\Users\DELL\Documents\4CIR\PFA\MINI SOAR\mini-soar\claude-agent"
docker build -t mini-soar-agent .
```

### 3. Run the container

```powershell
docker run -d --name mini-soar-agent -p 8000:8000 --env-file .env --restart always mini-soar-agent
```

### 4. Verify the service

```powershell
curl http://localhost:8000/health
```

Expected response:

```json
{"status":"ok"}
```

## Grafana and Slack integration

### Grafana

Grafana is not required for the Flask SOAR agent, but it can be used to visualize Wazuh or SOAR alert data if you deploy it separately.

A simple Grafana container example:

```powershell
docker run -d --name grafana --network soc-net -p 3000:3000 --restart always -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:latest
```

Then open `http://localhost:3000` and configure dashboards.

### Slack

The `wazuh-n8n-lab/wazuh-docker/.github/workflows/` workflows include Slack notification steps using `rtCamp/action-slack-notify@v2`.

To enable those notifications, add a GitHub secret named `SLACK_WEBHOOK` in your repository settings.

The Wazuh lab environment also preserves Slack integration scripts under `wazuh-docker/build-docker-images/wazuh-manager/config/permanent_data.env`, including:

- `/var/ossec/integrations/slack.py`
- `/var/ossec/active-response/bin/wazuh-slack`

If you want alert notifications or CI messages in Slack, configure the webhook and channel accordingly.

## API Endpoints

### `GET /health`

Checks the service health.

### `POST /analyser`

Analyze a Wazuh alert and generate a SOAR verdict and incident report.

Example request:

```bash
curl -X POST http://localhost:8000/analyser \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "host-01",
    "threat_level": "high",
    "mitre_id": "T1078",
    "summary": "Multiple SSH authentication failures detected",
    "srcip": "10.0.0.5",
    "attacker_ip": "203.0.113.10",
    "occurrence_count": 12
  }'
```

### `POST /bloquer_ip`

Block an attacker IP using `iptables`.

```bash
curl -X POST http://localhost:8000/bloquer_ip \
  -H "Content-Type: application/json" \
  -d '{"ip":"203.0.113.10"}'
```

### `POST /lock_account`

Lock a Linux account.

```bash
curl -X POST http://localhost:8000/lock_account \
  -H "Content-Type: application/json" \
  -d '{"user":"alice"}'
```

## How it works

- `app.py` loads environment variables from `.env`
- It creates a `Groq` client using `GROQ_API_KEY`
- `/analyser` builds a security analysis prompt, calls the model, and parses JSON output
- It also creates a Markdown incident report using a second prompt
- Blocking and lock actions are delegated to system commands via `subprocess`

## Development

To run locally without Docker, install Python dependencies:

```powershell
python -m pip install flask groq python-dotenv
python app.py
```

Then open `http://localhost:8000`.

## GitHub and `.gitignore`

This repo should not include your secrets.

The current `.gitignore` should already ignore:

- `*.env`
- editor files such as `.vscode/`, `.idea/`
- local shell and cache files
- temporary files such as `*.log`, `*.pyc`, `__pycache__/`

## Notes and warnings

- `bloquer_ip` and `lock_account` use `sudo` and require privileged access.
- Run the Docker container or app on a trusted machine only.
- Adjust the prompt and analysis logic carefully before using in production.

## Contribution

If you want to improve this repository:

- add `mini-soar/claude-agent/env.example` with safe placeholder values
- document any Wazuh integration steps
- create a script to deploy the full Wazuh+n8n lab environment
- add tests for the analyzer payload and expected model responses

## License

Add a license file if you want to publish this repo publicly.

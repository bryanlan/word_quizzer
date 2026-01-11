---
name: word-quizzer-deploy
description: Deploy Word Quizzer frontend (Flutter PWA) and/or backend (FastAPI) to the Hetzner VPS using rsync + docker compose. Use when asked to deploy, release, sync, or publish Word Quizzer to word-quizzer.bryanlangley.org or word-quizzer-api.bryanlangley.org.
---

# Word Quizzer Deploy

## Overview

Deploy the latest Flutter PWA build and/or FastAPI backend from local repos to the VPS at 5.78.140.254 with rsync and docker compose.

## Workflow

1) Deploy scope
- Deploy BOTH frontend and backend every time unless the user explicitly asks to skip one.
- Use SSH key `~/.ssh/server_key` and host `root@5.78.140.254`.
- Always use rsync (no git on VPS).
- Keep `--delete` in rsync unless the user explicitly asks to avoid deletions.

2) Frontend (Flutter PWA)
- Source (authoritative): `/home/bryan/code/word_quizzer/mobile_app/build/web/`.
- Do not use `/home/bryan/code/Omnilearner/word-quizzer-frontend/` (outdated).
- If a rebuild is requested, run the build workflow first (prefer `tools/build.sh web` via `word-quizzer-build`).
- Deploy:
  `rsync -avz --delete -e "ssh -i ~/.ssh/server_key" /home/bryan/code/word_quizzer/mobile_app/build/web/ root@5.78.140.254:/var/www/word-quizzer/`
- Verify:
  `ssh -i ~/.ssh/server_key root@5.78.140.254 "ls -lh /var/www/word-quizzer/main.dart.js"`
  `curl -I https://word-quizzer.bryanlangley.org`

3) Backend (FastAPI)
- Source: `/home/bryan/code/Omnilearner/word-quizzer-backend/`.
- Deploy:
  `rsync -avz --delete -e "ssh -i ~/.ssh/server_key" /home/bryan/code/Omnilearner/word-quizzer-backend/ root@5.78.140.254:/opt/omnilearner/word-quizzer-backend/`
- Rebuild/restart:
  `ssh -i ~/.ssh/server_key root@5.78.140.254 'cd /opt/omnilearner && docker compose up -d --build word-quizzer-backend'`
- Verify:
  `ssh -i ~/.ssh/server_key root@5.78.140.254 'cd /opt/omnilearner && docker compose ps word-quizzer-backend'`
  `curl -I https://word-quizzer-api.bryanlangley.org/docs`

4) Troubleshooting quick checks
- If API returns 502: check `docker compose logs --tail=50 word-quizzer-backend` and `/var/log/nginx/error.log`.
- Ensure Nginx proxies to `http://127.0.0.1:8001` in `/etc/nginx/sites-available/word-quizzer-api`.
- If orphan container warnings appear and the user agrees, run:
  `ssh -i ~/.ssh/server_key root@5.78.140.254 'docker compose -f /opt/omnilearner/docker-compose.yml up -d --remove-orphans'`

5) Report
- Confirm what was deployed (frontend, backend, or both).
- Note the verified HTTP status codes and any warnings.

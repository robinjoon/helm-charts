FROM docker.n8n.io/n8nio/n8n:stable

USER root
RUN npm install -g @openai/codex
USER node

ENV PATH="/opt/nodejs/node-v24.13.1/bin:${PATH}"

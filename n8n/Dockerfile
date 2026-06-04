FROM docker.n8n.io/n8nio/n8n:stable

USER root

# Bump CODEX_CACHE_BUST (passed via --build-arg, e.g. the git short sha) to bypass
# Docker's layer cache and reinstall the latest @openai/codex on every build.
ARG CODEX_CACHE_BUST=unset
RUN echo "codex cache bust: ${CODEX_CACHE_BUST}" \
    && npm install -g @openai/codex@latest \
    && ln -sf "$(npm prefix -g)/bin/codex" /usr/local/bin/codex \
    && codex --version

USER node

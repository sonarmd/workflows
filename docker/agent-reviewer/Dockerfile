# syntax=docker/dockerfile:1.7
#
# ghcr.io/sonarmd/agent-reviewer
#
# Pre-baked image for the Stage 1 agent job of the
# `agent-architecture-review` workflow. The image runs as a DATA-ONLY
# reviewer:
#   - reads the PR diff handed to it via /work/diff.patch + /work/pr-meta.json
#   - reads the rubric + overlays from /opt/rubrics/
#   - emits a single findings.json conforming to
#     /opt/schemas/findings.v2.schema.json
#
# By design this image contains NO `gh` CLI and is invoked from a job
# with NO GitHub permissions. Only outbound capability: api.anthropic.com.
#
# The image is PUBLIC on GHCR. It contains no secrets. ANTHROPIC_API_KEY
# is injected by the calling workflow at runtime; never baked in.
#
# Tags:
#   :latest          — most recent build of `main`
#   :sha-<12hex>     — pinned by commit; reusable workflow uses this
#
# Build (local):
#   docker build -t ghcr.io/sonarmd/agent-reviewer:dev docker/agent-reviewer

ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim

# Pin Claude Code to a specific version (not `latest`) so a new upstream
# release that adds a tool family cannot bypass the entrypoint's
# `--disallowed-tools` blocklist in production. Bump deliberately and
# re-review the blocklist when you do.
ARG CLAUDE_CODE_VERSION=2.0.43
ARG IMAGE_REVISION=unknown

LABEL org.opencontainers.image.source="https://github.com/sonarmd/workflows"
LABEL org.opencontainers.image.description="Agent architecture reviewer (Stage 1 of agent-architecture-review)"
LABEL org.opencontainers.image.licenses="Proprietary"
LABEL org.opencontainers.image.revision="${IMAGE_REVISION}"

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    AGENT_REVIEWER_RUBRICS_DIR=/opt/rubrics \
    AGENT_REVIEWER_SCHEMAS_DIR=/opt/schemas

# System packages — minimal. NO gh CLI by design.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        jq \
        tini \
 && rm -rf /var/lib/apt/lists/*

# Claude Code CLI.
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

# Rubrics + bundled schema for self-validation.
COPY rubrics/ /opt/rubrics/
COPY schemas/ /opt/schemas/

# Reference cards — lean one-page primers (DDD, FCIS, Clean Architecture,
# abstraction discipline) included in the agent prompt by the entrypoint.
# Kept deliberately short so they grouund the model without bloating
# token usage on every PR.
COPY references/ /opt/references/

COPY entrypoint.sh /usr/local/bin/agent-review
RUN chmod +x /usr/local/bin/agent-review

# Working directory is mounted by GHA at /__w/<repo>/<repo> when used
# with `container:`. We intentionally do NOT change WORKDIR here.

# tini handles signal forwarding so SIGTERM from GHA cancels claude cleanly.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agent-review"]
CMD ["--help"]

Subject: Permission Inquiry: Including Claude Code CLI in a Free, Open-Source Docker Image for Personal Use

Dear Anthropic Legal / Partnerships Team,

I am writing to seek clarification on whether the following use case complies with your Terms of Service and Commercial Terms.

## About Our Project

I am the developer of **OneCode**, an open-source (MIT-licensed) project that provides a browser-based IDE experience around command-line AI tools. The project is available on GitHub at:

- Repository: https://github.com/yiyan-yixing/onecode

OneCode is intended for **personal learning and research purposes only**. It is not a commercial product, and we do not charge for it in any way.

## Current Approach

Our Docker image installs the Claude Code CLI during the image build process:

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@2.1.177
```

Users then pull the pre-built image from GitHub Container Registry (GHCR) and run it with their own API key. This means the Docker image distributed to users **contains a copy of the Claude Code CLI binary**.

## Our Concern

We recognize that Claude Code is proprietary software ("© Anthropic PBC. All rights reserved"), and that distributing a pre-built Docker image containing it may constitute redistribution under your license terms. We want to ensure we are operating within your guidelines.

## Two Questions

**1. Is it permissible to include Claude Code in a free, open-source Docker image distributed via GHCR?**

Specifically:
- The image is free — no payment, subscription, or registration required
- The project is MIT-licensed and open-source
- Users must provide their own Anthropic API key to use Claude Code
- We do not modify, reverse-engineer, or repackage Claude Code in any way
- We do not route or proxy OAuth credentials from Free/Pro/Max users
- We do not compete with or position OneCode as an alternative to any Anthropic product
- OneCode serves as a frontend enhancement (browser IDE, Agent roles) that calls Claude Code as-is

**2. If redistribution in a Docker image is not permitted, would the following alternative be acceptable?**

Instead of pre-installing Claude Code during `docker build`, we would have the CLI installed at container startup time:

```bash
# In entrypoint.sh — runs when the user starts the container
if ! command -v claude &>/dev/null; then
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
fi
```

Under this approach, the Docker image itself would **not contain** Claude Code. Users would effectively be running `npm install -g` inside their own container, equivalent to installing it on their own machine. We would simply automate this step for convenience.

## Additional Context

- We are happy to add any disclaimers, attribution, or notices you require
- We are happy to prominently state that OneCode is not affiliated with or endorsed by Anthropic
- If there is a partnership or integration program we should join, please let us know
- We are committed to full compliance with your Terms of Service and Commercial Terms

Thank you for your time and guidance. I understand this is not a typical inquiry, and I appreciate your patience. Please feel free to direct me to the appropriate team or process if this falls outside your scope.

Best regards,

[yiyan-yixing]
GitHub: https://github.com/yiyan-yixing
Project: https://github.com/yiyan-yixing/onecode

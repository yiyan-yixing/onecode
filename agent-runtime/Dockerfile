FROM node:24-slim

# Use Tsinghua mirror for apt (faster in China)
RUN sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    curl \
    wget \
    jq \
    vim-tiny \
    make \
    g++ \
    ca-certificates \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    gosu \
    openssh-server \
    tzdata \
    locales \
    openssl \
    tini \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libasound2 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libxshmfence1 \
    libpango-1.0-0 \
    libcairo2 \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI — enables `docker build` inside container via host's Docker daemon
# (socket mounted by oc at runtime, no daemon runs inside the container)
# NOTE: use armored key (.asc) directly — node:24-slim has no `gpg` binary
# (git's gnupg is only a Recommends, dropped by --no-install-recommends above)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL --retry 3 --retry-delay 2 https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# GitHub mirror(s) for China network — comma-separated list tried in order by gh_fetch.
# Set to "" to use direct github.com only. Override at build: --build-arg GH_MIRROR="https://my-mirror.com"
ARG GH_MIRROR="https://ghfast.top,https://gh.llkk.cc,https://gh-proxy.com"

# gh_fetch: download from GitHub with mirror fallback
# Usage: gh_fetch <github_path> <output_path>
# e.g.  gh_fetch "owner/repo/releases/download/v1/file.tar.gz" - | tar xz
#       gh_fetch "owner/repo/releases/download/v1/file.zip" /tmp/file.zip
#
# Env: GH_MIRROR — mirror prefix (e.g. https://gh-proxy.com), empty = direct
COPY bin/gh_fetch.sh /usr/local/bin/gh_fetch
RUN chmod +x /usr/local/bin/gh_fetch

# JetBrains Mono font (sharp, ligature-free terminal font)
RUN mkdir -p /usr/local/share/fonts/jetbrains-mono \
    && gh_fetch "JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" /tmp/jb.zip \
    && python3 -c "import zipfile; zipfile.ZipFile('/tmp/jb.zip').extractall('/tmp/jb')" \
    && cp /tmp/jb/fonts/ttf/JetBrainsMono-Regular.ttf /usr/local/share/fonts/jetbrains-mono/ \
    && cp /tmp/jb/fonts/ttf/JetBrainsMono-Bold.ttf /usr/local/share/fonts/jetbrains-mono/ \
    && cp /tmp/jb/fonts/ttf/JetBrainsMono-Medium.ttf /usr/local/share/fonts/jetbrains-mono/ \
    && cp /tmp/jb/fonts/ttf/JetBrainsMono-SemiBold.ttf /usr/local/share/fonts/jetbrains-mono/ \
    && fc-cache -f \
    && rm -rf /tmp/jb /tmp/jb.zip

# Python packages (use Tsinghua mirror for China network)
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --trusted-host pypi.tuna.tsinghua.edu.cn \
    -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Claude Code CLI version (installed at runtime by entrypoint.sh, NOT pre-baked into the image)
# This avoids redistribution of Anthropic's proprietary software in the Docker image.
# Users install it themselves when the container starts, equivalent to running `npm install -g` on their own machine.
ARG CLAUDE_CODE_VERSION=2.1.177

# OpenCode CLI (MIT license — safe to pre-install in the image)
# Alternative AI backend to Claude Code, supports multiple LLM providers.
# https://github.com/opencode-ai/opencode
ARG OPENCODE_VERSION=0.5.0
RUN ARCH=$(dpkg --print-architecture) \
    && gh_fetch "opencode-ai/opencode/releases/download/v${OPENCODE_VERSION}/opencode_${OPENCODE_VERSION}_linux_${ARCH}.tar.gz" - \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/opencode \
    && opencode --version 2>/dev/null || true

# filebrowser - Web-based file manager
RUN ARCH=$(dpkg --print-architecture) \
    && gh_fetch "filebrowser/filebrowser/releases/download/v2.63.5/linux-${ARCH}-filebrowser.tar.gz" - \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/filebrowser \
    && [ "$(stat -c%s /usr/local/bin/filebrowser)" -gt 1000 ]

# code-server - Web-based VS Code (accessible via /vscode/ route)
RUN CODE_SERVER_VERSION="4.121.0" \
    && ARCH=$(dpkg --print-architecture) \
    && gh_fetch "coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${ARCH}.tar.gz" /tmp/code-server.tar.gz \
    && tar xzf /tmp/code-server.tar.gz -C /usr/local/lib/ \
    && ln -sf /usr/local/lib/code-server-*/bin/code-server /usr/local/bin/code-server \
    && rm -f /tmp/code-server.tar.gz \
    && which code-server

# node-pty + ws (native module — needs node headers from China mirror)
RUN npm_config_disturl=https://npmmirror.com/mirrors/node \
    npm install --prefix /tmp/pty node-pty@1.0.0 ws@8.18.0 \
    --registry=https://registry.npmmirror.com \
    && mkdir -p /usr/local/share/gateway/node_modules \
    && mv /tmp/pty/node_modules/node-pty /usr/local/share/gateway/node_modules/ \
    && mv /tmp/pty/node_modules/ws /usr/local/share/gateway/node_modules/ \
    && rm -rf /tmp/pty

# Gateway app (split into two layers: static assets vs code)
# Layer 1: static assets (npm build output — independent of gateway code changes)
RUN mkdir -p /usr/local/share/gateway/static \
    && npm install --prefix /tmp/gw marked@9.1.6 highlight.js@11.9.0 \
       @xterm/xterm@5.5.0 @xterm/addon-fit@0.10.0 @xterm/addon-web-links@0.11.0 \
       @xterm/addon-webgl@0.18.0 \
       --registry=https://registry.npmmirror.com \
    && cp /tmp/gw/node_modules/marked/marked.min.js /usr/local/share/gateway/static/ \
    && node -e '\
const fs=require("fs"),p=require("path"),r="/tmp/gw/node_modules/highlight.js";\
let c=fs.readFileSync(p.join(r,"lib/core.js"),"utf8");\
let b="(function(){\nvar module={exports:{}};\n"+c.replace(/module\.exports\s*=/,"var hljs=");\
const L={javascript:"javascript.js",typescript:"typescript.js",python:"python.js",ruby:"ruby.js",go:"go.js",rust:"rust.js",java:"java.js",c:"c.js",cpp:"cpp.js",csharp:"csharp.js",php:"php.js",bash:"bash.js",yaml:"yaml.js",json:"json.js",xml:"xml.js",css:"css.js",scss:"scss.js",sql:"sql.js",markdown:"markdown.js",dockerfile:"dockerfile.js",makefile:"makefile.js",ini:"ini.js",lua:"lua.js",swift:"swift.js",kotlin:"kotlin.js",dart:"dart.js",scala:"scala.js",nginx:"nginx.js",diff:"diff.js",plaintext:"plaintext.js",protobuf:"protobuf.js",hcl:"hcl.js",groovy:"groovy.js",powershell:"powershell.js"};\
const d=p.join(r,"lib/languages"),s=new Set();\
Object.entries(L).forEach(function(e){var n=e[0],f=e[1];if(s.has(f))return;s.add(f);\
var fp=p.join(d,f);if(!fs.existsSync(fp))return;\
var src=fs.readFileSync(fp,"utf8");\
var exp=src.match(/module\.exports\s*=\s*(\w+)/);\
var body=src.replace(/\n?module\.exports\s*=\s*\w+\s*;?\s*$/,"").replace(/\bexport\s+default\s*/,"");\
if(exp){b+="\nhljs.registerLanguage(\""+n+"\",function(hljs){"+body+";return "+exp[1]+"(hljs);});\n";}\
else{var fn=body.match(/function\s*\(hljs[^)]*\)\s*\{/);if(fn){b+="\nhljs.registerLanguage(\""+n+"\","+body.replace(fn[0],"function(hljs){")+");\n";}}\
});\
b+="\nwindow.hljs=hljs;\n})();\n";\
fs.writeFileSync("/usr/local/share/gateway/static/highlight.min.js",b);\
' \
    && cp /tmp/gw/node_modules/highlight.js/styles/github-dark-dimmed.min.css /usr/local/share/gateway/static/hljs.css \
    && cp /tmp/gw/node_modules/@xterm/xterm/lib/xterm.js /usr/local/share/gateway/static/xterm.min.js \
    && cp /tmp/gw/node_modules/@xterm/xterm/css/xterm.css /usr/local/share/gateway/static/ \
    && cp /tmp/gw/node_modules/@xterm/addon-fit/lib/addon-fit.js /usr/local/share/gateway/static/addon-fit.min.js \
    && cp /tmp/gw/node_modules/@xterm/addon-web-links/lib/addon-web-links.js /usr/local/share/gateway/static/addon-web-links.min.js \
    && cp /tmp/gw/node_modules/@xterm/addon-webgl/lib/addon-webgl.js /usr/local/share/gateway/static/addon-webgl.min.js \
    && rm -rf /tmp/gw \
    && [ "$(stat -c%s /usr/local/share/gateway/static/marked.min.js)" -gt 10000 ] \
    && [ "$(stat -c%s /usr/local/share/gateway/static/highlight.min.js)" -gt 10000 ] \
    && [ "$(stat -c%s /usr/local/share/gateway/static/xterm.min.js)" -gt 10000 ]

# Layer 2: gateway code (only rebuilds when gateway/ changes)
COPY gateway/ /usr/local/share/gateway/

# SSH server for VS Code Remote-SSH
RUN mkdir -p /run/sshd \
    && cat > /etc/ssh/sshd_config.d/onecode.conf <<SSHD
Port 8222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile /home/work/.ssh-keys/authorized_keys
SSHD

# Change node user home to /home/work
RUN usermod -d /home/work node \
    && mkdir -p /home/work \
    && echo '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true,"bypassPermissionsModeAccepted":true}}}' > /home/work/.claude.json \
    && chown -R node:node /home/work /home/work/.claude.json

# Bash color support and common aliases
RUN echo 'export TERM=xterm-256color' >> /home/work/.bashrc \
    && echo 'alias ll="ls -l --color=auto"' >> /home/work/.bashrc \
    && echo 'alias ls="ls --color=auto"' >> /home/work/.bashrc \
    && echo 'alias grep="grep --color=auto"' >> /home/work/.bashrc \
    && chown node:node /home/work/.bashrc

# Claude Code: allow all tools (container provides isolation)
RUN mkdir -p /home/work/.claude /home/work/.claude/command && chown -R node:node /home/work/.claude
COPY settings.json /home/work/.claude/
COPY cc-statusline-command/statusline-command.sh /home/work/.claude/command/statusline-command.sh
COPY cc-statusline-command/cron-tracker.sh /home/work/.claude/command/cron-tracker.sh
RUN chmod +x /home/work/.claude/command/statusline-command.sh /home/work/.claude/command/cron-tracker.sh

# code-server: default VS Code user settings
RUN mkdir -p /home/work/.local/share/code-server/User \
    && printf '{\n  "workbench.activityBar.location": "default",\n  "workbench.activityBar.compact": true,\n  "workbench.colorTheme": "Dark 2026",\n  "terminal.integrated.fontFamily": "JetBrains Mono, SF Mono, Fira Code, Consolas, monospace",\n  "terminal.integrated.fontSize": 13,\n  "terminal.integrated.fontWeight": "normal",\n  "terminal.integrated.fontWeightBold": "bold",\n  "editor.fontFamily": "JetBrains Mono, SF Mono, Fira Code, Consolas, monospace",\n  "editor.fontSize": 13,\n  "editor.fontWeight": "normal",\n  "claudeCode.useTerminal": true,\n  "claudeCode.disableLoginPrompt": true,\n  "claudeCode.initialPermissionMode": "bypassPermissions",\n  "claudeCode.hideOnboarding": true,\n  "claudeCode.environmentVariables": {}\n}\n' > /home/work/.local/share/code-server/User/settings.json \
    && chown -R node:node /home/work/.local

# Version file
COPY VERSION /usr/local/share/onecode/VERSION

# Workspace
RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

# Entrypoint scripts (changing scripts only rebuilds from this layer)
COPY bin/start-sshd.sh bin/start-remote.sh bin/setup-code-server.sh /usr/local/bin/onecode/
RUN chmod +x /usr/local/bin/onecode/*.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PATH="/usr/local/bin:$PATH"

ENV TZ="Asia/Shanghai" \
    LANG="zh_CN.UTF-8"

# Generate zh_CN.UTF-8 locale
RUN sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Agent runtime config (mapped to Claude Code env vars in entrypoint.sh)
# NOTE: API_KEY is intentionally NOT declared here — pass at runtime via
# `docker run -e API_KEY=xxx` to avoid persisting secrets into image layers.
ENV API_BASE_URL="https://api.anthropic.com" \
    MODEL="claude-sonnet-4-6"

# App port: pre-reserved port for AI-generated services
# AI agents can start web services on this port and they will be accessible from outside the container
ENV APP_PORT=8000

# Web terminal port + SSH port + App service port
EXPOSE 7681 8222 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "var m=process.env.GATEWAY_HTTPS==='1'?'https':'http';require(m).get(m+'://localhost:7681/',function(r){process.exit(r.statusCode<400?0:1)}).on('error',function(){process.exit(1)})"

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["claude"]

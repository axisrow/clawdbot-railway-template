# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS openclaw-build

ENV NPM_CONFIG_FETCH_RETRIES=5 \
    NPM_CONFIG_FETCH_RETRY_FACTOR=2 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=20000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=120000 \
    NPM_CONFIG_PREFER_ONLINE=true

# Dependencies needed for openclaw build
RUN apt-get -o Acquire::Retries=5 update \
  && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it). Retry and request origin revalidation on 503-like edge failures.
RUN set -eux; \
  tmp_script="$(mktemp)"; \
  for src in \
    "https://bun.sh/install" \
    "https://raw.githubusercontent.com/oven-sh/bun/main/install.sh"; do \
    if curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
      -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
      "${src}?_=$(date +%s)" -o "${tmp_script}"; then \
      bash "${tmp_script}"; \
      rm -f "${tmp_script}"; \
      exit 0; \
    fi; \
  done; \
  rm -f "${tmp_script}"; \
  echo "Failed to download Bun installer after retries/fallback" >&2; \
  exit 1
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known-good ref (tag/branch). Override in Railway template settings if needed.
# Using a released tag avoids build breakage when `main` temporarily references unpublished packages.
ARG OPENCLAW_GIT_REF=v2026.3.12
RUN set -eux; \
  cloned=0; \
  for attempt in 1 2 3; do \
    rm -rf /tmp/openclaw-src; \
    if git -c http.extraHeader="Cache-Control: no-cache" clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git /tmp/openclaw-src; then \
      cp -a /tmp/openclaw-src/. .; \
      rm -rf /tmp/openclaw-src; \
      cloned=1; \
      break; \
    fi; \
    sleep $((attempt * 5)); \
  done; \
  if [ "${cloned}" -eq 0 ]; then \
    for archive_url in \
      "https://github.com/openclaw/openclaw/archive/refs/tags/${OPENCLAW_GIT_REF}.tar.gz" \
      "https://github.com/openclaw/openclaw/archive/refs/heads/${OPENCLAW_GIT_REF}.tar.gz" \
      "https://codeload.github.com/openclaw/openclaw/tar.gz/${OPENCLAW_GIT_REF}"; do \
      if curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
        -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
        "${archive_url}?_=$(date +%s)" -o /tmp/openclaw.tar.gz; then \
        tar -xzf /tmp/openclaw.tar.gz --strip-components=1 -C .; \
        rm -f /tmp/openclaw.tar.gz; \
        cloned=1; \
        break; \
      fi; \
    done; \
  fi; \
  if [ "${cloned}" -eq 0 ]; then \
    echo "Failed to download OpenClaw source after retries/fallback" >&2; \
    exit 1; \
  fi

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN set -eux; \
  for attempt in 1 2 3; do \
    if pnpm install --no-frozen-lockfile --fetch-retries=5 --fetch-retry-mintimeout=20000 --fetch-retry-maxtimeout=120000; then \
      break; \
    fi; \
    if [ "${attempt}" -eq 3 ]; then \
      echo "pnpm install failed after retries" >&2; \
      exit 1; \
    fi; \
    sleep $((attempt * 8)); \
  done
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production
ENV NPM_CONFIG_FETCH_RETRIES=5 \
    NPM_CONFIG_FETCH_RETRY_FACTOR=2 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=20000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=120000 \
    NPM_CONFIG_PREFER_ONLINE=true

RUN apt-get -o Acquire::Retries=5 update \
  && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    curl \
    file \
    git \
    procps \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 -s /bin/bash linuxbrew

RUN set -eux; \
  for attempt in 1 2 3; do \
    if su -c \
      'NONINTERACTIVE=1 HOMEBREW_NO_ANALYTICS=1 \
       /bin/bash -c "$(curl -fsSL \
         --retry 5 --retry-all-errors --retry-delay 2 \
         -H \"Cache-Control: no-cache\" -H \"Pragma: no-cache\" \
         https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
      linuxbrew; then \
      break; \
    fi; \
    if [ "${attempt}" -eq 3 ]; then \
      echo "Homebrew install failed after retries" >&2; \
      exit 1; \
    fi; \
    sleep $((attempt * 10)); \
  done

RUN chmod -R o+rwX /home/linuxbrew/.linuxbrew

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_ANALYTICS=1
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar
ENV HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew

# `openclaw update` expects pnpm. Provide it in the runtime image.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN set -eux; \
  for attempt in 1 2 3; do \
    if npm install --omit=dev --prefer-online --fetch-retries=5 --fetch-retry-mintimeout=20000 --fetch-retry-maxtimeout=120000; then \
      npm cache clean --force; \
      break; \
    fi; \
    if [ "${attempt}" -eq 3 ]; then \
      echo "npm install failed after retries" >&2; \
      exit 1; \
    fi; \
    sleep $((attempt * 8)); \
  done

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide an openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# The wrapper listens on this port.
ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]

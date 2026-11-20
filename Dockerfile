FROM golang:1.26-bookworm AS builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go run github.com/AshokShau/gotdbot/scripts/tools
RUN go run setup_ntgcalls.go

RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-w -s" -o main .

FROM debian:12-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    wget \
    unzip \
    curl \
    lsb-release \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/yt-dlp \
    https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux \
    && chmod +x /usr/local/bin/yt-dlp

RUN curl -fsSL https://deno.land/install.sh | sh \
    && export DENO_INSTALL="/opt/deno" \
    && export PATH="$DENO_INSTALL/bin:$PATH" \
    && mv /root/.deno /opt/deno \
    && ln -sf /opt/deno/bin/deno /usr/local/bin/deno

RUN groupadd -r app && useradd -r -g app -m -d /home/app app

ENV DENO_INSTALL="/opt/deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"
ENV HOME="/home/app"

COPY --from=builder --chown=app:app /app/main /usr/local/bin/app
COPY --from=builder --chown=app:app /app/libtdjson.so.* /home/app/

# main.go loads this exact TDLib filename. Normalize the downloaded
# versioned library name to the path expected by gotdbot.
RUN set -eux; \
    if [ ! -e /home/app/libtdjson.so.1.8.70 ]; then \
        lib="$(find /home/app -maxdepth 1 -type f -name 'libtdjson.so.*' ! -name 'libtdjson.so.1.8.70' | sort | head -n 1)"; \
        test -n "$lib"; \
        ln -s "$(basename "$lib")" /home/app/libtdjson.so.1.8.70; \
    fi; \
    chown -R app:app /home/app /opt/deno

USER app

WORKDIR /home/app
ENTRYPOINT ["app"]

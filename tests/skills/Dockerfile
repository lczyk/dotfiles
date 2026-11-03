FROM ghcr.io/lczyk/pats/sandbox:26.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        jq && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

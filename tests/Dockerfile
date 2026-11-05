# THROWAWAY STAND-IN FOR THE WORKSTATION: A `pipeline` USER AND THE VLT DATA FOLDERS
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home pipeline \
    && mkdir -p /data/raw /data/reduced \
    && chown -R pipeline /data \
    && chmod 777 /data
USER pipeline
WORKDIR /home/pipeline

# THROWAWAY STAND-IN FOR THE WORKSTATION: A `pipeline` USER AND THE VLT DATA FOLDERS.
# ON THE WORKSTATION, /data/raw IS A LINK TO /diskb/data/raw.
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /diska/home \
    && useradd --create-home --home-dir /diska/home/pipeline pipeline \
    && mkdir -p /diskb/data/raw /data/reduced \
    && ln -s /diskb/data/raw /data/raw \
    && chown -R pipeline /data /diskb \
    && chmod 777 /data
USER pipeline
WORKDIR /diska/home/pipeline

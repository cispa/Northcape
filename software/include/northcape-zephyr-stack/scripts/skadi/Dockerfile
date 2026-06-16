FROM ubuntu:22.04

WORKDIR /workspace

COPY scripts/ /workspace/scripts

RUN apt update && apt install sudo

RUN ./scripts/skadi/install-packages.sh

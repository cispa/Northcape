FROM ubuntu:22.04

WORKDIR /scripts

COPY patches /patches

COPY scripts/install-dependencies.sh .

COPY scripts/install-openpdk.sh .

RUN ./install-dependencies.sh

# cleanup build temporaries
RUN rm -r /tmp/*

# STEP 1 build ui
FROM --platform=$BUILDPLATFORM node:22-alpine AS node

RUN apk update && apk add --no-cache make git

WORKDIR /build

RUN git clone https://github.com/bacopilot/cvee.git /build
RUN git fetch --tags
RUN git checkout 0.305.1

# install node tools
RUN npm ci

# build ui
RUN make ui


# STEP 2 build executable binary
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS builder

# Install git + SSL ca certificates.
# Git is required for fetching the dependencies.
# Ca-certificates is required to call HTTPS endpoints.
RUN apk update && apk add --no-cache git make patch tzdata ca-certificates && update-ca-certificates

# define RELEASE=1 to hide commit hash
ARG RELEASE=0

WORKDIR /build

RUN git clone https://github.com/bacopilot/ccve.git /build
RUN git fetch --tags
RUN git checkout 0.305.2

# Copy modified auth.go to fix sponsorship
# COPY auth.go util/sponsor/auth.go

RUN go mod download

RUN make install

RUN make patch-asn1
RUN make assets

# copy ui
COPY --from=node /build/dist /build/dist

# build
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
ARG GOARM=${TARGETVARIANT#v}



RUN RELEASE=${RELEASE} GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${GOARM} make build


# STEP 3 build a small image including module support
FROM alpine:3.20

WORKDIR /app

ENV TZ=Europe/Berlin

# Import from builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /build/evcc /usr/local/bin/evcc

RUN apk update && apk add --no-cache bash

# mDNS
#EXPOSE 5353/udp
# EEBus
#EXPOSE 4712/tcp
# UI and /api
EXPOSE 7070/tcp
# KEBA charger
#EXPOSE 7090/udp
# OCPP charger
EXPOSE 8887/tcp
# Modbus UDP
EXPOSE 8899/udp
# SMA Energy Manager
#EXPOSE 9522/udp

#HEALTHCHECK --interval=60s --start-period=60s --timeout=30s --retries=3 CMD [ "evcc", "health" ]

#ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD [ "evcc" ]

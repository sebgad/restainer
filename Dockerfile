# BUILD restic binary from source
FROM docker.io/library/golang:alpine AS dist

# Install build tools.
RUN apk add --update --no-cache \
        build-base curl git

ARG restic_ver=0.17.1

# Prepare dirs for export
RUN mkdir -p /out/usr/local/bin/ \
             /out/usr/share/licenses/restic/

RUN curl -fL -o /tmp/restic.tar.gz \
         https://github.com/restic/restic/releases/download/v${restic_ver}/restic-${restic_ver}.tar.gz \
 && tar -xzf /tmp/restic.tar.gz -C /tmp

# Build restic
RUN cd /tmp/restic-* \
 && go run build.go \
 && cp restic /out/usr/local/bin/ \
 && cp LICENSE /out/usr/share/licenses/restic/

# Use restic build in alpine linux container
FROM docker.io/library/alpine AS runtime

RUN rm -rf /var/cache/apk/*
COPY --from=dist /out/ /

RUN apk add --update --no-cache mariadb-client

RUN \
    mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log; \
    touch /var/log/cron.log;

ENV RESTIC_REPOSITORY=/mnt/repo \
    RESTIC_PASSWORD=""

ENV RESTIC_TAG=""
ENV BACKUP_CRON="0 */6 * * *"
ENV CHECK_CRON=""
ENV MARIADB_DATABASE=""
ENV MARIADB_BACKUP_USER=""
ENV MARIADB_BACKUP_PW=""
ENV RESTIC_INIT_ARGS=""
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""
ENV RESTIC_DATA_SUBSET=""

# Backup directory
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /entry.sh

ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0","/var/log/cron.log"]

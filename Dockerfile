# wp-sqlite-elementor-server — WordPress + SQLite on FrankenPHP (scratch runtime)
#
# Build variants (Elementor stack is optional):
#   Full (default):        docker build .
#   No Pro Elements:       docker build --build-arg WITH_PRO_ELEMENTS=false .
#   No Elementor at all:   docker build --build-arg WITH_ELEMENTOR=false \
#                                       --build-arg WITH_PRO_ELEMENTS=false \
#                                       --build-arg WITH_HELLO_ELEMENTOR=false .
#   Pin versions:          docker build --build-arg WP_VERSION=6.9.4 \
#                                       --build-arg FRANKENPHP_VERSION=v1.9.0 .
ARG FRANKENPHP_VERSION=latest

FROM alpine:3.21 AS builder
ARG TARGETARCH
ARG FRANKENPHP_VERSION
# WordPress version: "latest" or an explicit version like 6.9.4
ARG WP_VERSION=latest
# Optional Elementor stack — set any to "false" to exclude. SQLite is always included.
ARG WITH_ELEMENTOR=true
ARG WITH_PRO_ELEMENTS=true
ARG WITH_HELLO_ELEMENTOR=true
ARG PRO_ELEMENTS_REPO=https://github.com/juslintek/proelements.git
ARG PRO_ELEMENTS_REF=elementor-4.0-compat

RUN apk add --no-cache curl unzip ca-certificates busybox-static git

# FrankenPHP binary (latest or pinned tag)
RUN ARCH=$([ "$TARGETARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    URL="https://github.com/dunglas/frankenphp/releases" && \
    if [ "$FRANKENPHP_VERSION" = "latest" ]; then \
      URL="$URL/latest/download/frankenphp-linux-$ARCH"; \
    else \
      URL="$URL/download/$FRANKENPHP_VERSION/frankenphp-linux-$ARCH"; \
    fi && \
    curl -sL -o /frankenphp "$URL" && chmod +x /frankenphp && \
    /frankenphp version

RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /wp-cli.phar && chmod +x /wp-cli.phar

# PHP ini + WordPress core (latest or pinned)
RUN mkdir -p /etc/php && printf "memory_limit=512M\nerror_reporting=E_ALL&~E_DEPRECATED\nupload_max_filesize=64M\npost_max_size=64M\n" > /etc/php/custom.ini && \
    if [ "$WP_VERSION" = "latest" ]; then WPVER=""; else WPVER="--version=$WP_VERSION"; fi && \
    PHP_INI_SCAN_DIR=/etc/php /frankenphp php-cli /wp-cli.phar core download --path=/wp $WPVER --allow-root

# Plugin/theme stack. SQLite Database Integration is ALWAYS included (it is the DB layer).
# Elementor / Pro Elements / Hello Elementor are gated behind build args.
RUN mkdir -p /opt/elementor-stack && \
    curl -sL -o /tmp/s.zip "https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip" && \
    unzip -q /tmp/s.zip -d /opt/elementor-stack/ && \
    if [ "$WITH_ELEMENTOR" = "true" ] || [ "$WITH_PRO_ELEMENTS" = "true" ]; then \
      echo ">> including Elementor" && \
      curl -sL -o /tmp/e.zip "https://downloads.wordpress.org/plugin/elementor.latest-stable.zip" && \
      unzip -q /tmp/e.zip -d /opt/elementor-stack/; \
    fi && \
    if [ "$WITH_PRO_ELEMENTS" = "true" ]; then \
      echo ">> including Pro Elements ($PRO_ELEMENTS_REF)" && \
      git clone --depth 1 -b "$PRO_ELEMENTS_REF" "$PRO_ELEMENTS_REPO" /opt/elementor-stack/pro-elements && \
      rm -rf /opt/elementor-stack/pro-elements/.git; \
    fi && \
    if [ "$WITH_HELLO_ELEMENTOR" = "true" ]; then \
      echo ">> including hello-elementor" && \
      curl -sL -o /tmp/h.zip "https://downloads.wordpress.org/theme/hello-elementor.latest-stable.zip" && \
      unzip -q /tmp/h.zip -d /opt/elementor-stack/; \
    fi && \
    rm -rf /tmp/*.zip

RUN printf '{\n\tauto_https off\n\tadmin off\n\tfrankenphp\n}\n:8080 {\n\troot * /wp\n\tencode zstd br gzip\n\tphp_server\n}\n' > /Caddyfile

FROM scratch
COPY --from=builder /bin/busybox.static /bin/busybox
RUN ["/bin/busybox", "sh", "-c", "/bin/busybox --install -s /bin"]
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /frankenphp /usr/local/bin/frankenphp
COPY --from=builder /wp-cli.phar /usr/local/bin/wp
COPY --from=builder /etc/php/custom.ini /etc/php/custom.ini
COPY --from=builder /wp /wp
COPY --from=builder /opt/elementor-stack /opt/elementor-stack
COPY --from=builder /Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /entrypoint.sh
RUN ["/bin/busybox", "sh", "-c", "mkdir -p /tmp /var/log /data/caddy /config/caddy /root"]

ENV HOME=/root SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt PHP_INI_SCAN_DIR=/etc/php PATH=/usr/local/bin:/bin
WORKDIR /wp
EXPOSE 8080
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

ARG FRANKENPHP_VERSION=latest

FROM alpine:3.21 AS builder
ARG TARGETARCH
ARG FRANKENPHP_VERSION
ARG PRO_ELEMENTS_VERSION=v3.35.0

RUN apk add --no-cache curl unzip ca-certificates busybox-static git

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

RUN mkdir -p /etc/php && printf "memory_limit=512M\nerror_reporting=E_ALL&~E_DEPRECATED\nupload_max_filesize=64M\npost_max_size=64M\n" > /etc/php/custom.ini && \
    PHP_INI_SCAN_DIR=/etc/php /frankenphp php-cli /wp-cli.phar core download --path=/wp --allow-root

RUN mkdir -p /opt/elementor-stack && \
    curl -sL -o /tmp/s.zip "https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip" && unzip -q /tmp/s.zip -d /opt/elementor-stack/ && \
    curl -sL -o /tmp/e.zip "https://downloads.wordpress.org/plugin/elementor.latest-stable.zip" && unzip -q /tmp/e.zip -d /opt/elementor-stack/ && \
    git clone --depth 1 -b elementor-4.0-compat https://github.com/juslintek/proelements.git /opt/elementor-stack/pro-elements && rm -rf /opt/elementor-stack/pro-elements/.git && \
    curl -sL -o /tmp/h.zip "https://downloads.wordpress.org/theme/hello-elementor.latest-stable.zip" && unzip -q /tmp/h.zip -d /opt/elementor-stack/ && \
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

# ── Stage 1: Download everything ───────────────────────────────────────────────
FROM alpine:3.21 AS builder

ARG TARGETARCH

RUN apk add --no-cache curl unzip git ca-certificates busybox-static

# FrankenPHP static binary (PHP 8.5 + Caddy — single file, zero dependencies)
RUN ARCH=$([ "$TARGETARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    curl -sL -o /frankenphp \
      "https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-$ARCH" && \
    chmod +x /frankenphp

# WP-CLI
RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /wp-cli.phar && chmod +x /wp-cli.phar

# WordPress
RUN mkdir -p /etc/php && printf "memory_limit=512M\nerror_reporting=E_ALL&~E_DEPRECATED\n" > /etc/php/custom.ini && \
    PHP_INI_SCAN_DIR=/etc/php /frankenphp php-cli /wp-cli.phar core download --path=/wp --allow-root

# Plugins + theme
RUN mkdir -p /opt/elementor-stack && \
    curl -sL -o /tmp/s.zip "https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip" && \
    unzip -q /tmp/s.zip -d /opt/elementor-stack/ && \
    curl -sL -o /tmp/e.zip "https://downloads.wordpress.org/plugin/elementor.latest-stable.zip" && \
    unzip -q /tmp/e.zip -d /opt/elementor-stack/ && \
    git clone --depth 1 https://github.com/proelements/proelements.git /opt/elementor-stack/pro-elements && \
    rm -rf /opt/elementor-stack/pro-elements/.git && \
    curl -sL -o /tmp/h.zip "https://downloads.wordpress.org/theme/hello-elementor.latest-stable.zip" && \
    unzip -q /tmp/h.zip -d /opt/elementor-stack/ && \
    rm -rf /tmp/*.zip

# Caddyfile
RUN cat > /Caddyfile << 'CADDY'
{
	auto_https off
	admin off
	frankenphp
}

:8080 {
	root * /wp
	encode zstd br gzip
	php_server
}
CADDY

# ── Stage 2: Scratch — zero OS, zero CVEs ─────────────────────────────────────
FROM scratch

# Busybox static — provides sh, ln, mkdir, cat, sed, rm, wget (~1.5MB)
COPY --from=builder /bin/busybox.static /bin/busybox
RUN ["/bin/busybox", "sh", "-c", "/bin/busybox --install -s /bin"]

# TLS certificates (for curl/HTTPS in WP-CLI and WordPress)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# FrankenPHP static binary (PHP 8.5 + Caddy + 70+ extensions)
COPY --from=builder /frankenphp /usr/local/bin/frankenphp

# PHP config
COPY --from=builder /etc/php/custom.ini /etc/php/custom.ini

# WP-CLI
COPY --from=builder /wp-cli.phar /usr/local/bin/wp

# WordPress
COPY --from=builder /wp /wp

# Elementor stack (immune to wp-content mounts)
COPY --from=builder /opt/elementor-stack /opt/elementor-stack

# Caddyfile
COPY --from=builder /Caddyfile /etc/caddy/Caddyfile

# Entrypoint
COPY entrypoint.sh /entrypoint.sh

# Needed by PHP/Caddy
RUN ["/bin/busybox", "sh", "-c", "mkdir -p /tmp /var/log /data/caddy /config/caddy /root"]
ENV HOME=/root
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV PHP_INI_SCAN_DIR=/etc/php
ENV PATH=/usr/local/bin:/bin

WORKDIR /wp
EXPOSE 8080
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

ARG PHP_VERSION=8.5

# ── Stage 1: Builder (has build tools, downloads everything) ───────────────────
FROM dunglas/frankenphp:1-php${PHP_VERSION}-alpine AS builder

RUN apk add --no-cache curl unzip git

RUN install-php-extensions gd intl zip opcache exif sqlite3 pdo_sqlite fileinfo

RUN echo "memory_limit=512M" > /usr/local/etc/php/conf.d/99-custom.ini && \
    curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp && chmod +x /usr/local/bin/wp && \
    wp core download --path=/wp --allow-root

RUN mkdir -p /opt/elementor-stack && \
    curl -sL -o /tmp/sqlite.zip \
      "https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip" && \
    unzip -q /tmp/sqlite.zip -d /opt/elementor-stack/ && \
    curl -sL -o /tmp/elementor.zip \
      "https://downloads.wordpress.org/plugin/elementor.latest-stable.zip" && \
    unzip -q /tmp/elementor.zip -d /opt/elementor-stack/ && \
    git clone --depth 1 https://github.com/proelements/proelements.git \
      /opt/elementor-stack/pro-elements && \
    rm -rf /opt/elementor-stack/pro-elements/.git && \
    curl -sL -o /tmp/hello.zip \
      "https://downloads.wordpress.org/theme/hello-elementor.latest-stable.zip" && \
    unzip -q /tmp/hello.zip -d /opt/elementor-stack/ && \
    rm -rf /tmp/*.zip

# ── Stage 2: Runtime (minimal, patched, no build tools) ───────────────────────
FROM dunglas/frankenphp:1-php${PHP_VERSION}-alpine

# Patch all known vulnerabilities
RUN apk upgrade --no-cache && \
    apk add --no-cache curl && \
    curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp && chmod +x /usr/local/bin/wp

# Copy PHP extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy WordPress + stack
COPY --from=builder /wp /wp
COPY --from=builder /opt/elementor-stack /opt/elementor-stack

RUN cat > /etc/caddy/Caddyfile << 'CADDY'
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

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /wp
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]

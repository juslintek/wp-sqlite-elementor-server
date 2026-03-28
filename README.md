# wp-sqlite-elementor-server

Zero-dependency WordPress + Elementor development server.

**FrankenPHP · PHP 8.5 · SQLite · Elementor · ProElements · hello-elementor**

Single container. No MySQL. No Apache. No Nginx. Ready in ~10 seconds.

## Quick Start

```bash
docker run -p 8080:8080 \
  -e WP_ADMIN_USER=admin \
  -e WP_ADMIN_PASS=admin \
  juslintek/wp-sqlite-elementor-server:latest
```

Open http://localhost:8080

## What's Inside

| Component | Details |
|---|---|
| [FrankenPHP](https://frankenphp.dev) | Caddy + PHP in one process. HTTP/2, HTTP/3, zstd/br/gzip. |
| PHP 8.5 (ZTS) | Thread-safe, OPcache enabled |
| WordPress | Latest stable |
| [SQLite Database Integration](https://wordpress.org/plugins/sqlite-database-integration/) | No MySQL/MariaDB/Postgres needed |
| [Elementor](https://wordpress.org/plugins/elementor/) | Page builder |
| [ProElements](https://github.com/proelements/proelements) | Free Elementor Pro alternative |
| [hello-elementor](https://wordpress.org/themes/hello-elementor/) | Default theme (activated on auto-setup) |

Core stack lives in `/opt/elementor-stack/` and is symlinked into `wp-content/plugins/` on every boot — immune to `wp-content` mounts.

## Tags

| Tag | PHP | Description |
|---|---|---|
| `latest` | 8.5 | Latest everything |
| `php8.5` | 8.5 | PHP 8.5 explicit |
| `php8.4` | 8.4 | PHP 8.4 stable |
| `wp6.9.4-elementor3.35.9-php8.5` | 8.5 | Pinned versions |
| `wp6.9.4-elementor3.35.9-php8.4` | 8.4 | Pinned versions |

All tags: `linux/amd64` + `linux/arm64`

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `WP_ADMIN_USER` | *(none)* | Set to enable auto-setup. Omit for manual web install. |
| `WP_ADMIN_PASS` | `admin` | Admin password |
| `WP_ADMIN_EMAIL` | `admin@test.local` | Admin email |
| `WP_TITLE` | `Elementor MCP` | Site title |
| `WP_DEBUG` | `false` | WordPress debug mode |

## Domain-Agnostic

URL is determined from the request `Host` header. Works from any domain/port without reconfiguration.

## Volumes

```bash
# Persist database + uploads
docker run -p 8080:8080 \
  -v ./data/database:/wp/wp-content/database \
  -v ./data/uploads:/wp/wp-content/uploads \
  -e WP_ADMIN_USER=admin \
  juslintek/wp-sqlite-elementor-server:latest

# Custom plugins (Elementor/ProElements still load from /opt)
docker run -p 8080:8080 \
  -v ./my-plugins:/wp/wp-content/plugins \
  -e WP_ADMIN_USER=admin \
  juslintek/wp-sqlite-elementor-server:latest
```

| Mount | Purpose |
|---|---|
| `/wp/wp-content/database` | SQLite database |
| `/wp/wp-content/uploads` | Media uploads |
| `/wp/wp-content/plugins` | Custom plugins |
| `/wp/wp-content/themes` | Custom themes |

## Docker Compose

```yaml
services:
  wordpress:
    image: juslintek/wp-sqlite-elementor-server:latest
    ports:
      - "8080:8080"
    environment:
      WP_ADMIN_USER: admin
      WP_ADMIN_PASS: admin
      WP_DEBUG: "true"
    volumes:
      - ./data/database:/wp/wp-content/database
      - ./data/uploads:/wp/wp-content/uploads
```

## Application Password

Auto-setup creates an application password at `/wp/app-password.txt`:

```bash
docker exec <container> cat /wp/app-password.txt
curl -u admin:<password> http://localhost:8080/wp-json/wp/v2/pages
```

## Security

Multi-stage build: build tools (git, unzip) are NOT in the runtime image. Only curl + WP-CLI remain for runtime operations. All Alpine packages upgraded to latest patches on build.

### Known Considerations

The Alpine base image (`dunglas/frankenphp:1-php8.5-alpine`) inherits some packages with known CVEs that may not have upstream patches yet. For maximum security:

1. **Rebuild regularly** — `docker build --no-cache` picks up latest Alpine patches
2. **Use pinned version tags** — avoid `latest` in production
3. **Mount read-only** where possible — `-v ./data:/wp/wp-content/database:ro` after setup

### Vulnerability Mitigation

| Package | Risk | Mitigation |
|---|---|---|
| `unzip` | CVE-2008-0888 | **Not in runtime image** (build stage only) |
| `tar/busybox` | Path traversal CVEs | No user-uploaded archives processed; WordPress doesn't use tar |
| `curl` | Multiple CVEs | `apk upgrade` applied; rebuild to get latest |
| `nghttp2` | CVE-2026-27135 | `apk upgrade` applied; only used for HTTP/2 client |

### Future: Static Binary Approach

FrankenPHP supports static binaries (PHP + Caddy in one file). Running on `scratch`/`distroless` would eliminate ALL OS-level CVEs. This is tracked for a future release.

## Building

```bash
# Local
docker build -t wp-sqlite-elementor-server .

# Multi-arch + push
docker buildx build --platform linux/amd64,linux/arm64 \
  -t juslintek/wp-sqlite-elementor-server:latest --push .

# Different PHP version
docker build --build-arg PHP_VERSION=8.4 -t wp-sqlite-elementor-server:php8.4 .
```

## Architecture

```
FrankenPHP (Caddy + PHP 8.5 ZTS)
  ├── HTTP/2, HTTP/3, zstd/br/gzip
  ├── OPcache, worker-ready
  └── Serves :8080

/wp/                              WordPress root
├── wp-config.php                 Auto-generated, domain-agnostic, SQLite
└── wp-content/
    ├── database/.ht.sqlite       SQLite database (mountable)
    ├── uploads/                  Media (mountable)
    ├── plugins/                  User plugins + symlinks to /opt
    ├── themes/                   User themes + symlink to /opt
    ├── db.php                    SQLite drop-in (auto-created)
    └── mu-plugins/               REST API config (recreated on boot)

/opt/elementor-stack/             Baked into image, immune to mounts
├── sqlite-database-integration/
├── elementor/
├── pro-elements/
└── hello-elementor/
```

## License

BSL-1.1 — free to use for any purpose. Cannot be resold as a separate product without commercial license.

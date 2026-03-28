#!/bin/sh
set -e

WP_DIR="/wp"
STACK="/opt/elementor-stack"
cd "$WP_DIR"

# ── 1. Ensure directories ─────────────────────────────────────────────────────

mkdir -p wp-content/mu-plugins wp-content/database wp-content/uploads wp-content/plugins wp-content/themes

# ── 2. Symlink stack plugins from /opt into plugins dir (survives mounts) ─────
#    Recreated every boot so wp-content mounts don't break them.

for plugin in elementor pro-elements sqlite-database-integration; do
  target="wp-content/plugins/$plugin"
  rm -rf "$target" 2>/dev/null || true
  ln -sf "$STACK/$plugin" "$target"
done

# Symlink hello-elementor theme
if [ ! -d wp-content/themes/hello-elementor ] && [ ! -L wp-content/themes/hello-elementor ]; then
  ln -sf "$STACK/hello-elementor" wp-content/themes/hello-elementor
fi

# ── 3. SQLite db.php drop-in ──────────────────────────────────────────────────

if [ ! -f wp-content/db.php ]; then
  sed "s|{SQLITE_IMPLEMENTATION_FOLDER_PATH}|$STACK/sqlite-database-integration|g" \
    "$STACK/sqlite-database-integration/db.copy" > wp-content/db.php
fi

# ── 4. mu-plugin: REST API meta + domain-agnostic + app passwords ─────────────

cat > wp-content/mu-plugins/elementor-mcp-config.php << 'CONFIG'
<?php
add_action('init', function() {
    foreach (['_elementor_data', '_elementor_edit_mode', '_elementor_template_type', '_elementor_version'] as $key) {
        register_post_meta('page', $key, [
            'show_in_rest' => true,
            'single' => true,
            'type' => 'string',
            'auth_callback' => function() { return current_user_can('edit_posts'); }
        ]);
    }
});
add_filter('wp_is_application_passwords_available', '__return_true');
CONFIG

# ── 5. wp-config.php (domain-agnostic, SQLite) ────────────────────────────────

if [ ! -f wp-config.php ]; then
  cat > wp-config.php << 'WPEOF'
<?php
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? getenv('WP_DOMAIN') ?: 'localhost:8080';
define('WP_HOME', "$scheme://$host");
define('WP_SITEURL', "$scheme://$host");

define('DB_DIR', __DIR__ . '/wp-content/database/');
define('DB_FILE', '.ht.sqlite');

define('AUTH_KEY',         getenv('WP_AUTH_KEY')         ?: 'emcp-k1');
define('SECURE_AUTH_KEY',  getenv('WP_SECURE_AUTH_KEY')  ?: 'emcp-k2');
define('LOGGED_IN_KEY',    getenv('WP_LOGGED_IN_KEY')    ?: 'emcp-k3');
define('NONCE_KEY',        getenv('WP_NONCE_KEY')        ?: 'emcp-k4');
define('AUTH_SALT',        getenv('WP_AUTH_SALT')        ?: 'emcp-s1');
define('SECURE_AUTH_SALT', getenv('WP_SECURE_AUTH_SALT') ?: 'emcp-s2');
define('LOGGED_IN_SALT',   getenv('WP_LOGGED_IN_SALT')   ?: 'emcp-s3');
define('NONCE_SALT',       getenv('WP_NONCE_SALT')       ?: 'emcp-s4');

$table_prefix = getenv('WP_TABLE_PREFIX') ?: 'wp_';
define('WP_DEBUG', filter_var(getenv('WP_DEBUG') ?: 'false', FILTER_VALIDATE_BOOLEAN));
define('WP_DEBUG_LOG', WP_DEBUG);

if (!defined('ABSPATH')) define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
WPEOF
fi

# ── 6. Auto-setup ─────────────────────────────────────────────────────────────

if ! wp core is-installed --allow-root 2>/dev/null; then
  if [ -n "${WP_ADMIN_USER:-}" ]; then
    echo "=== Auto-installing WordPress ==="
    wp core install \
      --url="http://localhost:8080" \
      --title="${WP_TITLE:-Elementor MCP}" \
      --admin_user="${WP_ADMIN_USER}" \
      --admin_password="${WP_ADMIN_PASS:-admin}" \
      --admin_email="${WP_ADMIN_EMAIL:-admin@test.local}" \
      --skip-email \
      --allow-root

    wp plugin activate elementor --allow-root 2>/dev/null || true
    wp plugin activate pro-elements --allow-root 2>/dev/null || true
    wp theme activate hello-elementor --allow-root 2>/dev/null || true

    for t in twentytwentyfive twentytwentyfour twentytwentythree twentytwentytwo twentytwentyone twentytwenty; do
      wp theme delete "$t" --allow-root 2>/dev/null || true
    done

    wp rewrite structure '/%postname%/' --allow-root 2>/dev/null || true

    if [ ! -f /wp/app-password.txt ]; then
      APP_PASS=$(wp user application-password create "${WP_ADMIN_USER}" "elementor-mcp" --porcelain --allow-root 2>/dev/null || echo "")
      [ -n "$APP_PASS" ] && echo "$APP_PASS" > /wp/app-password.txt
    fi

    echo "=== Setup complete ==="
  else
    echo "=== WordPress not installed — visit http://localhost:8080 or set WP_ADMIN_USER ==="
  fi
fi

# ── 7. Start FrankenPHP ────────────────────────────────────────────────────────

echo "=== FrankenPHP (Caddy + PHP $(php -r 'echo PHP_VERSION;')) on :8080 ==="
exec frankenphp run --config /etc/caddy/Caddyfile

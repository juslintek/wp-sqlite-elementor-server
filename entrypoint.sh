#!/bin/sh
set -e

STACK="/opt/elementor-stack"
cd /wp

# WP-CLI wrapper (uses FrankenPHP's PHP)
wp() { PHP_INI_SCAN_DIR=/etc/php frankenphp php-cli /usr/local/bin/wp --allow-root "$@"; }

# ── 1. Directories + symlinks ─────────────────────────────────────────────────

mkdir -p wp-content/mu-plugins wp-content/database wp-content/uploads wp-content/plugins wp-content/themes

for p in elementor pro-elements sqlite-database-integration; do
  rm -f "wp-content/plugins/$p"
  ln -sf "$STACK/$p" "wp-content/plugins/$p"
done

[ -e wp-content/themes/hello-elementor ] || ln -sf "$STACK/hello-elementor" wp-content/themes/hello-elementor

# ── 2. SQLite drop-in ─────────────────────────────────────────────────────────

[ -f wp-content/db.php ] || \
  sed "s|{SQLITE_IMPLEMENTATION_FOLDER_PATH}|$STACK/sqlite-database-integration|g" \
    "$STACK/sqlite-database-integration/db.copy" > wp-content/db.php

# ── 3. mu-plugin ──────────────────────────────────────────────────────────────

cat > wp-content/mu-plugins/config.php << 'PHP'
<?php
add_action('init', function() {
    foreach (['_elementor_data','_elementor_edit_mode','_elementor_template_type','_elementor_version'] as $k)
        register_post_meta('page', $k, ['show_in_rest'=>true,'single'=>true,'type'=>'string',
            'auth_callback'=>function(){return current_user_can('edit_posts');}]);
});
add_filter('wp_is_application_passwords_available', '__return_true');
PHP

# ── 4. wp-config.php ──────────────────────────────────────────────────────────

[ -f wp-config.php ] || cat > wp-config.php << 'WPEOF'
<?php
$s = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$h = $_SERVER['HTTP_HOST'] ?? getenv('WP_DOMAIN') ?: 'localhost:8080';
define('WP_HOME', "$s://$h"); define('WP_SITEURL', "$s://$h");
define('DB_DIR', __DIR__.'/wp-content/database/'); define('DB_FILE', '.ht.sqlite');
define('AUTH_KEY',getenv('WP_AUTH_KEY')?:'k1'); define('SECURE_AUTH_KEY',getenv('WP_SECURE_AUTH_KEY')?:'k2');
define('LOGGED_IN_KEY',getenv('WP_LOGGED_IN_KEY')?:'k3'); define('NONCE_KEY',getenv('WP_NONCE_KEY')?:'k4');
define('AUTH_SALT',getenv('WP_AUTH_SALT')?:'s1'); define('SECURE_AUTH_SALT',getenv('WP_SECURE_AUTH_SALT')?:'s2');
define('LOGGED_IN_SALT',getenv('WP_LOGGED_IN_SALT')?:'s3'); define('NONCE_SALT',getenv('WP_NONCE_SALT')?:'s4');
$table_prefix = getenv('WP_TABLE_PREFIX') ?: 'wp_';
define('WP_DEBUG', filter_var(getenv('WP_DEBUG')?:'false', FILTER_VALIDATE_BOOLEAN));
define('WP_DEBUG_LOG', WP_DEBUG);
if (!defined('ABSPATH')) define('ABSPATH', __DIR__.'/');
require_once ABSPATH.'wp-settings.php';
WPEOF

# ── 5. Auto-setup ─────────────────────────────────────────────────────────────

if ! wp core is-installed 2>/dev/null; then
  if [ -n "${WP_ADMIN_USER:-}" ]; then
    echo "=== Installing WordPress ==="
    wp core install \
      --url="http://localhost:8080" \
      --title="${WP_TITLE:-WordPress}" \
      --admin_user="$WP_ADMIN_USER" \
      --admin_password="${WP_ADMIN_PASS:-admin}" \
      --admin_email="${WP_ADMIN_EMAIL:-admin@test.local}" \
      --skip-email

    wp plugin activate sqlite-database-integration 2>/dev/null || true
    wp plugin activate elementor 2>/dev/null || true
    wp plugin activate pro-elements 2>/dev/null || true
    wp theme activate hello-elementor 2>/dev/null || true

    for t in twentytwentyfive twentytwentyfour twentytwentythree twentytwentytwo twentytwentyone twentytwenty; do
      wp theme delete "$t" 2>/dev/null || true
    done

    wp rewrite structure '/%postname%/' 2>/dev/null || true

    [ -f /wp/app-password.txt ] || {
      P=$(wp user application-password create "$WP_ADMIN_USER" "mcp" --porcelain)
      [ -n "$P" ] && echo "$P" > /wp/app-password.txt
    }
    echo "=== Ready ==="
  else
    echo "=== Visit http://localhost:8080 to install, or set WP_ADMIN_USER ==="
  fi
fi

# ── 6. FrankenPHP ─────────────────────────────────────────────────────────────

exec frankenphp run --config /etc/caddy/Caddyfile

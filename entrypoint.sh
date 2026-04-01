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

// Create ProElements tables that are normally created via editor visit
add_action('init', function() {
    global $wpdb;
    $wpdb->suppress_errors(true);
    $charset = $wpdb->get_charset_collate();
    $wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->prefix}e_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id bigint(20) NOT NULL DEFAULT 0,
        element_id varchar(60) NOT NULL DEFAULT '',
        content longtext NOT NULL DEFAULT '',
        author_id bigint(20) NOT NULL DEFAULT 0,
        created_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        updated_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        parent_id bigint(20) NOT NULL DEFAULT 0,
        status varchar(20) NOT NULL DEFAULT 'publish',
        route_url varchar(2083) NOT NULL DEFAULT '',
        route_title varchar(255) NOT NULL DEFAULT '',
        is_resolved tinyint(1) NOT NULL DEFAULT 0,
        resolved_by bigint(20) NOT NULL DEFAULT 0,
        resolved_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        last_activity_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
    )");
    $wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->prefix}e_submissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type varchar(60) NOT NULL DEFAULT '',
        hash_id varchar(60) NOT NULL DEFAULT '',
        main_meta_id bigint(20) NOT NULL DEFAULT 0,
        post_id bigint(20) NOT NULL DEFAULT 0,
        referer varchar(500) NOT NULL DEFAULT '',
        referer_title varchar(300) NOT NULL DEFAULT '',
        element_id varchar(60) NOT NULL DEFAULT '',
        form_name varchar(60) NOT NULL DEFAULT '',
        campaign_id bigint(20) NOT NULL DEFAULT 0,
        created_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        updated_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        created_at_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        updated_at_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        user_id bigint(20) NOT NULL DEFAULT 0,
        user_ip varchar(46) NOT NULL DEFAULT '',
        user_agent text NOT NULL DEFAULT '',
        actions_count int(11) NOT NULL DEFAULT 0,
        actions_succeeded_count int(11) NOT NULL DEFAULT 0,
        status varchar(20) NOT NULL DEFAULT '',
        is_read tinyint(1) NOT NULL DEFAULT 0
    )");
    $wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->prefix}e_submissions_values (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        submission_id bigint(20) NOT NULL DEFAULT 0,
        key varchar(60) NOT NULL DEFAULT '',
        value longtext NOT NULL DEFAULT ''
    )");
    $wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->prefix}e_submissions_actions_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        submission_id bigint(20) NOT NULL DEFAULT 0,
        action_name varchar(60) NOT NULL DEFAULT '',
        action_label varchar(60) NOT NULL DEFAULT '',
        status varchar(20) NOT NULL DEFAULT '',
        log text NOT NULL DEFAULT '',
        created_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        updated_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        created_at_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        updated_at_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
    )");
    $wpdb->suppress_errors(false);
}, 1);
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

    # Create default navigation menu
    wp menu create "Main Menu" 2>/dev/null || true
    wp menu item add-custom "Main Menu" "Home" "/" 2>/dev/null
    wp menu item add-custom "Main Menu" "About" "/about" 2>/dev/null
    wp menu item add-custom "Main Menu" "Features" "/features" 2>/dev/null
    wp menu item add-custom "Main Menu" "Contact" "/contact" 2>/dev/null
    wp menu location assign "Main Menu" primary 2>/dev/null || true

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

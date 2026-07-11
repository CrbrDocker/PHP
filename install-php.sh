#! /bin/bash
#
# Script to install an Apache / PHP server on the crbr Debian base.
# The PHP version is parameterized via $PHP_VERSION (e.g. 8.3, 8.4, 8.5) and the
# Debian codename for the sury repo is read from the base image's os-release,
# so this single script serves every version/codename combination.


# PHP version to install (default 8.3 for backward compat)
PHP_VERSION="${PHP_VERSION:-8.3}"


# APT
# sury repo, per Debian codename, with a verified signing key (instead of the
# old trusted=yes / allow-insecure).
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
cat > /etc/apt/sources.list.d/php-sury.list <<EOF
# PHP recent
deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${codename} main
EOF

# env var so APT knows we won't answer any of its prompts
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

apt -y update

apt-get -y dist-upgrade

# Installation apache & modules
apt-get -y --no-install-recommends install apache2 openssl libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-apcu php${PHP_VERSION}-bcmath php${PHP_VERSION}-bz2 php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-dba php${PHP_VERSION}-gd php${PHP_VERSION}-grpc php${PHP_VERSION}-igbinary php${PHP_VERSION}-imagick php${PHP_VERSION}-ldap php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcached php${PHP_VERSION}-memcache php${PHP_VERSION}-msgpack php${PHP_VERSION}-mysql php${PHP_VERSION}-odbc php${PHP_VERSION}-opcache php${PHP_VERSION}-readline php${PHP_VERSION}-redis php${PHP_VERSION}-soap php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-sybase php${PHP_VERSION}-tidy php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip php-common

# While we're at it, composer too ... (it needs php8.3-intl, otherwise it pulls php8.4-intl & php8.4-common...)
apt-get -y --no-install-recommends install php${PHP_VERSION}-intl composer


# APT cache cleanup
apt-get clean
apt-get autoclean

# Clean APT lists (~90 MB) and the archive cache (likewise)
# An apt-get update will be needed before next use
rm -rf /var/lib/apt/lists/* 2>/dev/null
rm -rf /var/cache/apt/*pkgcache.bin 2>/dev/null

# The directories
mkdir -p /srv/log /srv/www /srv/www/default/public
mv /var/log/apache2 /srv/log && ln -s /srv/log/apache2 /var/log
echo coucou > /srv/www/default/public/index.php




# Log file management.
# (Not really needed on docker where logrotate doesn't run)
cat > /etc/logrotate.d/apache2 <<EOF
/var/log/apache2/*.log {
	daily
	missingok
	rotate 14
	compress
	delaycompress
	notifempty
	create 644 root adm
	sharedscripts
	prerotate
		if [ -d /etc/logrotate.d/httpd-prerotate ]; then
			run-parts /etc/logrotate.d/httpd-prerotate
		fi
	endscript
	postrotate
		if pgrep -f ^/usr/sbin/apache2 > /dev/null; then
			invoke-rc.d apache2 reload 2>&1 | logger -t apache2.logrotate
		fi
	endscript
}

EOF




# Environment variables
cat > /etc/environment <<EOF
#TZ=Europe/Paris

EOF

cat >> /etc/apache2/envvars <<EOF

### Env Vars - Because Apache does not use /etc/environment...

### DOn't care here.

### Log targets: stdout/stderr by default; the entrypoint repoints these at
### /srv/log/apache2 when APACHE_LOG_TO_FILE=1.
export APACHE_ACCESS_LOG="\${APACHE_ACCESS_LOG:-/proc/self/fd/1}"
export APACHE_ERROR_LOG="\${APACHE_ERROR_LOG:-/proc/self/fd/2}"

EOF

# PHP config:
for fichier in /etc/php/${PHP_VERSION}/apache2/php.ini /etc/php/${PHP_VERSION}/cli/php.ini ; do
  sed -i -e "s/^variables_order.*/variables_order = \"EGPCS\"/" $fichier
  #sed -i -e "s/^;date\.timezone.*/date.timezone = Europe\/Paris/" $fichier
  sed -i -e "s/^;date\.timezone.*/date.timezone = UTC/" $fichier
  sed -i -e "s/^expose_php.*/expose_php = Off/" $fichier
  sed -i -e "s/^post_max_size.*/post_max_size = 80M/" $fichier
  sed -i -e "s/^upload_max_filesize.*/upload_max_filesize = 20M/" $fichier
  #sed -i -e "s/^session\.use_only_cookies.*/session.use_only_cookies = 0/" $fichier

  # There would be things to set up for memcache-backed sessions but for a dev box we'll skip it
  # And for the rest, display errors & co, the debian default is fine for now
done



# apache config

## SSL config
## The self-signed dev cert is NOT baked into the image (no private key in the
## repo). crbr-generate-cert.sh creates one at container start into
## /etc/apache2/ssl unless a cert is already there -- mount your own to override.
mkdir /etc/apache2/ssl

cat > /usr/local/bin/crbr-generate-cert.sh <<'CERTEOF'
#!/bin/bash
#
# crbr-generate-cert.sh
#
# Generate a self-signed dev certificate for the default vhosts, unless one is
# already present at /etc/apache2/ssl/dev.crt (mounted by the user, or made on a
# previous start). Idempotent: it never overwrites an existing cert/key.
#
# The SANs match the vhost_alias ServerAlias set so the cert covers every dev
# hostname the image serves.
set -u

CRT=/etc/apache2/ssl/dev.crt
KEY=/etc/apache2/ssl/dev.key

if [ -s "$CRT" ] && [ -s "$KEY" ]; then
  echo "dev-cert: keeping existing ${CRT}"
  exit 0
fi

mkdir -p /etc/apache2/ssl
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CRT" -days 3650 \
  -subj "/CN=dev" \
  -addext "subjectAltName=DNS:localhost,DNS:dev,DNS:*.dev,DNS:test,DNS:*.test,DNS:local,DNS:*.local,DNS:docker,DNS:*.docker" \
  >/dev/null 2>&1

chmod 600 "$KEY"
chmod 644 "$CRT"
echo "dev-cert: generated self-signed certificate at ${CRT}"
CERTEOF
chmod 755 /usr/local/bin/crbr-generate-cert.sh

## The base config (note: concurrency & co greatly reduced vs the standard)
cat > /etc/apache2/conf-available/crbr.conf<<EOF

### Base config, number of threads & co

ServerAdmin hostmaster@myserver.net

HostnameLookups off

Timeout                 120
KeepAlive               On
MaxKeepAliveRequests    50
KeepAliveTimeout        1

# Number of procs & co adjusted for dev docker.
<IfModule mpm_prefork_module>
    StartServers         2
    MinSpareServers      2
    MaxSpareServers      5
    ServerLimit         50
    MaxClients          50
    MaxRequestsPerChild 20
</IfModule>


### Sharing SSL sessions in Memcache for load-balanced servers
# Override the default conf in ssl.conf (shared memory on the server)
<IfModule mod_socache_memcache.c>
    SSLSessionCache memcache:memcached-session:11211
</IfModule>


### SSL Security
# CF https://ssl-config.mozilla.org/
<IfModule mod_ssl.c>
    SSLProtocol             all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA256:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA
    SSLHonorCipherOrder     on
    SSLSessionTickets       off

   # Notes: deliberately left out the OCSP stapling options. They don't work well with an intermediate certificate
</IfModule>


### Log directives
LogLevel warn
# Error log target: stdout/stderr by default, or /srv/log/apache2 when APACHE_LOG_TO_FILE=1
# (both resolved by the entrypoint / envvars into ${APACHE_ERROR_LOG}).
ErrorLog "\${APACHE_ERROR_LOG}"

<IfModule !mod_remoteip.c>
    # If we haven't configured mod_remote_ip & cloudflare
    # We keep the old conf

    # Log Format Normal
    LogFormat "%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %V %D %I %O" vcombined

    # Log format for SOAP requests (replaces the referer with the soap action)
    LogFormat "%v:%p %h %l %u %t \"%r\" %>s %b \"%{SOAPAction}i\" \"%{User-Agent}i\" %V %D %I %O" vcombinedsoap

    # Log format for lines with GDPR crap in the GET request that we need to not log...
    LogFormat "%v:%p %h %l %u %t \"%m %U HTTP/1.1\" %>s %b \"-\" \"%{User-Agent}i\" %V %D %I %O" vcombinednoquerystring
</IfModule>
<IfModule mod_remoteip.c>
    # Cloudflare real-IP trust (RemoteIPHeader + RemoteIPInternalProxy) lives in
    # conf-available/cloudflare-ips.conf, seeded at build time and refreshed at
    # container start by crbr-update-cloudflare-ips.sh (baked fallback if offline).
    # mod_remoteip only honours CF-Connecting-IP when the peer is a trusted proxy;
    # otherwise the real connection IP is kept.

    # Log Format Normal
    LogFormat "%v:%p %a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %V %D %I %O" vcombined

    # Log format for SOAP requests (replaces the referer with the soap action)
    LogFormat "%v:%p %a %l %u %t \"%r\" %>s %b \"%{SOAPAction}i\" \"%{User-Agent}i\" %V %D %I %O" vcombinedsoap

    # Log format for lines with GDPR crap in the GET request that we need to not log...
    LogFormat "%v:%p %a %l %u %t \"%m %U?CENSORED HTTP/1.1\" %>s %b \"-\" \"%{User-Agent}i\" %V %D %I %O" vcombinednoquerystring
</IfModule>

SetEnvIf SOAPAction "^$" notsoapaction

# Normal log if it not SOAP and we dont ask to remove the query string parameters
CustomLog "\${APACHE_ACCESS_LOG}" vcombined expr=(reqenv('notsoapaction')=='yes'&&reqenv('removequerystring')!='yes')

# If we are not a SOAP action and we asked to remove the query string parameters with a SetEnvIf SOMETHING removequerystring=yes
CustomLog "\${APACHE_ACCESS_LOG}" vcombinednoquerystring expr=(reqenv('notsoapaction')=='yes'&&reqenv('removequerystring')=='yes')

# If we are a soap action
CustomLog "\${APACHE_ACCESS_LOG}" vcombinedsoap expr=(reqenv('notsoapaction')!='yes')


### Security
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<Directory />
  Options FollowSymlinks
  AllowOverride None
  Require all denied
</Directory>

<IfModule mod_headers.c>
  Header setifempty Referrer-Policy "no-referrer, strict-origin-when-cross-origin"
  Header setifempty X-Content-Type-Options "nosniff"
</IfModule>


### Override mod status default conf
<IfModule mod_status.c>
    <Location /server-status>
        # Disable it globaly. it will be allowed only in the right vhost.
        SetHandler None
        Require all denied
    </Location>
    ExtendedStatus On
    #SeeRequestTail On
    <IfModule mod_proxy.c>
        ProxyStatus On
    </IfModule>
</IfModule>


### Override mod ldap default conf
<Location /ldap-status>
    # Disable it globaly. it will be allowed only in the right vhost.
    SetHandler None
    Require all denied
</Location>


### Override mod_proxy default conf
<IfModule mod_proxy.c>
    ProxyRequests Off
    <Proxy *>
        AddDefaultCharset off
        Require all denied
    </Proxy>
    ProxyVia Off

    # This one isn't set by ProxyAddHeaders
    #  If we have nothing, we set it ourselves, http as http and https as https
    SetEnvIfNoCase ^CloudFront-Forwarded-Proto$ (.+) CloudFront=$1
    RequestHeader setifempty X-Forwarded-Proto %{CloudFront}e env=CloudFront
    RequestHeader setifempty X-Forwarded-Proto expr=%{REQUEST_SCHEME} env=!CloudFront

</IfModule>
EOF

#sed -i -e "s/^ServerSignature.*/ServerSignature Off/" /etc/apache2/conf-available/security.conf
#sed -i -e "s/^ServerTokens.*/ServerTokens Prod/" /etc/apache2/conf-available/security.conf
# Replaced by a2disconf security and the rest in crbr.conf

## Modules
a2dismod access_compat
a2enmod authnz_ldap headers ldap proxy_http remoteip rewrite ssl vhost_alias


## enable / disable confs
a2disconf security
a2disconf other-vhosts-access-log
a2disconf charset
a2disconf localized-error-pages
a2disconf serve-cgi-bin
a2enconf crbr


## Cloudflare trusted-proxy list for mod_remoteip.
## The script below regenerates conf-available/cloudflare-ips.conf from the live
## Cloudflare ranges (with a baked fallback). We seed it now at build time and
## call it again at container start from the entrypoint.
cat > /usr/local/bin/crbr-update-cloudflare-ips.sh <<'CFEOF'
#!/bin/bash
#
# crbr-update-cloudflare-ips.sh
#
# (Re)generate the Cloudflare trusted-proxy list for mod_remoteip. Run once at
# image build to seed the config, then again at container start (from
# docker-php-entrypoint) so a changed Cloudflare range is picked up automatically.
#
# It fetches cloudflare.com/ips-v4 + ips-v6; if that fails or returns something
# that does not look like CIDRs, it falls back to the baked list below, so the
# trusted list is never emptied.
#
# TRUST_PRIVATE_PROXIES=1 additionally trusts RFC1918 ranges (10/8, 172.16/12,
# 192.168/16) -- needed when Apache sits behind a private-IP reverse proxy / LB
# that forwards CF-Connecting-IP. Leave unset/0 for a direct Cloudflare -> Apache
# setup (trusting private ranges lets anything on those networks spoof the client
# IP if it can reach Apache directly).
set -u

CONF=/etc/apache2/conf-available/cloudflare-ips.conf

# Baked fallback: Cloudflare's published ranges as of image build.
FALLBACK="$(cat <<'IPS'
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22
2400:cb00::/32
2606:4700::/32
2803:f800::/32
2405:b500::/32
2405:8100::/32
2a06:98c0::/29
2c0f:f248::/32
IPS
)"

fetch() { curl -fsS --max-time 5 "$1" 2>/dev/null; }
live="$(printf '%s\n%s\n' "$(fetch https://www.cloudflare.com/ips-v4)" "$(fetch https://www.cloudflare.com/ips-v6)" | grep -E '^[0-9a-fA-F:.]+/[0-9]+$')"

if [ -n "$live" ]; then
  ips="$live"; src="live cloudflare.com"
else
  ips="$(printf '%s\n' "$FALLBACK" | grep -E '^[0-9a-fA-F:.]+/[0-9]+$')"; src="baked fallback (fetch failed)"
fi

tmp="$(mktemp)"
{
  echo "# Cloudflare trusted proxies for mod_remoteip -- source: ${src}."
  echo "# (Re)generated by crbr-update-cloudflare-ips.sh; do not edit by hand."
  echo "<IfModule mod_remoteip.c>"
  echo "    RemoteIPHeader CF-Connecting-IP"
  printf '%s\n' "$ips" | sed 's/^/    RemoteIPInternalProxy /'
  if [ "${TRUST_PRIVATE_PROXIES:-0}" = "1" ]; then
    echo "    # TRUST_PRIVATE_PROXIES=1: also trust RFC1918 reverse proxies / LBs"
    echo "    RemoteIPInternalProxy 10.0.0.0/8"
    echo "    RemoteIPInternalProxy 172.16.0.0/12"
    echo "    RemoteIPInternalProxy 192.168.0.0/16"
  fi
  echo "</IfModule>"
} > "$tmp" && mv "$tmp" "$CONF"

echo "cloudflare-ips: ${src}, TRUST_PRIVATE_PROXIES=${TRUST_PRIVATE_PROXIES:-0}"
CFEOF
chmod 755 /usr/local/bin/crbr-update-cloudflare-ips.sh
crbr-update-cloudflare-ips.sh
a2enconf cloudflare-ips


## "default" site
a2dissite 000-default

cat > /etc/apache2/sites-available/000-crbr-default.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    ServerAlias 127.0.0.1 ::1

    # Disable Error logs for all 403.
    LogLevel Emerg

    DocumentRoot /srv/www/default/public/
    <Directory /srv/www/default/public>
        Require local
        Require ip 10.0.0.0/8
        Require ip 192.168.0.0/16
        Require ip 172.16.0.0/12
    </Directory>

    #RewriteEngine On
    #RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME} !-f
    #RewriteRule ^.*$ /index.html [qsa,L]

    # Override mod status default conf (allow internal)
    <IfModule mod_status.c>
        <Location /server-status>
            SetHandler server-status
            Require local
            Require ip 10.0.0.0/8
            Require ip 192.168.0.0/16
            Require ip 172.16.0.0/12
        </Location>
    </IfModule>

    # Override mod ldap default conf (allow internal)
    <IfModule mod_authnz_ldap.c>
        <Location /ldap-status>
            SetHandler ldap-status
            Require local
            Require ip 10.0.0.0/8
            Require ip 192.168.0.0/16
            Require ip 172.16.0.0/12
        </Location>
    </IfModule>

</VirtualHost>


<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName localhost
        ServerAlias 127.0.0.1 ::1

        SSLEngine on
        SSLCertificateFile ssl/dev.crt
        SSLCertificateKeyFile ssl/dev.key

        # Disable Error logs for all 403.
        LogLevel Emerg

        DocumentRoot /srv/www/default/public/
        <Directory /srv/www/default/public>
            Require local
            Require ip 10.0.0.0/8
            Require ip 192.168.0.0/16
            Require ip 172.16.0.0/12
        </Directory>

        #RewriteEngine On
        #RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME} !-f
        #RewriteRule ^.*$ /index.html [qsa,L]

        # Override mod status default conf (allow internal)
        <IfModule mod_status.c>
            <Location /server-status>
                SetHandler server-status
                Require local
                Require ip 10.0.0.0/8
                Require ip 192.168.0.0/16
                Require ip 172.16.0.0/12
            </Location>
        </IfModule>

        # Override mod ldap default conf (allow internal)
        <IfModule mod_authnz_ldap.c>
            <Location /ldap-status>
                SetHandler ldap-status
                Require local
                Require ip 10.0.0.0/8
                Require ip 192.168.0.0/16
                Require ip 172.16.0.0/12
            </Location>
        </IfModule>

    </VirtualHost>
</IfModule>

EOF
a2ensite 000-crbr-default

# Create a default one with vhost_alias, but they can override it as needed by overwriting the /etc/apache2/sites-enabled directory
cat > /etc/apache2/sites-available/dev.conf <<EOF
<VirtualHost *:80>
    ServerName dev
    ServerAlias *.dev test *.test local *.local docker *.docker

    VirtualDocumentRoot /srv/www/%0/public

    DocumentRoot /srv/www/
    <Directory /srv/www/>
        Require all granted
        AllowOverride All
    </Directory>
</VirtualHost>

<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName dev
        ServerAlias *.dev test *.test local *.local docker *.docker

        SSLEngine on
        SSLCertificateFile ssl/dev.crt
        SSLCertificateKeyFile ssl/dev.key

        VirtualDocumentRoot /srv/www/%0/public

        <Directory /srv/www/*>
            Require all granted
            AllowOverride All
        </Directory>


    </VirtualHost>
</IfModule>

EOF
a2ensite dev-docker


## Note: no IP/access filtering concept HERE => nothing about it in the conf and no /etc/apache2/access on this machine.



# The docker bit, to make it launch apache at startup
# (lifted from the official image, with an added log purge at startup)


cat > /usr/local/bin/docker-php-entrypoint << 'EOF'
#!/bin/sh
set -e


# Logs go to the container's stdout/stderr by default (see envvars). Set
# APACHE_LOG_TO_FILE=1 to write to files under /srv/log/apache2 instead.
if [ "${APACHE_LOG_TO_FILE:-0}" = "1" ]; then
	export APACHE_ACCESS_LOG=/srv/log/apache2/access.log
	export APACHE_ERROR_LOG=/srv/log/apache2/error.log
	mkdir -p /srv/log/apache2
	rm -f /srv/log/apache2/*.log 2>/dev/null || true
	touch "$APACHE_ACCESS_LOG" "$APACHE_ERROR_LOG"
	chown www-data: "$APACHE_ACCESS_LOG" "$APACHE_ERROR_LOG"
fi

# Suppress annoying warning at startup
echo "ServerName $(hostname)" > /etc/apache2/conf-enabled/servername.conf

# Generate the self-signed dev cert if none is present (mount your own to override)
crbr-generate-cert.sh || true

# Refresh the Cloudflare trusted-proxy list (keeps the baked list if offline)
crbr-update-cloudflare-ips.sh || true


# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- apache2-foreground "$@"
fi

exec "$@"
EOF
chmod 755 /usr/local/bin/docker-php-entrypoint


cat > /usr/local/bin/apache2-foreground << 'EOF'
#!/bin/bash
set -e

# Note: we don't just use "apache2ctl" here because it itself is just a shell-script wrapper around apache2 which provides extra functionality like "apache2ctl start" for launching apache2 in the background.
# (also, when run as "apache2ctl <apache args>", it does not use "exec", which leaves an undesirable resident shell process)

: "${APACHE_CONFDIR:=/etc/apache2}"
: "${APACHE_ENVVARS:=$APACHE_CONFDIR/envvars}"
if test -f "$APACHE_ENVVARS"; then
	. "$APACHE_ENVVARS"
fi

# Apache gets grumpy about PID files pre-existing
: "${APACHE_RUN_DIR:=/var/run/apache2}"
: "${APACHE_PID_FILE:=$APACHE_RUN_DIR/apache2.pid}"
rm -f "$APACHE_PID_FILE"

# create missing directories
# (especially APACHE_RUN_DIR, APACHE_LOCK_DIR, and APACHE_LOG_DIR)
for e in "${!APACHE_@}"; do
	if [[ "$e" == *_DIR ]] && [[ "${!e}" == /* ]]; then
		# handle "/var/lock" being a symlink to "/run/lock", but "/run/lock" not existing beforehand, so "/var/lock/something" fails to mkdir
		#   mkdir: cannot create directory '/var/lock': File exists
		dir="${!e}"
		while [ "$dir" != "$(dirname "$dir")" ]; do
			dir="$(dirname "$dir")"
			if [ -d "$dir" ]; then
				break
			fi
			absDir="$(readlink -f "$dir" 2>/dev/null || :)"
			if [ -n "$absDir" ]; then
				mkdir -p "$absDir"
			fi
		done

		mkdir -p "${!e}"
	fi
done

exec apache2 -DFOREGROUND "$@"
EOF
chmod 755 /usr/local/bin/apache2-foreground



# Clean junk before sealing the image
rm -rf /tmp/* /var/tmp/* 2> /dev/null
find /var/log -type f -delete
find /srv/log -type f -delete

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

# env var pour que APT sache qu'on ne va pas lui repondre
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

apt -y update

apt-get -y dist-upgrade

# Installation apache & modules
apt-get -y --no-install-recommends install apache2 libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-apcu php${PHP_VERSION}-bcmath php${PHP_VERSION}-bz2 php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-dba php${PHP_VERSION}-gd php${PHP_VERSION}-grpc php${PHP_VERSION}-igbinary php${PHP_VERSION}-imagick php${PHP_VERSION}-ldap php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcached php${PHP_VERSION}-memcache php${PHP_VERSION}-msgpack php${PHP_VERSION}-mysql php${PHP_VERSION}-odbc php${PHP_VERSION}-opcache php${PHP_VERSION}-readline php${PHP_VERSION}-redis php${PHP_VERSION}-soap php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-sybase php${PHP_VERSION}-tidy php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip php-common

# Tant qu'on est y est composer aussi ... (et il lui faut php8.3-intl, sinon il met php8.4-intl & php8.4-common...)
apt-get -y --no-install-recommends install php${PHP_VERSION}-intl composer


# Nettoyage du cache APT
apt-get clean
apt-get autoclean

# Nettoyage liste APT (90 Mo) et cache archives (idem)
# Il faudra faire un apt-get update avant prochain usage
rm -rf /var/lib/apt/lists/* 2>/dev/null
rm -rf /var/cache/apt/*pkgcache.bin 2>/dev/null

# Les repertoires
mkdir -p /srv/log /srv/www /srv/www/default/public
mv /var/log/apache2 /srv/log && ln -s /srv/log/apache2 /var/log
echo coucou > /srv/www/default/public/index.php




# Gestion des fichiers de log.
# (Pas vraiment necessaire pour docker ou logrotate tourne pas)
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




# Variables d'environnement
cat > /etc/environment <<EOF
TZ=Europe/Paris
ENVIRONMENT=dev
PLATFORM=dev
PLATFORM_URL=dev.
LIB_INCLUDE_PATH=/srv/www/lib/clean
LEGACY_LIB_INCLUDE_PATH=/srv/www/lib/legacy

EOF

cat >> /etc/apache2/envvars <<EOF

### Env Vars - Because Apache does not use /etc/environment...
#export PLATFORM=dev
#export PLATFORM_URL=dev.
#export LIB_INCLUDE_PATH=/srv/www/lib/clean
#export LEGACY_LIB_INCLUDE_PATH=/srv/www/lib/legacy
### DOn't care here.

EOF

# Conf PHP :
for fichier in /etc/php/${PHP_VERSION}/apache2/php.ini /etc/php/${PHP_VERSION}/cli/php.ini ; do
  sed -i -e "s/^variables_order.*/variables_order = \"EGPCS\"/" $fichier
  sed -i -e "s/^;date\.timezone.*/date.timezone = Europe\/Paris/" $fichier
  sed -i -e "s/^expose_php.*/expose_php = Off/" $fichier
  sed -i -e "s/^post_max_size.*/post_max_size = 80M/" $fichier
  sed -i -e "s/^upload_max_filesize.*/upload_max_filesize = 20M/" $fichier
  #sed -i -e "s/^session\.use_only_cookies.*/session.use_only_cookies = 0/" $fichier

  # Il y aurait des trucs a faire pour les sessions en memcache mais pour machine de dev on va s'en passer
  # Et pour le reste, display errors & co, le defaut debian est bon pour l'instant
done



# conf apache

## Conf SSL
mkdir /etc/apache2/ssl

cat > /etc/apache2/ssl/dev.crt <<EOF
-----BEGIN CERTIFICATE-----
MIID/zCCAuegAwIBAgIUHY8CkPf1yxXcOV+mfRMUbIrKemMwDQYJKoZIhvcNAQEM
BQAwWTEMMAoGA1UEAwwDZGV2MQswCQYDVQQGEwJGUjEXMBUGA1UECAwOw45sZS1k
ZS1GcmFuY2UxDjAMBgNVBAcMBVBhcmlzMRMwEQYDVQQKDApEZXYgRG9ja2VyMCAX
DTI1MDQxNjE3MzIxMFoYDzIwNTUwNDA5MTczMjEwWjBZMQwwCgYDVQQDDANkZXYx
CzAJBgNVBAYTAkZSMRcwFQYDVQQIDA7DjmxlLWRlLUZyYW5jZTEOMAwGA1UEBwwF
UGFyaXMxEzARBgNVBAoMCkRldiBEb2NrZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IB
DwAwggEKAoIBAQC3Oml6oan8fNi0M1xZN+4dIrThMKpPpUaTJpZbF3gA2o+8iyPp
GpuoiCcHq7SNPhRge6JgCls6cCbkhqZhkNYT7s40sHziK4P9OZLkac2ptQjPodY4
lz7BEQtwK2QgkQ1WZm9o/apDS453du6Ig3SuAp8jIBFV4c3SHquUz41Tin1roGWF
VcMczg35Q3iUkf+4N76wJfEFZJ6ufPhUtsZlfIW1sICLDTc1FOJJxpaFEMDMCeQW
AtUAJ8DL2d285YiMwHg+8Y2/WZylqsuTDrjrPuSiJmuXvRKVM5cz95zJK/krHooS
m2MhU2Z9G9eOzz6rjBPvSo22/WSyNYjHfG1rAgMBAAGjgbwwgbkwHQYDVR0OBBYE
FHrU8Z6WzGelHFgdfbIya6zRm0jbMB8GA1UdIwQYMBaAFHrU8Z6WzGelHFgdfbIy
a6zRm0jbMA4GA1UdDwEB/wQEAwIFoDAgBgNVHSUBAf8EFjAUBggrBgEFBQcDAQYI
KwYBBQUHAwIwRQYDVR0RBD4wPIIDZGV2ggR0ZXN0ggUqLmRldoIGKi50ZXN0ggVs
b2NhbIIHKi5sb2NhbIIGZG9ja2VygggqLmRvY2tlcjANBgkqhkiG9w0BAQwFAAOC
AQEAKIHjKpJtrHh2E5onhW/t6DyzpFaz91A/oCeruUyDWyLPNlgClxa9hS/LudkO
rusIVI35LtK7Vc2mMoA0mzBTR76IefndxQVHMVVIKMn8wLiSZ6I+wL4f6ylSSVqa
IhH8ddSAE1t+KdchW5MOQr1TOlf51DUGX8fuuEvmSV5+5hB8QPvzsts0Yd+08HQM
lbAYRmQVEf1fA5KL77FNHc1d5d/XIuXdqb/1tikYdeuSmtMPFIezOQ8EHFYONcLe
S3RP6/tpyWjTOjsO5HG/W/ndBXsbYE5tkoB+u21CePHjHii0hVd6Lm+y6AD/OIbE
y297Njj7yoEepUUr3cGhIA5oKw==
-----END CERTIFICATE-----
EOF

cat > /etc/apache2/ssl/dev.key <<EOF
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQC3Oml6oan8fNi0
M1xZN+4dIrThMKpPpUaTJpZbF3gA2o+8iyPpGpuoiCcHq7SNPhRge6JgCls6cCbk
hqZhkNYT7s40sHziK4P9OZLkac2ptQjPodY4lz7BEQtwK2QgkQ1WZm9o/apDS453
du6Ig3SuAp8jIBFV4c3SHquUz41Tin1roGWFVcMczg35Q3iUkf+4N76wJfEFZJ6u
fPhUtsZlfIW1sICLDTc1FOJJxpaFEMDMCeQWAtUAJ8DL2d285YiMwHg+8Y2/WZyl
qsuTDrjrPuSiJmuXvRKVM5cz95zJK/krHooSm2MhU2Z9G9eOzz6rjBPvSo22/WSy
NYjHfG1rAgMBAAECggEADeqET1mO8QvEY69Q8L/EOHdF2KKbFNB/MzbnjYSTSzFO
YGoK8K3iK6Mnn7gFTwLrhkZtlzDCLAaPlaS6Z0eaUso85BiRa5YVgLqKMwnsIlsL
D8YBYKvwCrbSMRNCmAycQDcoeAdoEpNe/yjLxheB2aN+VaseVfD/8lj8/CDlYXZO
18uGfPu2HAdLJOEZO1WugZ6q8TJOflr+TXw1qYCZr3VCgl2q7Rdvn5p1p0ehtSPh
tDykBGs3BXbdpQueZS0JgSyky2Zbh69q0X7aJHchQQJt3GKz5wPjl5h5TjW8E6cY
DXVJN00c6svxqeOzCD/G9nwKmKi+0LLgjDsDjoIOCQKBgQDcolEzGLKeqJ4ch7qi
ivJ7bPs4GGCpw+Vf1TwL/5zjR1iCpFzK4ZxVDe21IIJ7AtqBJaWbn989D0/Y+T8p
PBg4trvHJmAuHBdKzVTS1M0fgMoZNkLbBiT0nODoeaSWYfF61xUWTtqG2tcEdLI1
BKrXKkAUrmc6EodLCI3C22Fi4wKBgQDUmSaNM06B10z3odDv788ZWjhA9i+aYu2b
92RM6ObOXLW4DGf7+yWaOVsBj4xrs7XH6VZ17H8ebL9d/bC4hn0YYc0lvYAsYlRf
OMLRt1MgSaIwhPv0QeLd/XZ1S5CMSPpfpZBmO9Qv/BJb68xPZ0F6V1qzyxETiTfu
w2taJYXp2QKBgFQv/4nev7F4p7Q9OkLxf+sGv6k87A17OVfi9qGhbIzw2V4oN1wW
0F9IDE8T05X6lcO3yMRkMXuMDyy8lpQ2YQuq9mXcR9DwWRbq2JYGKyr9KqCKKuKG
Kq3H+q3aVKopP0pfLaWwewQAFxGVMba3TDUD4yXBEpR/I27HGcijizp/AoGAcOVL
NZxTSlv8wVuqyl98iKgCS2zwZnm2WCaNmtHrDxboYO4loggCNd3TWAbUuLTcCWb9
xO1rq8pv7Qe0+qhgcbwt5qa1E9y7lT1dJ2TEvdacTEuySElcoing5/TSs8xlOLmA
7ulCiqC/VxTmkBvzB3av8d4aGVe63g3kSiC29jECgYAxemChTUCk9GaQAoon3AFI
fKXhQCYlaH0BAMJz40vmz/dfoWWJjUARLgmvdyj+j1hLRj+6oK23NfAH6fIdNVZv
91JvfY9VDEokIrIU95X/E0REZIZHPWBLV5a6h9+ljPYzf9uiLf0M9TJzLYHLKsGw
Qpri7x5m91EnksWTgh3biQ==
-----END PRIVATE KEY-----
EOF

## La conf de base (note : concurrence & co fortement baisse par rapport au standard)
cat > /etc/apache2/conf-available/crbr.conf<<EOF

### Conf de base, nombre de threads n co

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


### Sharing des sessions SSL dans Memcache pour serveurs load balances
# Override de la conf par defaut dans ssl.conf (shared memory sur le server)
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

   # Notes : volontairement pas mis les options de use stapling. Ca ne fonctionne pas bien avec certificat intermedaire
</IfModule>


### Directives des Log
LogLevel warn
#deja dans apache2.conf#ErrorLog /srv/log/apache2/error.log

<IfModule !mod_remoteip.c>
    # Si on n'a pas configure mod_remote_ip & cloudflare
    # On garde l'ancienne conf

    # Log Format Normal
    LogFormat "%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %V %D %I %O" vcombined

    # Log format pour requetes SOAP (remplace le referer par la soap action)
    LogFormat "%v:%p %h %l %u %t \"%r\" %>s %b \"%{SOAPAction}i\" \"%{User-Agent}i\" %V %D %I %O" vcombinedsoap

    # Log format for lines with GDPR crap in the GET request that we need to not log...
    LogFormat "%v:%p %h %l %u %t \"%m %U HTTP/1.1\" %>s %b \"-\" \"%{User-Agent}i\" %V %D %I %O" vcombinednoquerystring
</IfModule>
<IfModule mod_remoteip.c>
    # Si on utilise cloudflare et qu'on a active mod_remote_ip a la place du vieux mod_cloudflare (plus maintenu)

    RemoteIPHeader CF-Connecting-IP

    # IPv4 de Cloudflare
    RemoteIPInternalProxy 173.245.48.0/20
    RemoteIPInternalProxy 103.21.244.0/22
    RemoteIPInternalProxy 103.22.200.0/22
    RemoteIPInternalProxy 103.31.4.0/22
    RemoteIPInternalProxy 141.101.64.0/18
    RemoteIPInternalProxy 108.162.192.0/18
    RemoteIPInternalProxy 190.93.240.0/20
    RemoteIPInternalProxy 188.114.96.0/20
    RemoteIPInternalProxy 197.234.240.0/22
    RemoteIPInternalProxy 198.41.128.0/17
    RemoteIPInternalProxy 162.158.0.0/15
    RemoteIPInternalProxy 104.16.0.0/13
    RemoteIPInternalProxy 104.24.0.0/14
    RemoteIPInternalProxy 172.64.0.0/13
    RemoteIPInternalProxy 131.0.72.0/22


    # IPv6 de Cloudflare
    RemoteIPInternalProxy 2400:cb00::/32
    RemoteIPInternalProxy 2606:4700::/32
    RemoteIPInternalProxy 2803:f800::/32
    RemoteIPInternalProxy 2405:b500::/32
    RemoteIPInternalProxy 2405:8100::/32
    RemoteIPInternalProxy 2a06:98c0::/29
    RemoteIPInternalProxy 2c0f:f248::/32

    # Liste des IPs: https://www.cloudflare.com/ips/
    # La conf avec mod remoteip : https://support.cloudflare.com/hc/en-us/articles/200170786-Restoring-original-visitor-IPs#JUxJSMn3Ht5c5yq

    # Log Format Normal
    LogFormat "%v:%p %a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %V %D %I %O" vcombined

    # Log format pour requetes SOAP (remplace le referer par la soap action)
    LogFormat "%v:%p %a %l %u %t \"%r\" %>s %b \"%{SOAPAction}i\" \"%{User-Agent}i\" %V %D %I %O" vcombinedsoap

    # Log format for lines with GDPR crap in the GET request that we need to not log...
    LogFormat "%v:%p %a %l %u %t \"%m %U?CENSORED HTTP/1.1\" %>s %b \"-\" \"%{User-Agent}i\" %V %D %I %O" vcombinednoquerystring
</IfModule>

SetEnvIf SOAPAction "^$" notsoapaction

# Normal log if it not SOAP and we dont ask to remove the query string parameters
CustomLog /srv/log/apache2/access.log vcombined expr=(reqenv('notsoapaction')=='yes'&&reqenv('removequerystring')!='yes')

# If we are not a SOAP action and we asked to remove the query string parameters with a SetEnvIf SOMETHING removequerystring=yes
CustomLog /srv/log/apache2/access.log vcombinednoquerystring expr=(reqenv('notsoapaction')=='yes'&&reqenv('removequerystring')=='yes')

# If we are a soap action
CustomLog /srv/log/apache2/access.log vcombinedsoap expr=(reqenv('notsoapaction')!='yes')


### Securite
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

    # Celui-la n'est pas set par ProxyAddHeaders
    #  Si on n'a rien, on le met nous meme, http en http et https en https
    SetEnvIfNoCase ^CloudFront-Forwarded-Proto$ (.+) CloudFront=$1
    RequestHeader setifempty X-Forwarded-Proto %{CloudFront}e env=CloudFront
    RequestHeader setifempty X-Forwarded-Proto expr=%{REQUEST_SCHEME} env=!CloudFront

</IfModule>
EOF

#sed -i -e "s/^ServerSignature.*/ServerSignature Off/" /etc/apache2/conf-available/security.conf
#sed -i -e "s/^ServerTokens.*/ServerTokens Prod/" /etc/apache2/conf-available/security.conf
# Remplace par a2disconf security et le reste dans crbr.conf

## Modules
a2dismod access_compat
a2enmod authnz_ldap headers ldap proxy_http rewrite ssl vhost_alias


## activation / desactivation de confs
a2disconf security
a2disconf other-vhosts-access-log
a2disconf charset
a2disconf localized-error-pages
a2disconf serve-cgi-bin
a2enconf crbr


## site "par defaut"
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

# Creation d'un truc par defaut avec vhost_alias mais ils peuvent l'override au besoin en ecrasant le repertoire /etc/apache2/sites-enabled
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


## Note : pas de notion de filtrage d'IP et d'access ICI => Rien  ce sujet dans la conf et pas de /etc/apache2/access sur cette machine.



# Le truc pour docker, pour lui faire lancer apache au demarage
# (pomp sur VM officiel, avec ajout de purge des logs au demarrage)


cat > /usr/local/bin/docker-php-entrypoint << 'EOF'
#!/bin/sh
set -e


# Log files cleanup
rm -rf /srv/log/apache2/* 2>/dev/null || true
touch /srv/log/apache2/access.log /srv/log/apache2/error.log
chown www-data: /srv/log/apache2/access.log /srv/log/apache2/error.log

# Suppress annoying warning at startup
echo "ServerName $(hostname)" > /etc/apache2/conf-enabled/servername.conf


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



# Clean des conneries avant de clore l'image
rm -rf /tmp/* /var/tmp/* 2> /dev/null
find /var/log -type f -delete
find /srv/log -type f -delete

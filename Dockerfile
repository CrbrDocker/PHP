# Apache + PHP on the crbr Debian base image. The PHP version is chosen at build
# time via the PHP_VERSION build-arg (8.3 / 8.4 / 8.5 / …); the workflow drives
# one build per version resolved live from the sury repo.
# BASE_DIGEST records the exact base index the image was built from so the
# rebuild gate can detect a refreshed base.
FROM crbrdocker/debian:stable
ARG PHP_VERSION=8.3
ARG IMAGE_VERSION=""
ARG IMAGE_REVISION=""
ARG IMAGE_CREATED=""
ARG IMAGE_SOURCE=""
ARG BASE_DIGEST=""

COPY --chmod=755 install-php.sh /usr/local/bin/install-php.sh
RUN PHP_VERSION="${PHP_VERSION}" /usr/local/bin/install-php.sh && rm -f /usr/local/bin/install-php.sh

LABEL org.opencontainers.image.title="apache-php" \
      org.opencontainers.image.description="Apache + PHP ${PHP_VERSION} on the crbr Debian base image" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.base.name="crbrdocker/debian:stable" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"

ENTRYPOINT ["docker-php-entrypoint"]
STOPSIGNAL SIGWINCH
WORKDIR /srv/www
EXPOSE 80/tcp
EXPOSE 443/tcp
CMD ["apache2-foreground"]

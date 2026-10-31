# The application image of product-catalog-api.
#
# The base images are pinned by digest: a floating tag would let the runtime
# drift away from the version the lock file was built for. The application
# source is copied into the image, so the container needs no bind mount of the
# repository. Every bind mount of the compose stack lives under var/ (R92).

FROM php:8.4-apache@sha256:4af38a0245996e700e20ec211b9f1c44fb789ad8cc7d24c7ea81ff382b641052 AS base

# The application needs the pgsql and the zip extensions. The client library
# of postgres is needed to build the pdo_pgsql extension.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip libzip-dev libpq-dev \
    && docker-php-ext-install pdo_pgsql zip \
    && rm -rf /var/lib/apt/lists/*

# The routing of Laravel needs the rewrite module: every request that is not
# a file of the document root is sent to the front controller. The module is
# not enabled in the base image.
RUN a2enmod rewrite

# The composer of the matching version, so the lock file is installed the way
# it was resolved.
COPY --from=composer:2@sha256:af98f42dfff7c68ba8d53c2164fd9fde1087b7d449514baa38c418b1f6bc4bac /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# The dependency layer. The lock file alone decides the tree, so the layer is
# reused whenever only the application code changes.
FROM base AS vendor

COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-progress --no-scripts --prefer-dist

# The runtime image installs only the production dependencies.
FROM base AS vendor-prod

COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-progress --no-scripts --no-dev --prefer-dist

# The test image carries the suite next to the application. The suite runs
# against an in memory database, so it needs neither a database nor a
# network.
FROM vendor AS test

COPY . .
RUN composer dump-autoload --optimize --no-interaction --no-scripts \
    && chown -R www-data:www-data /var/www/html

USER www-data

ENTRYPOINT ["./vendor/bin/phpunit", "--colors=always"]

# The runtime image carries the application only. The process runs as the
# unprivileged www-data user, and the image holds no secret.
FROM vendor-prod AS runtime

# The web server listens on a port that needs no privilege, so the container
# does not have to run as root.
COPY build/php/apache.conf /etc/apache2/ports.conf
COPY build/php/apache-vhost.conf /etc/apache2/sites-available/000-default.conf

COPY --chown=www-data:www-data . .
RUN composer dump-autoload --optimize --no-interaction --no-scripts \
    && php artisan package:discover --ansi \
    && mkdir -p storage/framework/{cache/data,sessions,views} storage/logs bootstrap/cache \
    && chmod +x build/php/entrypoint.sh \
    && chown -R www-data:www-data storage bootstrap/cache

USER www-data

EXPOSE 8080

ENTRYPOINT ["build/php/entrypoint.sh"]
CMD ["apache2-foreground"]

# The application answers /api/category without a body. The check asks for
# the list, so a running process and a dead one can be told apart.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=15s \
  CMD php -r "exit(@fsockopen('127.0.0.1', 8080) ? 0 : 1);"

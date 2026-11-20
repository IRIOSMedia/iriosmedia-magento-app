# PHP-FPM 8.3 for Magento Open Source 2.4.8, with Composer. Used by the php and cron services.
FROM php:8.3-fpm-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libicu-dev libxslt1-dev libzip-dev \
        unzip git default-mysql-client \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" bcmath ftp gd intl pdo_mysql soap sockets xsl zip opcache \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer
COPY php.ini /usr/local/etc/php/conf.d/zz-magento.ini
COPY fpm-pool.conf /usr/local/etc/php-fpm.d/zz-magento.conf

# The store lives in named volumes mounted here, owned by www-data: the user PHP-FPM, cron and bin/magento run as.
# A new volume copies the ownership of the folder it is mounted on.
RUN mkdir -p /var/www/html/pub/media \
    && chown -R www-data:www-data /var/www/html
ENV COMPOSER_HOME=/tmp/composer
WORKDIR /var/www/html

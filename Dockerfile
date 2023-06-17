FROM php:8.1.20-cli-alpine3.18 as compile

ENV PHP_REDIS_VERSION=5.3.7 \
    PHP_MONGODB_VERSION=1.13.0 \
    PHP_SWOOLE_VERSION=v5.0.3 \
    PHP_IMAGICK_VERSION=3.7.0 \
    PHP_YAML_VERSION=2.2.2 \
    PHP_MAXMINDDB_VERSION=v1.11.0 \
    PHP_SCRYPT_COMMIT_SHA="845b889bdbe817afe1633237f8fc68667c7a700b" \
    PHP_ZSTD_VERSION="9a01a21b1f1555100540db0ae4f71274407f7896" \
    PHP_BROTLI_VERSION="dcc7085aa0880e7547886cf53ffab60a35746b0b" \
    PHP_SNAPPY_VERSION="bfefe4906e0abb1f6cc19005b35f9af5240d9025" \
    PHP_LZ4_VERSION="2f006c3e4f1fb3a60d2656fc164f9ba26b71e995" \
    PHP_XDEBUG_VERSION="xdebug_3_1"

RUN \
  apk add --no-cache --virtual .deps \
  make \
  automake \
  autoconf \
  gcc \
  g++ \
  git \
  zlib-dev \
  openssl-dev \
  yaml-dev \
  imagemagick \
  imagemagick-dev \
  libmaxminddb-dev \
  zstd-dev \
  brotli-dev \
  lz4-dev

RUN docker-php-ext-install sockets

FROM compile AS redis
RUN \
  # Redis Extension
  git clone --depth 1 --branch $PHP_REDIS_VERSION https://github.com/phpredis/phpredis.git && \
  cd phpredis && \
  phpize && \
  ./configure && \
  make && make install

## Swoole Extension
FROM compile AS swoole
RUN \
  git clone --depth 1 --branch $PHP_SWOOLE_VERSION https://github.com/swoole/swoole-src.git && \
  cd swoole-src && \
  phpize && \
  ./configure --enable-sockets --enable-http2 --enable-openssl && \
  make && make install && \
  cd ..

## Imagick Extension
FROM compile AS imagick
RUN \
  git clone --depth 1 --branch $PHP_IMAGICK_VERSION https://github.com/imagick/imagick && \
  cd imagick && \
  phpize && \
  ./configure && \
  make && make install

## YAML Extension
FROM compile AS yaml
RUN \
  git clone --depth 1 --branch $PHP_YAML_VERSION https://github.com/php/pecl-file_formats-yaml && \
  cd pecl-file_formats-yaml && \
  phpize && \
  ./configure && \
  make && make install

## Maxminddb extension
FROM compile AS maxmind
RUN \
  git clone --depth 1 --branch main https://github.com/maxmind/MaxMind-DB-Reader-php.git && \
  cd MaxMind-DB-Reader-php && \
  cd ext && \
  phpize && \
  ./configure && \
  make && make install

# Mongodb Extension
FROM compile as mongodb
RUN \
  git clone --depth 1 --branch $PHP_MONGODB_VERSION https://github.com/mongodb/mongo-php-driver.git && \
  cd mongo-php-driver && \
  git submodule update --init && \
  phpize && \
  ./configure && \
  make && make install

# Zstd Compression
FROM compile as zstd
RUN git clone --recursive -n https://github.com/kjdev/php-ext-zstd.git \
  && cd php-ext-zstd \
  && git checkout $PHP_ZSTD_VERSION \
  && phpize \
  && ./configure --with-libzstd \
  && make && make install

## Brotli Extension
FROM compile as brotli
RUN git clone https://github.com/kjdev/php-ext-brotli.git \
 && cd php-ext-brotli \
 && git checkout $PHP_BROTLI_VERSION \ 
 && phpize \
 && ./configure --with-libbrotli \
 && make && make install

## LZ4 Extension
FROM compile AS lz4
RUN git clone --recursive https://github.com/kjdev/php-ext-lz4.git \
  && cd php-ext-lz4 \
  && git reset --hard $PHP_LZ4_VERSION \
  && phpize \
  && ./configure --with-lz4-includedir=/usr \ 
  && make && make install

## Snappy Extension
FROM compile AS snappy
RUN git clone --recursive https://github.com/kjdev/php-ext-snappy.git \
  && cd php-ext-snappy \
  && git reset --hard $PHP_SNAPPY_VERSION \
  && phpize \
  && ./configure \
  && make && make install

## Scrypt Extension
FROM compile AS scrypt
RUN \
  git clone --depth 1 https://github.com/DomBlack/php-scrypt.git && \
  cd php-scrypt && \
  git checkout $PHP_SCRYPT_COMMIT_SHA && \
  phpize && \
  ./configure --enable-scrypt && \
  make && make install

## Xdebug Extension
FROM compile AS xdebug
RUN \
  git clone --depth 1 --branch $PHP_XDEBUG_VERSION https://github.com/xdebug/xdebug.git && \
  cd xdebug && \
  phpize && \
  ./configure --enable-xdebug && \
  make && make install

FROM php:8.1.20-cli-alpine3.18 as final

LABEL maintainer="team@appwrite.io"

ENV DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
ENV DOCKER_COMPOSE_VERSION=v2.5.0

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN \
  apk update \
  && apk add --no-cache --virtual .deps \
  make \
  automake \
  autoconf \
  gcc \
  g++ \
  curl-dev \
  && apk add --no-cache \
  libstdc++ \
  rsync \
  brotli-dev \
  lz4-dev \
  yaml-dev \
  imagemagick \
  imagemagick-dev \
  libmaxminddb-dev \
  certbot \
  docker-cli \
  libgomp \
  git \
  && docker-php-ext-install sockets opcache pdo_mysql \
  && apk del .deps \
  && rm -rf /var/cache/apk/*

RUN \
  mkdir -p $DOCKER_CONFIG/cli-plugins \
  && ARCH=$(uname -m) && if [ $ARCH == "armv7l" ]; then ARCH="armv7"; fi \
  && curl -SL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-$ARCH -o $DOCKER_CONFIG/cli-plugins/docker-compose \
  && chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

WORKDIR /usr/src/code

COPY --from=xdebug /usr/local/lib/php/extensions/no-debug-non-zts-20210902/xdebug.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=swoole /usr/local/lib/php/extensions/no-debug-non-zts-20210902/swoole.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=redis /usr/local/lib/php/extensions/no-debug-non-zts-20210902/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=imagick /usr/local/lib/php/extensions/no-debug-non-zts-20210902/imagick.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=yaml /usr/local/lib/php/extensions/no-debug-non-zts-20210902/yaml.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=maxmind /usr/local/lib/php/extensions/no-debug-non-zts-20210902/maxminddb.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=mongodb /usr/local/lib/php/extensions/no-debug-non-zts-20210902/mongodb.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=scrypt /usr/local/lib/php/extensions/no-debug-non-zts-20210902/scrypt.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=zstd /usr/local/lib/php/extensions/no-debug-non-zts-20210902/zstd.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=brotli /usr/local/lib/php/extensions/no-debug-non-zts-20210902/brotli.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=lz4 /usr/local/lib/php/extensions/no-debug-non-zts-20210902/lz4.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/
COPY --from=snappy /usr/local/lib/php/extensions/no-debug-non-zts-20210902/snappy.so /usr/local/lib/php/extensions/no-debug-non-zts-20210902/


# Enable Extensions
RUN echo zend_extension=xdebug.so >> /usr/local/etc/php/conf.d/xdebug.ini
RUN echo extension=swoole.so >> /usr/local/etc/php/conf.d/swoole.ini
RUN echo extension=redis.so >> /usr/local/etc/php/conf.d/redis.ini
RUN echo extension=imagick.so >> /usr/local/etc/php/conf.d/imagick.ini
RUN echo extension=yaml.so >> /usr/local/etc/php/conf.d/yaml.ini
RUN echo extension=maxminddb.so >> /usr/local/etc/php/conf.d/maxminddb.ini
RUN echo extension=scrypt.so >> /usr/local/etc/php/conf.d/scrypt.ini
RUN echo extension=zstd.so >> /usr/local/etc/php/conf.d/zstd.ini
RUN echo extension=brotli.so >> /usr/local/etc/php/conf.d/brotli.ini
RUN echo extension=lz4.so >> /usr/local/etc/php/conf.d/lz4.ini
RUN echo extension=snappy.so >> /usr/local/etc/php/conf.d/snappy.ini

EXPOSE 80

ENV XDEBUG_SESSION=1
CMD [ "tail", "-f", "/dev/null" ]

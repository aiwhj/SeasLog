FROM php:5.6-apache
COPY . /usr/src/SeasLog/
COPY config/php.ini /usr/local/etc/php/
COPY tests/ /var/www/html/
RUN cd /usr/src/SeasLog/ \
    && phpize \
    && ./configure --with-seaslog \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable seaslog \
    && mkdir /log/ \
    && chmod -R 777 /log/

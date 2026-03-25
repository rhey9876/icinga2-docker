FROM debian:12-slim

ARG ICINGA2_VERSION=2.13.14-1+debian12
ARG DEBIAN_FRONTEND=noninteractive

# ── Base packages ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release \
      locales tzdata \
      supervisor \
      apache2 libapache2-mod-php \
      php php-mysql php-curl php-gd php-intl php-xml php-mbstring \
      mariadb-server mariadb-client \
      nagios-plugins nagios-nrpe-plugin dnsutils \
      openssl wget \
    && rm -rf /var/lib/apt/lists/*

# ── Locale ─────────────────────────────────────────────────────────────────────
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
    && sed -i 's/# de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen \
    && locale-gen
ENV LANG=en_US.UTF-8

# ── Icinga apt repo ────────────────────────────────────────────────────────────
RUN curl -sSL https://packages.icinga.com/icinga.key | gpg --dearmor \
      -o /usr/share/keyrings/icinga-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] \
      https://packages.icinga.com/debian icinga-$(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/icinga.list \
    && echo "deb-src [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] \
      https://packages.icinga.com/debian icinga-$(lsb_release -cs) main" \
      >> /etc/apt/sources.list.d/icinga.list

# ── Icinga packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      "icinga2=${ICINGA2_VERSION}" \
      "icinga2-bin=${ICINGA2_VERSION}" \
      "icinga2-common=${ICINGA2_VERSION}" \
      "icinga2-ido-mysql=${ICINGA2_VERSION}" \
      icingaweb2 \
      icinga-director-web \
      icinga-director-daemon \
      icinga-php-library \
      icinga-php-thirdparty \
      icinga-php-incubator \
    && rm -rf /var/lib/apt/lists/*

# ── Apache: enable modules, set port 8088 ─────────────────────────────────────
RUN a2enmod rewrite \
    && a2dissite 000-default \
    && sed -i 's/Listen 80/Listen 8088/' /etc/apache2/ports.conf

COPY setup/icingaweb2-apache.conf /etc/apache2/sites-available/icingaweb2.conf
RUN a2ensite icingaweb2

# ── Drop example conf.d files (Director manages all objects) ───────────────────
RUN rm -f /etc/icinga2/conf.d/hosts.conf \
          /etc/icinga2/conf.d/services.conf \
          /etc/icinga2/conf.d/users.conf \
          /etc/icinga2/conf.d/notifications.conf \
          /etc/icinga2/conf.d/templates.conf \
          /etc/icinga2/conf.d/groups.conf \
          /etc/icinga2/conf.d/timeperiods.conf

# ── Cert path compat with existing setup ──────────────────────────────────────
RUN mkdir -p /opt/nagios/etc/cert

# ── Save default /etc/icinga2 so entrypoint can seed fresh volume mounts ──────
RUN cp -r /etc/icinga2 /etc/icinga2-default

# ── Supervisor ─────────────────────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisor/conf.d/icinga.conf

# ── Entrypoint + setup scripts ────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
COPY setup/mysql-init.sh /setup/mysql-init.sh
COPY setup/icinga2-init.sh /setup/icinga2-init.sh
RUN chmod +x /entrypoint.sh /setup/mysql-init.sh /setup/icinga2-init.sh

VOLUME ["/etc/icinga2", "/var/lib/icinga2", "/var/lib/mysql", "/data", "/opt/nagios/etc/cert"]

EXPOSE 8088 5665

ENV TZ=Europe/Berlin \
    ICINGA2_FEATURE_DIRECTOR_PASS=changeme

ENTRYPOINT ["/entrypoint.sh"]

# build
FROM fpco/stack-build:lts-15 AS build-env

RUN mkdir -p /opt/monaba
WORKDIR /opt/monaba

# configure locales
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
 && locale-gen "en_US.UTF-8"
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# build dependencies
RUN apt-get update && apt-get -y install \
  libcrypto++-dev \
  libssl-dev \
  libgeoip-dev

# build monaba executable
COPY stack.yaml ./stack.yaml
COPY Monaba.cabal ./Monaba.cabal
COPY nano-md5-0.1.2 ./nano-md5-0.1.2
COPY ./geshi ./geshi
ADD ./GeoIPCity.dat.gz /usr/share/GeoIP/GeoIPCity.dat

RUN stack setup
RUN stack build --only-snapshot
RUN stack install --only-dependencies
COPY . ./

# install to /root/local/.bin
RUN stack install

FROM fpco/stack-build:lts-15

RUN mkdir -p /opt/monaba
WORKDIR /opt/monaba

COPY --from=build-env /root/.local /root/.local

RUN mkdir -p ./upload

COPY ./geshi ./geshi
ADD ./GeoIPCity.dat.gz /usr/share/GeoIP/GeoIPCity.dat
COPY --from=build-env /opt/monaba/config ./config
COPY --from=build-env /opt/monaba/static ./static

# build captcha executable
#WORKDIR /opt/monaba/captcha
#RUN stack setup
# install to /root/local/.bin
#RUN stack install

#WORKDIR /opt/monaba
RUN ln -s /root/.local/bin/Monaba ./Monaba
RUN ln -s /root/.local/bin/PlainCaptcha ./PlainCaptchz

# run dependencies
RUN apt-get update && apt-get -y install \
  php7.2-fpm \
  ffmpeg \
  imagemagick \
  exiftool \
  libpq-dev \
  libmagickwand-dev \
  libmagickcore-dev \
  libgeoip-dev \
  libicu-dev \
  libcrypto++-dev

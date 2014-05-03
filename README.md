Monaba
======

Imageboard engine written in Haskell and powered by Yesod. [Demo board](http://haibane.ru).

Features
------
* Multiple file attachment
* File censorship ratings SFW/R-15/R-18/R-18G
* AJAX posting
* Post autoload based on Server-Send Events (experimental)
* Answer map and previews
* Thread and image expanding
* Thread hiding
* Post deletion and editing with password
* Prooflabes as replacement of tripcodes
* Kusaba-like formatting with code highlighting and LaTeX support
* Internationalization
* Country flag support
* Antigate-resistant CAPTCHA
* Adaptive design
* Switchable stylesheets
* YouTube and pleer.com embedding
* Works fine with JavaScript disabled
* Rudimental JSON API
* Administration
    - [Hellbanning](http://en.wikipedia.org/wiki/Hellbanning)
    - Banning by IP
    - Thread moderation by OP
    - Flexible account system with customizable groups and permissions
    - Ability to stick and lock threads and to put on auto-sage
    - Modlog which allows to view previous action

Dependencies
------
* GHC >= 7.6
* PHP 5
* GD image library
* MySQL 5

Installation
------
Setup `approot` and `sitename` in config/settings.yml

Change MySQL `user` and `password` in config/mysql.yml

**Download GeoIPCity:**

    wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
    gzip -d GeoLiteCity.dat.gz
    cp GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat

Or it can be installed from repositories. You can change the path in `config/settings.yml`

**Download GeSHi:**

    wget http://sourceforge.net/projects/geshi/files/geshi/GeSHi%201.0.8.11/GeSHi-1.0.8.11.tar.gz
    tar -zxvf GeSHi-1.0.8.11.tar.gz
    mv geshi /your/path/to/geshi

Set your path to GeSHi in `highlight.php`

**Install all required packages (apt based distros):**

    apt-get install ghc php5 libgd-dev mysql-server
    apt-get install cabal-install zlibc libpcre++-dev libpcre3 libpcre3-dev libgeoip-dev libcrypto++-dev libssl-dev libmysqlclient-dev

**Using already compiled binary:**

Download Monaba-[your-arch]-[your-platform].7z [here](https://github.com/ahushh/Monaba/releases) and unpack to `dist/build/Monaba/`

Be aware that it might be quite old.

**Manual building:**

Preparing:

    cabal update
    cabal install hsenv
    ~/.cabal/bin/hsenv
    source .hsenv/bin/activate

Dependencies:

    cabal install happy
    cabal install --only-dependencies

Building:

    cabal clean && cabal configure && cabal build

You may also want to change meta tags such as `description` and `keywords` in templates/default-layout-wrapper.hamlet. Do it before building.

**Run:**

Create a database:

    mysql -u mysqluser -pmysqlpassword -e 'create database Monaba_production;'

Run the application to initialize database schema:

    ./dist/build/Monaba/Monaba production

Open another terminal and fill database with default values:

    mysql -u mysqluser -pmysqlpassword -e 'use Monaba_production; source init-db.sql;'

You are done. Navigate to manage page and use "admin" both for username and for password to log in.

Deployment
------

Coming soon.

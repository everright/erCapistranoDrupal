erCapistranoDrupal
==================

erCapistranoDrupal is a drupal deploy file for Capistrano. Includes site install, database migration; support subsites.

## Requirements
* [Drush](http://drush.ws)
* [Capistrano](https://github.com/capistrano/capistrano)
* [Capistrano-ext](https://github.com/neerajkumar/capistrano-ext)

## Versions
* Drupal 7
* Drupal 6 will be support on next version

## Installation

    $ gem install erCapistranoDrupal

## Usage

Open your application's `Capfile` and make it begins like this:

    require 'rubygems'
    require 'erCapistranoDrupal'
    load    'config/deploy'

Taking care to remove the original `require 'deploy'` as this is where all the standard tasks are defined.

You should then be able to proceed as you would usually, you may want to familiarise yourself with the truncated list of tasks, you can get a full list with:

    $ cap -T

## Special Files
### .htaccess
* /htaccess-[dev|staging|production]
* /htaccess

### robots.txt
* /robots-[dev|staging|production].txt

### settings.php
* /sites/[default]/settings.[dev|staging|production].php
* [shared_path]/sites/[default]/settings.php

### database migrations
* /migration/[default]/[yyyymmdd]/[hhiiss]_task.sql
* /migration/[default]/[yyyymmdd]/[hhiiss]_task.drush

#### SQL File
    # add user (2) to role (3)
    insert into users_roles (uid, rid) values (2, 3);

#### Drush File
    # create new user 'everright'
    user-create everright --mail="everright@example.com" --password="123456"
    # enable token module
    en token

## Default Variables

### Where to save the download resources
* :dp_local_backup, '/backup'

### Directories under shared_path: drupal sites, database backup, files backup, migration history
* :dp_sites, 'sites'
* :dp_migration, 'migration'
* :dp_released_files, 'released_files'
* :dp_released_db, 'released_db'

### Domains, virtualhosts
* :dp_domains, ['default']
* :dp_default_domain, 'default'
* :dp_virtual_hosts, []

### Share files when use multiple web servers
* :dp_shared_files, false
* :dp_shared_path, '/nfs'

### Drush tool
* :drush, '/usr/bin/drush'

### Drush site install info
If you want to install the drupal when first deploy, then you need to change these variables.
* :dp_site_install, false 
* :dp_site_db_url, nil
* :dp_site_profile, 'standard'
* :dp_site_name, 'Drupal 7 Demo'
* :dp_site_admin_user, 'admin'
* :dp_site_admin_pass, 'admin'

### Maintainance key
* :dp_maintainance_keys, {'default' => 'maintenance_mode'}

Support "[Read Only Mode](https://drupal.org/project/readonlymode)" module.

System will be auto set the maintainance key to "site_readonly" when "Read Only Mode" module enabled.

## Deploy Example
### deploy.rb

    # application name
    set :application, 'd7demo_deploy'

    # remote server user
    set :user, 'deploy'
    set :use_sudo, false

    # set multiple environments
    set :stages, ['dev', 'staging', 'production']
    set :default_stage, 'dev'

    require 'capistrano/ext/multistage'

    # set scm
    set :scm, :git
    set :repository, 'git@github.com:everright/d7demo.git'
    set :branch, 'master'
    set :deploy_via, :copy
    set :copy_cache, true
    set :copy_exclude, %w(.git .gitignore)

### deploy/dev.rb
    # define servers, must be set primary web.
    server 'dev_server', :web, :primary => true

    # deploy to
    set :deploy_to, "/var/www/sites/dev.d7demo.local"

    # site install info
    set :dp_site_install, true
    set :dp_site_db_url, "mysql://drupal_all:123456@dbserver/d7_demo_dev"
    set :dp_site_profile, "standard"
    set :dp_site_name, "D7 Demo"
    set :dp_site_admin_user, "admin"
    set :dp_site_admin_pass, "admin"

### deploy/staging.rb
    # define servers, must be set primary web.
    server 'staging_server', :web, :primary => true

    # deploy to
    set :deploy_to, "/var/www/sites/staging.d7demo.local"

    # site install info
    set :site_install, true
    set :site_db_url, "mysql://drupal_all:123456@dbserver/d7_demo_staging"
    set :site_profile, "standard"
    set :site_name, "D7 Demo"
    set :site_admin_user, "admin"
    set :site_admin_pass, "admin"

### deploy/production.rb

    # define servers, must be set primary web.
    server 'production_server1', :web, :primary => true
    server 'production_server2', :web
    server 'production_server3', :web, {
      :user => 'other_deploy_user'
    }

    # deploy to
    set :deploy_to, "/var/www/sites/www.d7demo.local"

    # site install info
    set :dp_site_install, true
    set :dp_site_db_url, "mysql://drupal_all:123456@dbserver/d7_demo"
    set :dp_site_profile, "standard"
    set :dp_site_name, "D7 Demo"
    set :dp_site_admin_user, "admin"
    set :dp_site_admin_pass, "admin"

    # If have multiple webservers, enable share files
    set :dp_shared_files, true

## Changelog:

### Version 0.1.0 - June 17 2013
* First release

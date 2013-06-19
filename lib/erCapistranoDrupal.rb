Capistrano::Configuration.instance(:must_exist).load do

  require 'capistrano/recipes/deploy/scm'
  require 'capistrano/recipes/deploy/strategy'

  def _cset(name, *args, &block)
    unless exists?(name)
      set(name, *args, &block)
    end
  end

  # =========================================================================
  # These variables MUST be set in the client capfiles. If they are not set,
  # the deploy will fail with an error.
  # =========================================================================

  _cset(:application) { abort "Please specify the name of your application, set :application, 'foo'" }
  _cset(:repository)  { abort "Please specify the repository that houses your application's code, set :repository, 'foo'" }

  # =========================================================================
  # These variables may be set in the client capfile if their default values
  # are not sufficient.
  # =========================================================================

  _cset(:scm) { scm_default }
  _cset :deploy_via, :checkout

  _cset(:deploy_to) { "/u/apps/#{application}" }
  _cset(:revision)  { source.head }

  # =========================================================================
  # These variables should NOT be changed unless you are very confident in
  # what you are doing. Make sure you understand all the implications of your
  # changes if you do decide to muck with these!
  # =========================================================================

  _cset(:source)            { Capistrano::Deploy::SCM.new(scm, self) }
  _cset(:real_revision)     { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }

  _cset(:strategy)          { Capistrano::Deploy::Strategy.new(deploy_via, self) }

  _cset(:release_name)      { set :deploy_timestamped, true; Time.now.utc.strftime("%Y%m%d%H%M%S") }

  _cset :version_dir,       "releases"
  _cset :shared_dir,        "shared"
  _cset :shared_children,   []
  _cset :current_dir,       "current"

  _cset(:releases_path)     { File.join(deploy_to, version_dir) }
  _cset(:shared_path)       { File.join(deploy_to, shared_dir) }
  _cset(:current_path)      { File.join(deploy_to, current_dir) }
  _cset(:release_path)      { File.join(releases_path, release_name) }

  _cset(:releases)          { capture("#{try_sudo} ls -x #{releases_path}", :except => { :no_release => true }).split.sort }
  _cset(:current_release)   { releases.any? ? File.join(releases_path, releases.last) : nil }
  _cset(:previous_release)  { releases.length > 1 ? File.join(releases_path, releases[-2]) : nil }

  _cset(:current_revision)  { capture("#{try_sudo} cat #{current_path}/REVISION",     :except => { :no_release => true }).chomp }
  _cset(:latest_revision)   { capture("#{try_sudo} cat #{current_release}/REVISION",  :except => { :no_release => true }).chomp }
  _cset(:previous_revision) { capture("#{try_sudo} cat #{previous_release}/REVISION", :except => { :no_release => true }).chomp if previous_release }

  _cset(:run_method)        { fetch(:use_sudo, true) ? :sudo : :run }

  # some tasks, like create_symlink, need to always point at the latest release, but
  # they can also (occassionally) be called standalone. In the standalone case,
  # the timestamped release_path will be inaccurate, since the directory won't
  # actually exist. This variable lets tasks like create_symlink work either in the
  # standalone case, or during deployment.
  _cset(:latest_release) { exists?(:deploy_timestamped) ? release_path : current_release }

  # Where to save the download resources
  _cset :dp_local_backup, '/backup'

  # define release backup db and files, migration
  _cset :dp_sites, 'sites'
  _cset :dp_migration, 'migration'
  _cset :dp_released_files, 'released_files'
  _cset :dp_released_db, 'released_db'

  # Domains, virtualhosts
  _cset :dp_domains, ['default']
  _cset :dp_default_domain, 'default'
  _cset :dp_virtual_hosts, []

  # Share files when use multiple web servers
  _cset :dp_shared_files, false
  _cset :dp_shared_path, '/nfs'

  # Drush tool
  _cset :drush, '/usr/bin/drush'

  # Drush site install info
  _cset :dp_site_install, false 
  _cset :dp_site_db_url, nil
  _cset :dp_site_profile, 'standard'
  _cset :dp_site_name, 'Drupal 7 Demo'
  _cset :dp_site_admin_user, 'admin'
  _cset :dp_site_admin_pass, 'admin'

  # =========================================================================
  # If "Read Only Mode" enabled, then set maintainance key to 'site_readonly'
  # else set maintainance key to 'maintenance_mode'
  # =========================================================================
  _cset :dp_maintainance_keys, {'default' => 'maintenance_mode'}

  # =========================================================================
  # These are helper methods that will be available to your recipes.
  # =========================================================================

  # Checks known version control directories to intelligently set the version
  # # control in-use. For example, if a .svn directory exists in the project,
  # # it will set the :scm variable to :subversion, if a .git directory exists
  # # in the project, it will set the :scm variable to :git and so on. If no
  # # directory is found, it will default to :git.
  def scm_default
    if File.exist? '.git'
      :git
    elsif File.exist? '.accurev'
      :accurev
    elsif File.exist? '.bzr'
      :bzr
    elsif File.exist? '.cvs'
      :cvs
    elsif File.exist? '_darcs'
      :darcs
    elsif File.exist? '.hg'
      :mercurial
    elsif File.exist? '.perforce'
      :perforce
    elsif File.exist? '.svn'
      :subversion
    else
      :none
    end
  end

  # Auxiliary helper method for the `deploy:check' task. Lets you set up your
  # own dependencies.
  def depend(location, type, *args)
    deps = fetch(:dependencies, {})
    deps[location] ||= {}
    deps[location][type] ||= []
    deps[location][type] << args
    set :dependencies, deps
  end

  # Temporarily sets an environment variable, yields to a block, and restores
  # the value when it is done.
  def with_env(name, value)
    saved, ENV[name] = ENV[name], value
    yield
  ensure
    ENV[name] = saved
  end

  # logs the command then executes it locally.
  # returns the command output as a string
  def run_locally(cmd)
    if dry_run
      return logger.debug "executing locally: #{cmd.inspect}"
    end
    logger.trace "executing locally: #{cmd.inspect}" if logger
    output_on_stdout = nil
    elapsed = Benchmark.realtime do
      output_on_stdout = `#{cmd}`
    end
    if $?.to_i > 0 # $? is command exit code (posix style)
      raise Capistrano::LocalArgumentError, "Command #{cmd} returned status code #{$?}"
    end
    logger.trace "command finished in #{(elapsed * 1000).round}ms" if logger
    output_on_stdout
  end

  # If a command is given, this will try to execute the given command, as
  # described below. Otherwise, it will return a string for use in embedding in
  # another command, for executing that command as described below.
  #
  # If :run_method is :sudo (or :use_sudo is true), this executes the given command
  # via +sudo+. Otherwise is uses +run+. If :as is given as a key, it will be
  # passed as the user to sudo as, if using sudo. If the :as key is not given,
  # it will default to whatever the value of the :admin_runner variable is,
  # which (by default) is unset.
  #
  # THUS, if you want to try to run something via sudo, and what to use the
  # root user, you'd just to try_sudo('something'). If you wanted to try_sudo as
  # someone else, you'd just do try_sudo('something', :as => "bob"). If you
  # always wanted sudo to run as a particular user, you could do 
  # set(:admin_runner, "bob").
  def try_sudo(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    command = args.shift
    raise ArgumentError, "too many arguments" if args.any?

    as = options.fetch(:as, fetch(:admin_runner, nil))
    via = fetch(:run_method, :sudo)
    if command
      invoke_command(command, :via => via, :as => as)
    elsif via == :sudo
      sudo(:as => as)
    else
      ""
    end
  end

  # Same as sudo, but tries sudo with :as set to the value of the :runner
  # variable (which defaults to "app").
  def try_runner(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    args << options.merge(:as => fetch(:runner, "app"))
    try_sudo(*args)
  end

  # =========================================================================
  # These are the tasks that are available to help with deploying web apps,
  # and specifically, Rails applications. You can have cap give you a summary
  # of them with `cap -T'.
  # =========================================================================
  namespace :deploy do
    desc <<-DESC
      Deploys your project. This calls both `update' and `restart'. Note that \
      this will generally only work for applications that have already been deployed \
      once. For a "cold" deploy, you'll want to take a look at the `deploy:cold' \
      task, which handles the cold start specifically.
    DESC
    task :default do
      update
      cleanup
    end

    desc <<-DESC
      Prepares one or more servers for deployment. Before you can use any \
      of the Capistrano deployment tasks with your project, you will need to \
      make sure all of your servers have been prepared with `cap deploy:setup'. When \
      you add a new server to your cluster, you can easily run the setup task \
      on just that server by specifying the HOSTS environment variable:

        $ cap HOSTS=new.server.com deploy:setup

      It is safe to run this task on servers that have already been set up; it \
      will not destroy any deployed revisions or data.
    DESC
    task :setup do
      dirs = [deploy_to, releases_path, shared_path]
      dirs += shared_children.map { |d| File.join(shared_path, d.split('/').last) }

      commands = []
      commands << "#{try_sudo} mkdir -p #{dirs.join(' ')}"
      commands << "#{try_sudo} chmod g+w #{dirs.join(' ')}" if fetch(:group_writable, true)

      dirs = [dp_sites, dp_migration, dp_released_files, dp_released_db]

      dp_domains.each do |domain|
        dirs += ["#{dp_sites}/#{domain}", "#{dp_sites}/#{domain}/files", "#{dp_released_files}/#{domain}", "#{dp_released_db}/#{domain}", "#{dp_migration}/#{domain}"]
      end

      if dp_shared_files
        dirs = dirs.map { |d| File.join(dp_shared_path, d) }
      else
        dirs = dirs.map { |d| File.join(shared_path, d) }
      end

      commands << "#{try_sudo} mkdir -p #{dirs.join(' ')}"
      commands << "#{try_sudo} chmod g+w #{dirs.join(' ')}" if fetch(:group_writable, true)

      if dp_shared_files
        commands << "#{try_sudo} ln -nfs #{dp_shared_path}/#{dp_sites} #{shared_path}/#{dp_sites}"
        commands << "#{try_sudo} ln -nfs #{dp_shared_path}/#{dp_released_files} #{shared_path}/#{dp_released_files}"
        commands << "#{try_sudo} ln -nfs #{dp_shared_path}/#{dp_released_db} #{shared_path}/#{dp_released_db}"
        commands << "#{try_sudo} ln -nfs #{dp_shared_path}/#{dp_migration} #{shared_path}/#{dp_migration}"
      end

      run commands.join('; ') if commands.any?
    end

    desc <<-DESC
      Copies your project and updates the symlink. It does this in a \
      transaction, so that if either `update_code' or `create_symlink' fail, all \
      changes made to the remote servers will be rolled back, leaving your \
      system in the same state it was in before `update' was invoked. Usually, \
      you will want to call `deploy' instead of `update', but `update' can be \
      handy if you want to deploy, but not immediately restart your application.
    DESC
    task :update do
      transaction do
        update_code
        create_symlink
        web.default
      end
    end

    desc <<-DESC
      Copies your project to the remote servers. This is the first stage \
      of any deployment; moving your updated code and assets to the deployment \
      servers. You will rarely call this task directly, however; instead, you \
      should call the `deploy' task (to do a complete deploy) or the `update' \
      task (if you want to perform the `restart' task separately).

      You will need to make sure you set the :scm variable to the source \
      control software you are using (it defaults to :subversion), and the \
      :deploy_via variable to the strategy you want to use to deploy (it \
      defaults to :checkout).
    DESC
    task :update_code, :except => { :no_release => true } do
      on_rollback { run "chmod -R ug+w #{release_path}/sites && rm -rf #{release_path}; true" }
      strategy.deploy!
      finalize_update
      maintainance_keys
    end

    desc <<-DESC
      [internal] Touches up the released code. This is called by update_code \
      after the basic deploy finishes. It assumes a Rails project was deployed, \
      so if you are deploying something else, you may want to override this \
      task with your own environment's requirements.

      This task will make the release group-writable (if the :group_writable \
      variable is set to true, which is the default). It will then set up \
      symlinks to the shared directory for the log, system, and tmp/pids \
      directories, and will lastly touch all assets in public/images, \
      public/stylesheets, and public/javascripts so that the times are \
      consistent (so that asset timestamping works).  This touch process \
      is only carried out if the :normalize_asset_timestamps variable is \
      set to true, which is the default.
    DESC
    task :finalize_update, :except => { :no_release => true } do
      escaped_release = latest_release.to_s.shellescape
      commands = []
      commands << "chmod -R -- g+w #{escaped_release}" if fetch(:group_writable, true)

      # mkdir -p is making sure that the directories are there for some SCM's that don't
      # save empty folders
      shared_children.map do |dir|
        d = dir.shellescape
        if (dir.rindex('/')) then
          commands += ["rm -rf -- #{escaped_release}/#{d}", "mkdir -p -- #{escaped_release}/#{dir.slice(0..(dir.rindex('/'))).shellescape}"]
        else
          commands << "rm -rf -- #{escaped_release}/#{d}"
        end
        commands << "ln -s -- #{shared_path}/#{dir.split('/').last.shellescape} #{escaped_release}/#{d}"
      end

      run commands.join(' && ') if commands.any?
    end

    desc "Set the site maintainance keys"
    task :maintainance_keys, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
      if previous_release
        tmp_keys = {}
        
        dp_domains.each do |domain|
          tmp_keys[domain] = capture("#{drush} pml --status='enabled' --root=#{current_path} --uri=#{domain} -y | grep 'Read Only Mode (readonlymode)' > /dev/null; if [ $? = 0 ]; then echo -n 'site_readonly'; else echo -n 'maintenance_mode'; fi")
        end

        set :dp_maintainance_keys, tmp_keys
      end
    end

    desc <<-DESC
      Updates the symlink to the most recently deployed version. Capistrano works \
      by putting each new release of your application in its own directory. When \
      you deploy a new version, this task's job is to update the `current' symlink \
      to point at the new version. You will rarely need to call this task \
      directly; instead, use the `deploy' task (which performs a complete \
      deploy, including `restart') or the 'update' task (which does everything \
      except `restart').
    DESC
    task :create_symlink, :except => { :no_release => true } do
      on_rollback do
        run "rm -f #{current_path}"
        if previous_release
          run "ln -s #{previous_release} #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
    end

    desc <<-DESC
      Deprecated API. This has become deploy:create_symlink, please update your recipes
    DESC
    task :symlink, :except => { :no_release => true } do
      Kernel.warn "[Deprecation Warning] This API has changed, please hook `deploy:create_symlink` instead of `deploy:symlink`."
      create_symlink
    end

    desc <<-DESC
      Copy files to the currently deployed version. This is useful for updating \
      files piecemeal, such as when you need to quickly deploy only a single \
      file. Some files, such as updated templates, images, or stylesheets, \
      might not require a full deploy, and especially in emergency situations \
      it can be handy to just push the updates to production, quickly.

      To use this task, specify the files and directories you want to copy as a \
      comma-delimited list in the FILES environment variable. All directories \
      will be processed recursively, with all files being pushed to the \
      deployment servers.

        $ cap deploy:upload FILES=templates,controller.rb

      Dir globs are also supported:

        $ cap deploy:upload FILES='config/apache/*.conf'
    DESC
    task :upload, :except => { :no_release => true } do
      files = (ENV["FILES"] || "").split(",").map { |f| Dir[f.strip] }.flatten
      abort "Please specify at least one file or directory to update (via the FILES environment variable)" if files.empty?

      files.each { |file| top.upload(file, File.join(current_path, file)) }
    end

    namespace :rollback do
      desc <<-DESC
        [internal] Points the current symlink at the previous revision.
        This is called by the rollback sequence, and should rarely (if
        ever) need to be called directly.
      DESC
      task :revision, :except => { :no_release => true } do
        if previous_release
          run "#{try_sudo} rm #{current_path}; #{try_sudo} ln -s #{previous_release} #{current_path}"
        else
          abort "could not rollback the code because there is no prior release"
        end
      end

      desc <<-DESC
        [internal] Removes the most recently deployed release.
        This is called by the rollback sequence, and should rarely
        (if ever) need to be called directly.
      DESC
      task :cleanup, :except => { :no_release => true } do
        run "if [ `readlink #{current_path}` != #{current_release} ]; then #{try_sudo} rm -rf #{current_release}; fi"
      end

      desc <<-DESC
        Rolls back to the previously deployed version. The `current' symlink will \
        be updated to point at the previously deployed version, and then the \
        current release will be removed from the servers. You'll generally want \
        to call `rollback' instead, as it performs a `restart' as well.
      DESC
      task :code, :except => { :no_release => true } do
        revision
        deploy.web.rollback
        cleanup
      end

      desc <<-DESC
        Rolls back to a previous version and restarts. This is handy if you ever \
        discover that you've deployed a lemon; `cap rollback' and you're right \
        back where you were, on the previously deployed version.
      DESC
      task :default do
        revision
        deploy.web.rollback
        cleanup
      end
    end

    desc <<-DESC
      Clean up old releases. By default, the last 5 releases are kept on each \
      server (though you can change this with the keep_releases variable). All \
      other deployed revisions are removed from the servers. By default, this \
      will use sudo to clean up the old releases, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead.
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_releases, 5).to_i
      if count < releases.length
        deploy.web.cleanup
        run "ls -1dt #{releases_path}/* | tail -n +#{count + 1} | #{try_sudo} xargs rm -rf"
      end
    end

    desc <<-DESC
      Test deployment dependencies. Checks things like directory permissions, \
      necessary utilities, and so forth, reporting on the things that appear to \
      be incorrect or missing. This is good for making sure a deploy has a \
      chance of working before you actually run `cap deploy'.

      You can define your own dependencies, as well, using the `depend' method:

        depend :remote, :gem, "tzinfo", ">=0.3.3"
        depend :local, :command, "svn"
        depend :remote, :directory, "/u/depot/files"
    DESC
    task :check, :except => { :no_release => true } do
      dependencies = strategy.check!

      other = fetch(:dependencies, {})
      other.each do |location, types|
        types.each do |type, calls|
          if type == :gem
            dependencies.send(location).command(fetch(:gem_command, "gem")).or("`gem' command could not be found. Try setting :gem_command")
          end

          calls.each do |args|
            dependencies.send(location).send(type, *args)
          end
        end
      end

      if dependencies.pass?
        puts "You appear to have all necessary dependencies installed"
      else
        puts "The following dependencies failed. Please check them and try again:"
        dependencies.reject { |d| d.pass? }.each do |d|
          puts "--> #{d.message}"
        end
        abort
      end
    end

    desc <<-DESC
      Deploys and starts a `cold' application. This is useful if you have not \
      deployed your application before, or if your application is (for some \
      other reason) not currently running. It will deploy the code, run any \
      pending migrations, and then instead of invoking `deploy:restart', it will \
      invoke `deploy:start' to fire up the application servers.
    DESC
    task :cold do
      update
    end
    
    namespace :pending do
      desc <<-DESC
        Displays the `diff' since your last deploy. This is useful if you want \
        to examine what changes are about to be deployed. Note that this might \
        not be supported on all SCM's.
      DESC
      task :diff, :except => { :no_release => true } do
        system(source.local.diff(current_revision))
      end

      desc <<-DESC
        Displays the commits since your last deploy. This is good for a summary \
        of the changes that have occurred since the last deploy. Note that this \
        might not be supported on all SCM's.
      DESC
      task :default, :except => { :no_release => true } do
        from = source.next_revision(current_revision)
        system(source.local.log(from))
      end
    end

    namespace :web do
      desc <<-DESC
        Run website install, files and database backup,
        Fix htaccess and robots, Database migration.
      DESC
      task :default, :except => { :no_release => true } do
        htaccess
        robots
        virtualhost
        install
        symlink
        backup_files
        backup_database
        disable
        migrate
        clear_cache
        enable
      end

      desc "Symlink files dir from shared path to latest release path"
      task :symlink, :except => { :no_release => true } do
        commands = []

        dp_domains.each do |domain|
          domain_path = "#{release_path}/#{dp_sites}/#{domain}"
        
          commands << "if [ -e '#{domain_path}/settings.#{stage}.php' ]; then #{try_sudo} ln -nfs #{domain_path}/settings.#{stage}.php #{domain_path}/settings.php; elif [ -e '#{shared_path}/#{dp_sites}/#{domain}/settings.php' ]; then #{try_sudo} ln -nfs #{shared_path}/#{dp_sites}/#{domain}/settings.php #{domain_path}/settings.php; fi"
          commands << "if [ -e '#{domain_path}' ]; then #{try_sudo} ln -nfs #{shared_path}/#{dp_sites}/#{domain}/files #{domain_path}/files; fi"

        end

        run commands.join('; ') if commands.any?
      end

      task :htaccess, :except => { :no_release => true } do
        run "if [ -e '#{current_path}/htaccess-#{stage}' ]; then #{try_sudo} mv #{current_path}/htaccess-#{stage} #{current_path}/.htaccess && #{try_sudo} rm -rf #{current_path}/htaccess-*; elif [ -e '#{current_path}/htaccess' ]; then #{try_sudo} mv #{current_path}/htaccess #{current_path}/.htaccess; fi"
      end
  
      task :robots, :except => { :no_release => true } do
        run "if [ -e '#{current_path}/robots-#{stage}.txt' ]; then #{try_sudo} mv #{current_path}/robots-#{stage}.txt #{current_path}/robots.txt && #{try_sudo} rm -rf #{current_path}/robots-*.txt; fi"
      end
  
      task :virtualhost, :except => { :no_release => true } do
        if not dp_virtual_hosts.empty? and not dp_default_domain.empty?
          commands = []

          dp_virtual_hosts.each do |alias_domain|
            commands << "#{try_sudo} ln -nfs #{release_path}/#{dp_sites}/#{default_domain} #{release_path}/#{dp_sites}/#{alias_domain}"
          end

          run commands.join('; ') if commands.any?
        end
      end

      desc "Install site on first deploy if site_install is true."
      task :install, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        if dp_site_install and not previous_release
          abort "Please specify the database url of your drupal install, set :dp_site_db_url, 'mysql://root:123456@localhost/drupal7_demo" if not dp_site_db_url

          default_shared_path = "#{shared_path}/#{dp_sites}/#{dp_default_domain}"
          default_current_path = "#{current_path}/#{dp_sites}/#{dp_default_domain}"
          run "if [ -e '#{default_shared_path}/settings.php' ]; then chmod ug+w #{default_shared_path}/settings.php && rm -rf #{default_shared_path}/settings.php; fi; #{drush} si #{dp_site_profile} --root=#{current_path} --db-url=#{dp_site_db_url} --site-name=\"#{dp_site_name}\" --account-name=\"#{dp_site_admin_user}\" --account-pass=\"#{dp_site_admin_pass}\" -y && #{try_sudo} cp #{default_current_path}/settings.php #{default_shared_path}/settings.php && #{try_sudo} chmod -R ug+w #{default_current_path}; #{try_sudo} rm -rf #{default_current_path}/settings.php #{default_current_path}/files"
        end
      end

      desc "Deactive drupal maintainance mode."
      task :enable, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        commands = []

        dp_domains.each do |domain|
          commands << "#{drush} vset #{dp_maintainance_keys[domain]} 0 --root=#{current_path} --uri=#{domain} -y"
        end

        run commands.join('; ') if commands.any?
      end

      desc "Active drupal maintainance mode."
      task :disable, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        commands = []

        dp_domains.each do |domain|
          commands << "#{drush} vset #{dp_maintainance_keys[domain]} 1 --root=#{current_path} --uri=#{domain} -y"
        end

        run commands.join('; ') if commands.any?
      end

      desc "Run drupal database update migrations if required"
      task :migrate, :roles => [:web], :only => {:primary => true}, :except => { :no_release => true } do
        on_rollback do
          rollback
        end

        commands = []

        dp_domains.each do |domain|
          drush_history = "#{shared_path}/#{dp_migration}/#{domain}/drush.history"
          drush_available = "#{shared_path}/#{dp_migration}/#{domain}/drush.available"
          sql_history = "#{shared_path}/#{dp_migration}/#{domain}/sql.history"
          sql_available = "#{shared_path}/#{dp_migration}/#{domain}/sql.available"

          # Append hook_update migration
          commands << "#{drush} updb --root=#{current_path} --uri=#{domain} -y"

          # Append drush migration
          commands << "#{try_sudo} touch #{drush_history}"
          commands << "find #{current_path}/#{dp_migration}/#{domain} -type f -name *.drush | xargs ls -1v 2>/dev/null > #{drush_available}"
          commands << "diff #{drush_available} #{drush_history} | awk \"/^</ {print \\$2}\" | while read f; do echo \"Migrating: $(basename $f)\"; egrep -v \"^$|^#|^[[:space:]]+$\" $f | while read line; do echo \"Running: drush $line\"; #{drush} $line --root=#{current_path} --uri=#{domain} -y; done; echo $f >> #{drush_history}; done"
          commands << "#{try_sudo} rm -f #{drush_available}"

          # Append sql migration
          commands << "#{try_sudo} touch #{sql_history}"
          commands << "find #{current_path}/#{dp_migration}/#{domain} -type f -name *.sql | xargs ls -1v 2>/dev/null > #{sql_available}"
          commands << "diff #{sql_available} #{sql_history} | awk \"/^</ {print \\$2}\" | while read f; do echo \"Migrating $(basename $f)\"; #{drush} -r #{current_path} --uri=#{domain} sqlq --file=$f -y && echo $f >> #{sql_history}; done"
          commands << "#{try_sudo} rm -f #{sql_available}"
        end

        run commands.join('; ') if commands.any?
      end

      desc "Cache clear"
      task :clear_cache, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        commands = []

        dp_domains.each do |domain|
          commands << "#{drush} cc all --root=#{current_path} --uri=#{domain} -y"
        end

        run commands.join('; ') if commands.any?
      end

      desc "Backup files"
      task :backup_files, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        on_rollback do
          files = []

          dp_domains.each do |domain|
            files << "#{shared_path}/#{dp_released_files}/#{domain}/#{domain}_files_#{release_name}.tar.bz2"
          end

          run "#{try_sudo} rm -rf #{files.join(' ')}" if files.any?
        end
      
        if previous_release
          commands = []

          dp_domains.each do |domain|
            commands << "cd #{shared_path}/#{dp_sites}/#{domain}"
            commands << "#{try_sudo} tar cjf #{shared_path}/#{dp_released_files}/#{domain}/#{domain}_files_#{release_name}.tar.bz2 files"
            commands << "cd -"
          end

          run commands.join('; ') if commands.any?
        end
      end

      desc "Backup database"
      task :backup_database, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        on_rollback do
          files = []

          dp_domains.each do |domain|
            files << "#{shared_path}/#{dp_released_db}/#{domain}/#{domain}_db_#{release_name}.sql.gz"
          end

          run "#{try_sudo} rm -rf #{files.join(' ')}" if files.any?
        end

        if previous_release
          commands = []

          dp_domains.each do |domain|
            commands << "#{try_sudo} #{drush} sql-dump --gzip --result-file=#{shared_path}/#{dp_released_db}/#{domain}/#{domain}_db_#{release_name}.sql --root=#{current_path} --uri=#{domain} -y"
          end

          run commands.join('; ') if commands.any?
        end
      end

      desc "Rollback files and database from release backup"
      task :rollback, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        if previous_release
          commands = []

          dp_domains.each do |domain|
            latest_release_name = latest_release.split('/').last

            files_dump = "#{shared_path}/#{dp_released_files}/#{domain}/#{domain}_files_#{latest_release_name}.tar.bz2"      
            domain_shared_path = "#{shared_path}/#{dp_sites}/#{domain}"
            commands << "if [ -e '#{files_dump}' ]; then rm -rf #{domain_shared_path}/files && tar xjf #{files_dump} -C #{domain_shared_path} && chmod -R g+w #{domain_shared_path}/files && rm -rf #{files_dump}; fi"

            db_dump = "#{shared_path}/#{dp_released_db}/#{domain}/#{domain}_db_#{latest_release_name}.sql"
            commands << "if [ -e '#{db_dump}.gz' ]; then gzip -d #{db_dump}.gz && #{drush} sql-drop --root=#{current_path} --uri=#{domain} -y && #{drush} sqlq --file=#{db_dump} --root=#{current_path} --uri=#{domain} -y && rm -rf #{db_dump}; fi"
          end

          run commands.join('; ') if commands.any?

          clear_cache
        end
      end

      desc "Clean up files and database backup"
      task :cleanup, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
        if previous_release
          count = fetch(:keep_releases, 5).to_i
          commands = []

          dp_domains.each do |domain|
            commands << "ls -1At #{releases_path} | tail -n +#{count} | sed 's!.*!#{shared_path}/#{dp_released_files}/#{domain}/#{domain}_files_&.tar.bz2 #{shared_path}/#{dp_released_db}/#{domain}/#{domain}_db_&.sql.gz!' | #{try_sudo} xargs rm -rf"
            #commands << "ls -1At #{releases_path} | tail -n +#{count + 1} | sed 's!.*!#{shared_path}/#{dp_released_db}/#{domain}/#{domain}_db_&.sql.gz!' | #{try_sudo} xargs rm -rf"
          end
          run commands.join('; ') if commands.any?
        end
      end

      namespace :download do
        desc "Download latest files and database"
        task :default, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
          files
          database
        end

        desc "Download files"
        task :files, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
          run_locally "mkdir -p #{dp_local_backup}/files"

          dp_domains.each do |domain|
            dump_file = "#{stage}_#{domain}_#{release_name}.tar.bz2"
            temp = "/tmp/#{dump_file}"

            run "cd #{shared_path}/#{dp_sites}/#{domain}; #{try_sudo} tar cjf #{temp} files; cd -"
            get temp, "#{dp_local_backup}/files/#{dump_file}"
            run "rm -rf #{temp}"
          end
        end

        desc "Download database"
        task :database, :roles => [:web], :only => { :primary => true }, :except => { :no_release => true } do
          run_locally "mkdir -p #{dp_local_backup}/db"

          dp_domains.each do |domain|
            dump_file = "#{stage}_#{domain}_#{release_name}.sql"
            temp = "/tmp/#{dump_file}"

            run "#{drush} sql-dump --gzip --result-file=#{temp} --root=#{current_path} --uri=#{domain}"
            get "#{temp}.gz", "#{dp_local_backup}/db/#{dump_file}.gz"
            run "rm -rf #{temp}.gz"
          end
        end
      end
    end
  end
end

require "bundler/capistrano"

set :application, "shelr"

set :scm, :git
set :repository, "gitosis@antono.info:shelr.git"
set :user, 'ubuntu'
set :branch, :next
set :deploy_via, :remote_cache

ssh_options[:forward_agent] = true
ssh_options[:port] = 22

role :web, "shelr"                          # Your HTTP server, Apache/etc
role :app, "shelr"                          # This may be the same as your `Web` server
role :db,  "shelr", :primary => true        # This is where Rails migrations will run


def restart_unicorn signal = 'USR2'
  run "kill -#{signal} `cat #{shared_path}/pids/unicorn.pid`"
end

namespace :deploy do
  task :start do
    run "cd #{current_path} && bundle exec unicorn -E production -D -c config/unicorn.production.rb"
  end

  task :stop do
    run "kill -9 `cat #{shared_path}/pids/unicorn.pid`"
  end

  task :restart do
    restart_unicorn
  end
end

namespace :solr do
  task :start do
    run "cd #{current_path} && RAILS_ENV=production bundle exec rake sunspot:solr:start"
  end

  task :stop do
    run "cd #{current_path} && RAILS_ENV=production bundle exec rake sunspot:solr:stop"
  end

  task :restart do
    run "cd #{current_path} && RAILS_ENV=production bundle exec rake sunspot:solr:stop"
    run "cd #{current_path} && RAILS_ENV=production bundle exec rake sunspot:solr:start"
  end
end

namespace :config do
  namespace :unicorn do
    config_path = ::Pathname.new ::File.expand_path('..', __FILE__)
    file_name   = 'unicorn.production.rb'

    task :generate, roles: [:app] do
      require 'erb'

      template = ::ERB.new ::File.read(config_path.join(%{#{file_name}.erb}))

      ::File.open config_path.join(%{../tmp/unicorn.#{stage}.conf.rb}), 'w+' do |file|
        file.write template.result(binding)
      end
    end

    task :upload, roles: [:app] do
      top.upload config_path.join(%{../tmp/unicorn.#{stage}.rb}).to_s,
                 %{#{current_path}/config/#{file_name}},
                 via: :scp
    end

    before 'config:unicorn:upload', 'config:unicorn:generate'

    task :apply, roles: [:app] do
      generate
      upload
      restart_unicorn 'HUP'
    end

  end

  # copy configs from shared path

  task :cp, roles: [:app] do
    run %{cp -Rf #{shared_path}/configs/* #{latest_release}/config}
  end

end

after 'deploy:update_code', 'config:cp'

# recompile assets after updating config
load 'deploy/assets'

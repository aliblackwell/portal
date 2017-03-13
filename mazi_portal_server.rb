require 'sinatra/base'
require 'helpers/mazi_logger'
require 'helpers/authorizer'
require 'helpers/mazi_exec_cmd'
require 'helpers/mazi_config'
require 'thin'
require 'json'
require 'sequel'

class MaziApp < Sinatra::Base
  include MaziConfig
  include Authorizer

  use Rack::Session::Pool, :expire_after => 60 * 60 * 24

  def initialize
    super
    @config = loadConfigFile
    MaziLogger.debug "INIT with config: #{@config}"
    Sequel.connect('sqlite://database/inventory.db')
    require 'models'
  end

  get '/' do
    redirect 'index'
  end

  # this is the main routing configuration that routes all the erb files
  get '/:index/?' do |index|
    MaziLogger.debug "request: get/#{index} from ip: #{request.ip}"
    if session['uuid'].nil?
      s = Mazi::Model::Session.create
      s.ip = request.ip
      s.save
      session['uuid'] = s.uuid
    end
    locals                     = {}
    locals[:local_data]        = {}
    locals[:local_data][:mode] = @config[:general][:mode]
    locals[:js]                = []
    locals[:error_msg]         = nil
    unless session['error'].nil?
      locals[:error_msg] = session["error"]
      session[:error] = nil
    end
    case index
    when 'index'
      session['notifications_read'] = [] if session['notifications_read'].nil?
      locals[:js] << "js/index_application.js"
      locals[:main_body] = :index_application
      locals[:local_data][:applications]          = Mazi::Model::Application.all
      locals[:local_data][:notifications]         = Mazi::Model::Notification.all
      locals[:local_data][:application_instances] = Mazi::Model::ApplicationInstance.all
      locals[:local_data][:notifications_read]    = session['notifications_read']
      locals[:local_data][:config_data]           = @config[:portal_configuration]
      erb :index_main, locals: locals
    when 'index_statistics'
      session['notifications_read'] = [] if session['notifications_read'].nil?
      locals[:js] << "js/index_statistics.js"
      locals[:main_body] = :index_statistics
      locals[:local_data][:notifications]      = Mazi::Model::Notification.all
      locals[:local_data][:notifications_read] = session['notifications_read']
      locals[:local_data][:config_data]        = @config[:portal_configuration]
      ex = MaziExecCmd.new('sh', '/root/back-end/', 'mazi-stat.sh', ['-u'], @config[:scripts][:enabled_scripts], @config[:general][:mode])
      lines = ex.exec_command
      users = ex.parseFor('wifi users')
      locals[:local_data][:users]          = {}
      locals[:local_data][:users][:online] = users[2] if users.kind_of? Array
      locals[:local_data][:clicks]         = 0
      Mazi::Model::Application.all.each do |app|
        locals[:local_data][:clicks] += app.click_counter
      end
      erb :index_main, locals: locals
    when 'admin'
      redirect 'admin_dashboard'
    when 'admin_dashboard'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_dashboard.js"
      locals[:main_body] = :admin_dashboard
      ex = MaziExecCmd.new('sh', '/root/back-end/', 'current.sh', ['-s', '-p', '-c', '-m'], @config[:scripts][:enabled_scripts], @config[:general][:mode])
      lines = ex.exec_command
      locals[:local_data][:net_info] = {}
      ssid = ex.parseFor('ssid')
      ssid.shift
      locals[:local_data][:net_info][:ssid] = ssid.join(' ') if ssid.kind_of? Array
      mode = ex.parseFor('mode')
      ex2 = MaziExecCmd.new('sh', '/root/back-end/', 'mazi-stat.sh', ['-u'], @config[:scripts][:enabled_scripts], @config[:general][:mode])
      lines = ex2.exec_command
      users = ex2.parseFor('wifi users')
      locals[:local_data][:users]           = {}
      locals[:local_data][:users][:online]  = users[2] if users.kind_of? Array
      locals[:local_data][:net_info][:mode] = mode[1] if mode.kind_of? Array
      locals[:local_data][:applications]    = Mazi::Model::Application.all
      locals[:local_data][:notifications]   = Mazi::Model::Notification.all
      locals[:local_data][:sessions]        = Mazi::Model::Session.all
      erb :admin_main, locals: locals
    when 'admin_application'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_application.js"
      locals[:main_body] = :admin_application
      locals[:local_data][:applications]  = Mazi::Model::Application.all
      locals[:local_data][:application_instances]  = Mazi::Model::ApplicationInstance.all
      erb :admin_main, locals: locals
    when 'admin_documentation'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:main_body] = :admin_documentation
      erb :admin_main, locals: locals
    when 'admin_network'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_network.js"
      locals[:main_body] = :admin_network
      ex = MaziExecCmd.new('sh', '/root/back-end/', 'current.sh', ['-s', '-p', '-c', '-m'], @config[:scripts][:enabled_scripts])
      lines = ex.exec_command
      locals[:local_data][:net_info] = {}
      ssid = ex.parseFor('ssid')
      ssid.shift
      locals[:local_data][:net_info][:ssid] = ssid.join(' ') if ssid.kind_of? Array
      channel = ex.parseFor('channel')
      locals[:local_data][:net_info][:channel] = channel[1] if channel.kind_of? Array
      password = ex.parseFor('password')
      locals[:local_data][:net_info][:password] = password[1] if password.kind_of? Array
      mode = ex.parseFor('mode')
      locals[:local_data][:net_info][:mode] = mode[1] if mode.kind_of? Array
      ex2 = MaziExecCmd.new('sh', '/root/back-end/', 'antenna.sh', ['-a'], @config[:scripts][:enabled_scripts])
      locals[:local_data][:net_info][:second_antenna] = ex2.exec_command.last
      ex3 = MaziExecCmd.new('sh', '/root/back-end/', 'antenna.sh', ['-l'], @config[:scripts][:enabled_scripts])
      locals[:local_data][:net_info][:available_ssids] = ex3.exec_command
      locals[:local_data][:net_info][:available_ssids].map! {|ssid| ssid.gsub('ESSID:', '').gsub('"', '')}
      locals[:local_data][:net_info][:available_ssids].reject! {|ssid| ssid.empty?}
      erb :admin_main, locals: locals
    when 'admin_configuration'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_network.js"
      locals[:js] << "js/jscolor.min.js"
      locals[:main_body] = :admin_configuration
      locals[:local_data][:portal_configuration] = @config[:portal_configuration]
      locals[:local_data][:config_files] = getAllConfigSaves
      erb :admin_main, locals: locals
    when 'admin_notification'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_notification.js"
      locals[:main_body] = :admin_notification
      locals[:local_data][:notifications] = Mazi::Model::Notification.all
      erb :admin_main, locals: locals
    when 'admin_snapshot'
      unless authorized?
        MaziLogger.debug "Not authorized"
        session['error'] = nil
        redirect '/admin_login'
      end
      locals[:js] << "js/admin_snapshot.js"
      locals[:main_body] = :admin_snapshot
      locals[:local_data][:dbs] = getAllDBSnapshots
      erb :admin_main, locals: locals
    when 'admin_login'
      locals[:main_body] = :admin_login
      erb :admin_main, locals: locals
    when 'admin_logout'
      locals[:main_body] = :admin_login
      session[:username] = nil
      erb :admin_main, locals: locals
    else
      MaziLogger.warn "#{index} is not supported." unless index == 'favicon.ico'
    end
  end 

  # admin login post request
  post '/admin_login/?' do
    MaziLogger.debug "request: post/admin_login from ip: #{request.ip} creds: #{params.inspect}"
    unless valid_admin_credentials?(params['username'], params['password'])
      session['error'] = 'Password and username missmatch!'
      redirect '/admin_login' 
    end
    MaziLogger.debug "valid credential"
    session[:username] = params['username']
    redirect '/admin'
  end

  # admin login post request
  delete '/admin_login/?' do
    session[:username] = nil
    redirect '/admin'
  end

  # admin create application
  post '/application/?' do
    MaziLogger.debug "request: post/application from ip: #{request.ip} creds: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    if params['instance']
      e = Mazi::Model::ApplicationInstance.validate(params)
      unless e.nil?
        MaziLogger.debug "invalid param #{e}"
        session['error'] = e
        redirect '/admin_application'
      end
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode create app"
        session['error'] = "This portal runs on Demo mode! This action would have created a new application."
        redirect '/admin_application'
      end

      a =  Mazi::Model::ApplicationInstance.create(params)
    else
      e = Mazi::Model::Application.validate(params)
      unless e.nil?
        MaziLogger.debug "invalid param #{e}"
        session['error'] = e
        redirect '/admin_application'
      end
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode create app"
        session['error'] = "This portal runs on Demo mode! This action would have created a new application."
        redirect '/admin_application'
      end

      a =  Mazi::Model::Application.create(params)
    end
    redirect '/admin_application'
  end

  # admin edit application
  post '/application/edit/?' do
    MaziLogger.debug "request: put/application from ip: #{request.ip} params: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    if params['instance']
      e = Mazi::Model::ApplicationInstance.validate_edit(params)
      unless e.nil?
        MaziLogger.debug "invalid param #{e}"
        session['error'] = e
        redirect '/admin_application'
      end
      id = params['id']
      app =  Mazi::Model::ApplicationInstance.find(id: params['id'].to_i)
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode edit app"
        session['error'] = "This portal runs on Demo mode! This action would have edited the '#{app.name}' application."
        redirect '/admin_application'
      end
      app.name        = params['name'] if params['name']
      app.url         = params['url'] if params['url']
      app.description = params['description'] if params['description']
      app.enabled     = params['enabled'] if params['enabled']
      app.save
    else
      e = Mazi::Model::Application.validate_edit(params)
      unless e.nil?
        MaziLogger.debug "invalid param #{e}"
        session['error'] = e
        redirect '/admin_application'
      end
      id = params['id']
      app =  Mazi::Model::Application.find(id: params['id'].to_i)
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode edit app"
        session['error'] = "This portal runs on Demo mode! This action would have edited the '#{app.name}' application."
        redirect '/admin_application'
      end
      app.name        = params['name'] if params['name']
      app.url         = params['url'] if params['url']
      app.description = params['description'] if params['description']
      app.enabled     = params['enabled'] if params['enabled']
      app.save
    end
    redirect '/admin_application'
  end

  # admin delete application
  delete '/application/:id/?' do |id| 
    MaziLogger.debug "request: delete/application from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    elsif @config[:general][:mode] == 'demo'
      MaziLogger.debug "Demo mode delete app"
      session['error'] = nil
      {error: "This portal runs on Demo mode! This action would have deleted an existing application.", id: id}.to_json
    else
      app = Mazi::Model::Application.find(id: id)
      app.destroy
      {result: 'OK', id: id}.to_json
    end
  end

  # admin delete application
  delete '/application/:id/instance/?' do |id| 
    MaziLogger.debug "request: delete/application from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    elsif @config[:general][:mode] == 'demo'
      MaziLogger.debug "Demo mode delete app"
      session['error'] = nil
      {error: "This portal runs on Demo mode! This action would have deleted an existing application.", id: id}.to_json
    else
      app = Mazi::Model::ApplicationInstance.find(id: id)
      app.destroy
      {result: 'OK', id: id}.to_json
    end
  end

  # toggles application enable disable
  put '/application/:id/?' do |id|
    MaziLogger.debug "request: put/application from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    else
      app = Mazi::Model::Application.find(id: id)
      app.enabled = !app.enabled 
      app.save
      {result: 'OK', id: id}.to_json
    end
  end

  # toggles application enable disable
  put '/application/:id/instance/?' do |id|
    MaziLogger.debug "request: put/application from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    else
      app = Mazi::Model::ApplicationInstance.find(id: id)
      app.enabled = !app.enabled 
      app.save
      {result: 'OK', id: id}.to_json
    end
  end

  # application status/start/stop
  put '/application/:id/action/:action/?' do |id, action|
    MaziLogger.debug "request: put/application from ip: #{request.ip} id: #{id} action: #{action}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    elsif @config[:general][:mode] == 'demo'
      MaziLogger.debug "Demo mode app acion"
      session['error'] = "This portal runs on Demo mode! This would have run the action '#{action}' to an existing application."
      {error: "This portal runs on Demo mode! This would have run the action '#{action}' to an existing application.", id: id}.to_json
    else
      app = Mazi::Model::Application.find(id: id)
      res = 'FAIL'
      case action
      when 'start'
        res = app.start
      when 'stop'
        res = app.stop
      when 'status'
        res = app.status
      end
      {result: res, id: id}.to_json
    end
  end

  # application counter +1
  put '/application/:id/click_counter/?' do |id|
    MaziLogger.debug "request: put/application from ip: #{request.ip} id: #{id}"
    app = Mazi::Model::ApplicationInstance.find(id: id)
    app.application.click_counter += 1 
    app.click_counter = app.click_counter + 1
    app.save
    {result: 'OK', id: id}.to_json
  end

  # application counter reset
  delete '/application/:id/click_counter/?' do |id|
    MaziLogger.debug "request: delete/application/click_counter from ip: #{request.ip} creds: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      return {error: 'Not Authorized!', id: id}.to_json
    end

    if id == 'all'
      Mazi::Model::Application.all.each do |app|
        app.click_counter = 0
        app.save
      end
    else
      app = Mazi::Model::Application.find(id: id)
      app.click_counter = 0
      app.save
    end
    {result: 'OK', id: id}.to_json
  end

  # admin create notification
  post '/notification/?' do
    MaziLogger.debug "request: post/notification from ip: #{request.ip} creds: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end

    a =  Mazi::Model::Notification.create(params)
    redirect '/admin_notification'
  end

  # admin edit notification
  post '/notification/edit/?' do
    MaziLogger.debug "request: put/notification from ip: #{request.ip} params: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    id = params['id']
    notif         =  Mazi::Model::Notification.find(id: params['id'].to_i)
    notif.title   = params['title'] if params['title']
    notif.body    = params['body'] if params['body']
    notif.enabled = params['enabled'] if params['enabled']
    notif.save
    redirect '/admin_notification'
  end

  # admin delete notification
  delete '/notification/:id/?' do |id| 
    MaziLogger.debug "request: delete/notification from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    else
      notif = Mazi::Model::Notification.find(id: id)
      notif.destroy
      {result: 'OK', id: id}.to_json
    end
  end

  # toggles notification enable disable
  put '/notification/:id/?' do |id|
    MaziLogger.debug "request: put/notification from ip: #{request.ip} id: #{id}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!', id: id}.to_json
    else
      notif = Mazi::Model::Notification.find(id: id)
      notif.enabled = !notif.enabled 
      notif.save
      {result: 'OK', id: id}.to_json
    end
  end

  # toggles notification read just in session
  put '/notification/:id/read/?' do |id|
    MaziLogger.debug "request: put/notification from ip: #{request.ip} id: #{id}"
    session[:notifications_read] << id.to_i
    {result: 'OK', id: id}.to_json
  end

  # executing a script
  post '/exec/?' do
    MaziLogger.debug "request: post/exec from ip: #{request.ip} params: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    env = params['env']
    path = params['path'] || @config[:scripts][:backend_scripts_folder]
    cmd = "#{params['cmd']}"
    case cmd
    when 'wifiap.sh'
      args = []
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode exec script"
        md, vl = params['ssid'] ? ['ssid', params['ssid']] : params['channel'] ? ['channel', params['channel']] : params['password'] ? ['password', params['password']] : ['wpa', 'off']
        session['error'] = "This portal runs on Demo mode! This action would have changed the '#{md}' to '#{vl}'"
      end
      args << "-s '#{params['ssid']}'" if params['ssid']
      args << "-c #{params['channel']}" if params['channel']
      args << "-p #{params['password']}" if params['password']
      args << "-w off" if args.empty? && (params['password'].nil? || params['password'].empty?)
    when 'internet.sh'
      args = []
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode exec script"
        session['error'] = "This portal runs on Demo mode! This action would have changed the 'network mode' to '#{params['mode']}'" if params['mode']
      end
      args << "-m #{params['mode']}" if params['mode']
      redirect '/admin_network' if args.empty?
    when 'antenna.sh'
      args = []
      if @config[:general][:mode] == 'demo'
        MaziLogger.debug "Demo mode exec script"
        session['error'] = "This portal runs on Demo mode! This action would have changed the 'network mode' to '#{params['mode']}'" if params['mode']
      end
      args << "-s #{params['ssid']}" if params['ssid']
      args << "-p #{params['password']}" unless params['password'].nil? || params['password'].empty?
    else
      args = []
    end
    begin
      ex = MaziExecCmd.new(env, path, cmd, args, @config[:scripts][:enabled_scripts])
      lines = ex.exec_command
      redirect '/admin_network'
    rescue ScriptNotEnabled => e
      MaziLogger.debug "Not enabled script '#{cmd}'"
      session['error'] = "#{cmd} is not enabled"
      redirect '/admin'
    end
  end

  # saving configurations
  post '/conf/?' do
    MaziLogger.debug "request: post/conf from ip: #{request.ip} params: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    if params['reset']
      changePortalConfigToDefault
      writeConfigFile
      redirect '/admin_configuration'
    elsif params['save']
      saveTheme(params[:filename])
      redirect '/admin_configuration'
    elsif params['load']
      loadTheme(params[:filename])
      redirect '/admin_configuration'
    end
    data = {}
    data[:title]                     = params['title'] unless params['title'].nil? || params['title'].empty?
    data[:applications_title]        = params['applications_title'] unless params['applications_title'].nil?  || params['applications_title'].empty?
    data[:applications_subtitle]     = params['applications_subtitle'] unless params['applications_subtitle'].nil?  || params['applications_subtitle'].empty?
    data[:applications_welcome_text] = params['applications_welcome_text'] unless params['applications_welcome_text'].nil?  || params['applications_welcome_text'].empty?
    data[:side_panel_color]          = params['side_panel_color'] unless params['side_panel_color'].nil?  || params['side_panel_color'].empty?
    data[:side_panel_active_color]   = params['side_panel_active_color'] unless params['side_panel_active_color'].nil?  || params['side_panel_active_color'].empty?
    data[:top_panel_color]           = params['top_panel_color'] unless params['top_panel_color'].nil?  || params['top_panel_color'].empty?
    data[:top_panel_active_color]    = params['top_panel_active_color'] unless params['top_panel_active_color'].nil?  || params['top_panel_active_color'].empty?
    unless params['applications_background_image'].nil? || params['applications_background_image'].empty?
      tempfile = params['applications_background_image'][:tempfile]
      filename = params['applications_background_image'][:filename]
      data[:applications_background_image] = filename
      FileUtils.cp tempfile.path, "public/images/#{filename}"
    end
    data.each do |key, value|
      changeConfigFile("portal_configuration->#{key}", value)
    end
    writeConfigFile
    redirect '/admin_configuration'
  end

  # saving configurations without a refresh
  put '/conf/?' do
    request.body.rewind
    body = JSON.parse(request.body.read)
    MaziLogger.debug "request: put/conf from ip: #{request.ip} body: #{body}"
    if !authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      {error: 'Not Authorized!'}.to_json
    else
      data = {}
      data[:title]                     = body['title'] unless body['title'].nil? || body['title'].empty?
      data[:applications_title]        = body['applications_title'] unless body['applications_title'].nil?  || body['applications_title'].empty?
      data[:applications_subtitle]     = body['applications_subtitle'] unless body['applications_subtitle'].nil?  || body['applications_subtitle'].empty?
      data[:applications_welcome_text] = body['applications_welcome_text'] unless body['applications_welcome_text'].nil?  || body['applications_welcome_text'].empty?
      data[:side_panel_color]          = body['side_panel_color'] unless body['side_panel_color'].nil?  || body['side_panel_color'].empty?
      data[:side_panel_active_color]   = body['side_panel_active_color'] unless body['side_panel_active_color'].nil?  || body['side_panel_active_color'].empty?
      data[:top_panel_color]           = body['top_panel_color'] unless body['top_panel_color'].nil?  || body['top_panel_color'].empty?
      data[:top_panel_active_color]    = body['top_panel_active_color'] unless body['top_panel_active_color'].nil?  || body['top_panel_active_color'].empty?
      data.each do |key, value|
        changeConfigFile("portal_configuration->#{key}", value)
      end
      writeConfigFile
      {result: 'OK'}.to_json
    end
  end

  # application counter reset
  delete '/session/:id/?' do |id|
    MaziLogger.debug "request: delete/session from ip: #{request.ip} creds: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      return {error: 'Not Authorized!', id: id}.to_json
    end

    if id == 'all'
      Mazi::Model::Session.all.each do |ses|
        ses.destroy
      end
    else
      ses = Mazi::Model::Session.find(id: id)
      ses.destroy
    end
    {result: 'OK', id: id}.to_json
  end

   # taking/loading snapshots
  post '/snapshot/?' do
    MaziLogger.debug "request: post/snapshot from ip: #{request.ip} params: #{params.inspect}"
    unless authorized?
      MaziLogger.debug "Not authorized"
      session['error'] = nil
      redirect '/admin_login'
    end
    if params['save']
      takeDBSnapshot(params[:snapshotname])
      redirect '/admin_snapshot'
    elsif params['load']
      loadDBSnapshot(params[:snapshotname])
      redirect '/admin_snapshot'
    end

    redirect '/admin_snapshot'
  end
end

Thin::Server.start MaziApp, '0.0.0.0', 4567


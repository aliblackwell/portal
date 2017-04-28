
module Authorizer
  def authorized?
    if @config[:general][:mode] == 'demo'
      return true
    end
    !session[:username].nil?  
  end

  def valid_admin_credentials?(username, password)
    if @config[:general][:mode] == 'demo'
      return true
    end
    username == readConfigFile[:admin][:admin_username] && password == readConfigFile[:admin][:admin_password]
  end

  def valid_password?(password)
    if @config[:general][:mode] == 'demo'
      return true
    end
    password == readConfigFile[:admin][:admin_password]
  end

  def first_time?
    readConfigFile[:admin][:admin_password] == '1234'
  end
end
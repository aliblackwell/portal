require 'open3'

class MaziExecCmd
  class ScriptNotEnabled < StandardError 
  end

  def initialize(env, path, cmd, args=[], enabled_scripts=[], demo=false)
    @enabled_scripts = enabled_scripts
    @demo = demo
    raise ScriptNotEnabled unless enabled?(cmd)
    @cmd = cmd
    @env = env
    @args = args
    @path = path
    @output = []
  end

  def enabled?(cmd)
    return true if @enabled_scripts.include?(cmd)
    false
  end

  def exec_command
    return demoExec if @demo == 'demo'
    command = "#{@env} #{@path}#{@cmd} #{@args.join(' ')}"
    MaziLogger.debug "$ #{command}"
    @output = []
    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
      while line = stdout.gets
        MaziLogger.debug "> #{line.strip}"
        @output << line.strip
      end
    end
    @output
  end

  def parseFor(token, splitter=' ')
    return demoParse(token, splitter) if @demo == 'demo'
    @output.each do |line|
      return line.split(splitter) if line.include? token
    end
    false
  end

  def demoExec
    case @cmd
    when 'wifiap.sh'
      'OK'
    when 'current.sh'
      'OK'
    when 'internet.sh'
      'OK'
    when 'antenna.sh'
      'OK'
    when 'mazi-app.sh'
      'OK'
    when 'mazi-stat.sh'
      'wifi users 3'
    end
  end

  def demoParse(token, splitter)
    case @cmd
    when 'wifiap.sh'
      'OK'
    when 'current.sh'
      case token
      when 'ssid'
        return ['ssid', 'MAZIZONE']
      when 'channel'
        return ['channel', '6']
      when 'password'
        return ['password', '123456789']
      when 'mode'
        return ['mode', 'offline']
      end
    when 'internet.sh'
      'OK'
    when 'antenna.sh'
      'OK'
    when 'mazi-app.sh'
      'OK'
    when 'mazi-stat.sh'
      return ['wifi', 'users', '3']
    end
  end
end

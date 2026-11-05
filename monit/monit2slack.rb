#!/diska/home/pipeline/miniforge3/envs/soxspipe/bin/ruby
# encoding: UTF-8

WEBHOOK_FILE = '/diska/home/pipeline/monit/slack-webhook-url'
LOG_FILE = '/diska/home/pipeline/monit/monit.log'
NETWORK_TIMEOUT_SECONDS = 10

def read_webhook
  File.exist?(WEBHOOK_FILE) ? File.read(WEBHOOK_FILE).strip : ''
end

# SLACK REPORTING MUST NEVER MAKE MONIT FAIL, SO A PROBLEM ONLY WRITES TO THE LOG
def log_problem(message)
  hidden = message.gsub(%r{/services/\S+}, '/services/<hidden>')
  File.open(LOG_FILE, 'a') { |file| file.puts "[#{Time.now}] monit2slack: #{hidden}" }
rescue StandardError
  nil
end

def parse_options(argv)
  opts = {}

  @parser = OptionParser.new do |o|
    o.on '--channel CHANNEL', "name of the channel to post to" do |arg|
      opts[:channel] = arg
    end

    o.on '--name NAME', "name of the bot" do |arg|
      opts[:name] = arg
    end

    o.on '--status STATUS', "kind of message" do |arg|
      opts[:status] = arg.upcase+"!"
    end

    o.on '--color #HEX_COLOR', "color of the message" do |arg|
      opts[:color] = arg
    end

    o.on '--slack-url URL', "URL to post to" do |arg|
      opts[:slack_url] = arg
    end

    o.on '--monit-url URL', "URL of Monit" do |arg|
      opts[:monit_url] = arg
    end

    o.on '--event EVENT', "text of the message" do |arg|
      opts[:text] = arg
    end

  end

  @parser.banner = "post_to_slack [options]"
  # @parser.on_tail "-h", "--help", "Show help" do
  #   logger.info @parser
  #   die 1
  # end
  @parser.parse!(argv)

  opts[:channel]   ||= ENV.fetch('CHANNEL') { '#monit-mac' }
  opts[:text]   ||= ENV.fetch('TEXT') { '' }
  opts[:name]      ||= ENV.fetch('NAME') { 'Monit' }
  opts[:status]    ||= ENV.fetch('STATUS') { '' }
  opts[:slack_url] ||= ENV.fetch('SLACK_URL') { read_webhook }
  opts[:monit_url] ||= ENV.fetch('MONIT_URL') { "http://#{`hostname -f`.chomp}:8080/" }
  opts[:event]  ||= ENV.fetch('MONIT_EVENT') { '' }
  opts[:service] ||= ENV.fetch('MONIT_SERVICE') { '' }
  opts[:desc] ||= ENV.fetch('MONIT_DESCRIPTION') { '' }
  opts[:date] ||= ENV.fetch('MONIT_DATE') { '' }
  opts[:host] ||= ENV.fetch('MONIT_HOST') { '' }
  
  opts[:color] ||= case opts[:status]
  when 'OK!'
    '#859900'
  when 'ERROR!'
    '#dc322f'
  when 'WARNING!'
    '#cb4b16'
  else
    '#859900'
  end

  opts
end

def format_payload(opts = {})
{
  "channel" => opts[:channel],
  "username" => opts[:name],
  "attachments" => [{
    "fallback" => "#{opts[:text]}\n#{opts[:monit_url]}#{opts.fetch(:service){'#'}}",
    "color" => opts[:color],
    "fields" => [{
      "title" => "#{opts[:status]}",
      "value" => opts[:text] + " on host `" + opts[:host] + "` as:\n> " +  opts[:desc],
      "short" => false
    },{
      "value" => "<#{opts[:monit_url]}#{opts.fetch(:service){'#'}}|more info>",
      "short" => false
    }]
  }]
}
end

def post(url, payload)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = NETWORK_TIMEOUT_SECONDS
  http.read_timeout = NETWORK_TIMEOUT_SECONDS
  http.ca_file = '/diska/home/pipeline/miniforge3/envs/soxspipe/ssl/cert.pem'
  http.post("#{uri.path}?#{uri.query}", payload.to_json)  
end

begin
  require 'optparse'
  require 'net/http'
  require 'json'
  require 'openssl'

  s = OpenSSL::X509::Store.new.tap(&:set_default_paths)
  OpenSSL::SSL::SSLContext.send(:remove_const, :DEFAULT_CERT_STORE) rescue nil
  OpenSSL::SSL::SSLContext.const_set(:DEFAULT_CERT_STORE, s.freeze)

  options = parse_options(ARGV)
  url = options.fetch(:slack_url)
  if url.empty?
    log_problem("no Slack webhook in #{WEBHOOK_FILE}, so this alert was not sent: #{options[:text]}")
  else
    response = post(url, format_payload(options))
    log_problem("Slack answered #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  end
rescue StandardError, ScriptError => e
  log_problem("could not send the alert: #{e.class}: #{e.message}")
end

exit 0

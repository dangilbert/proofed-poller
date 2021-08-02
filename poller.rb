require 'bundler/inline'
require 'time'
require 'yaml'

gemfile do
  source 'https://rubygems.org'
  gem 'json', require: false
  gem "http"
  gem 'logger'
  gem 'nokogiri'
end

proofed_dir = "#{ENV['HOME']}/.config/proofed"
$cookie_file = "#{proofed_dir}/cookies"
$id_file = "#{proofed_dir}/documents"
$time_file = "#{proofed_dir}/documents_time"
$last_update_time = Time.new.utc.iso8601

default_config = {
  :min_words => 500
}

config_file = default_config.merge(YAML.load(File.read("config.yml")))

$pushover_token = config_file[:pushover_token]
$pushover_user = config_file[:pushover_user]
$pushover_devices = config_file[:pushover_devices]
$pushover_error_devices = config_file[:pushover_error_devices]

$min_words = config_file[:min_words]

$proofed_user = config_file[:proofed_username]
$proofed_password = config_file[:proofed_password]

puts "Last update time: #{$last_update_time}"
puts "Setting min word limit to: #{$min_words}"

logger = Logger.new(STDOUT)
$http = HTTP #.use(logging: {logger: logger})
$cookies = []

require 'fileutils'

dirname = File.dirname($cookie_file)
puts "Checking if #{dirname} exists"
unless File.directory?(dirname)
  puts "Creating dir: #{dirname}"
  FileUtils.mkdir_p(dirname)
end
FileUtils.touch($id_file)

def login

  # Get initial cookies
  puts "Fetching initial csrf cookies"
  launchScreenResponse = $http.get('https://editor.getproofed.com/dashboard')

  $cookies = launchScreenResponse.headers["set-cookie"]
  csrf_cookie = $cookies.find { |cookie| cookie.include? "csrfToken" }
  startSubstring = csrf_cookie.index('=') + 1
  endSubstring = csrf_cookie.index(';') - csrf_cookie.index('=') - 1
  csrf_token = csrf_cookie[startSubstring, endSubstring]

  # Perform login
  puts "Logging in"
  loginResponse = $http.headers(:Cookie => $cookies.join("; "))
      .post('https://editor.getproofed.com/', :form => {
    :username => $proofed_user,
    :password => $proofed_password,
    :_csrfToken => csrf_token,
    :_method => "POST"
    }
  )

  if loginResponse.code != 302
    puts "Login failed - #{loginResponse.body}"
    return false
  end

  loginCookie = loginResponse.headers["set-cookie"]
  puts loginCookie
  $cookies = $cookies.map { |cookie|
    if cookie.include? "CAKEPHP"
      loginCookie
    else
      cookie
    end
  }

  $cookies = $cookies.flatten.reject { |cookie|
    cookie.include? "deleted"
  }.drop(1)

  puts "Storing cookies"
  File.open($cookie_file, 'w') {
    |file| file.puts($cookies)
  }

  return true

end

def check_login_valid
  begin
    puts "Fetching dashboard"
    dashboardResponse = $http.headers(:Cookie => $cookies.join("; "))
        .get('https://editor.getproofed.com/dashboard')

    return dashboardResponse.code == 200
  rescue => error
    send_error_push(error.message)
    raise
  end
end

def check_dashboard
  begin
    puts "Opening dashboard"

    dashboardResponse = $http.headers(:Cookie => $cookies.join("; "))
        .get('https://editor.getproofed.com/dashboard')

    if dashboardResponse.code != 200
      puts "Error fetching dashboard"
      puts "Status: #{dashboardResponse.status}"
      send_error_push("Error checking dashboard. Restart script?")
      exit
    end

    @doc = Nokogiri::HTML(dashboardResponse.body.to_s)
    # saved_page = File.read("#{ENV['HOME']}/Downloads/Archive/index.html")
    # @doc = Nokogiri::HTML(saved_page)
    documents_count_string = @doc.css("div.queue-doc-num h4").text
    
    document_count = documents_count_string["Documents in the queue: ".length].to_i
    puts "Documents: #{document_count}"
    
    if document_count > 0
      # Check the IDs
      ids = File.readlines($id_file).map { |id| id.strip }
      new_documents = @doc.css(".close-details")
      unseen_docs = []
      new_documents.each { |document|
        new_doc_id = document.css(".doc-id").text
        matches = document.css(".doc-id + td").text.match(/(\d+) words/)
        if matches.nil? then
          next
        end
        new_doc_word_count = matches.captures[0].to_i
        puts "#{new_doc_id} #{new_doc_word_count}"
        unless ids.include? new_doc_id
          if new_doc_word_count > $min_words
            unseen_docs << { :id => new_doc_id, :word_count => new_doc_word_count }
          end
        end
      }
      
      puts "New documents: #{unseen_docs}"

      File.open($id_file, "a") do |f|
        unseen_docs.each { |element| f.puts(element[:id]) }
      end
      File.open($time_file, "a") do |f|
        unseen_docs.each { |element| f.puts("#{Time.now.getutc} - #{element}") }
      end
      if unseen_docs.length > 0
        puts "Sending push notification"
        doc_lengths = unseen_docs.map { |doc| doc[:word_count] }
        send_push($pushover_devices, doc_lengths)
      end
    end
  rescue => error
    send_error_push(error.message)
    raise
  end
end

def poll
  begin
    # Start polling
    while true  do
      puts "Polling checkDocumentActivity"
      puts "Last update time: #{$last_update_time}"
      pollResponse = $http.headers(
        :Cookie => $cookies.join("; "),
        "X-Requested-With" => "XMLHttpRequest"
      )
        .get("https://editor.getproofed.com/freelancers/checkDocumentActivity", :params => { :time => $last_update_time })

      if pollResponse.code == 503
        puts "503 occurred. Sleeping 1 minute"
        send_error_push("Server down for maintenance. Retrying in 1 minute")
        sleep 60
        next
      elsif pollResponse.code == 524 || pollResponse.code == 521 || pollResponse.code == 504
        puts "Gateway timeout occurred. Either with cloudflare or proofed"
        send_error_push("Gateway timeout occurred. Retrying in 1 minute")
        sleep 60
        next
      elsif pollResponse.code != 200
        puts "Invalid response from poller"
        puts "Response code: #{pollResponse.code}"
        send_error_push("Couldn't poll. Restart script?")
        puts pollResponse.body.to_s
        exit
      end

      responseBody = JSON.parse(pollResponse.body.to_s)

      puts "Changes: #{responseBody.to_s}"
      puts "Changed: #{responseBody["status"]}"

      if responseBody["status"]
        check_dashboard()
        $last_update_time = responseBody["currentTime"]
        puts "Updated request time to: #{$last_update_time}"
      end

      sleep 10
    end
  rescue => error
    send_error_push(error.message)
    raise
  end
end

def send_push(pushover_device, word_counts = [])
  if pushover_device.nil? || pushover_device.to_s.strip.empty?
    puts "Device was empty. not sending push"
    return
  end
  pushResponse = $http.post("https://api.pushover.net/1/messages.json", :form => {
    :token => $pushover_token,
    :user => $pushover_user,
    :message => "New document(s) available with lengths: #{word_counts} words",
    :url => "https://editor.getproofed.com/dashboard",
    :device => pushover_device,
    :priority => 1
    })

    puts pushResponse.status
end

def send_error_push(error)
  pushResponse = $http.post("https://api.pushover.net/1/messages.json", :form => { 
    :token => $pushover_token, 
    :user => $pushover_user, 
    :message => "Script error: #{error}", 
    :url => "https://editor.getproofed.com/dashboard",
    :device => $pushover_error_devices
    })

    puts pushResponse.status
end

send_error_push("Starting the Proofed polling service")

# Check cookies
if File.file?($cookie_file)

  # Check the cookies are still valid
  $cookies = File.readlines($cookie_file).map { |cookie| cookie.strip }
  # Fetch the dashboard. If we get a 302 it's invalid
  puts "Loaded cookies"
  if check_login_valid()
    check_dashboard()
    poll()
  else
    if login()
      check_dashboard()
      poll()
    else
      exit
    end
  end
else
  if login()
    check_dashboard()
    poll()
  else
    exit
  end
end

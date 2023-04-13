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

$base_url = "https://editor.proofed.com"

default_config = {
  :min_words => 0
}

$min_words = ENV['MIN_WORDS'].to_i || 0

$proofed_user = ENV['PROOFED_USERNAME']
$proofed_password = ENV['PROOFED_PASSWORD']

$documents_notification_channels = ENV["DOCUMENTS_CHANNELS"]
$system_notification_channels = ENV["SYSTEM_CHANNELS"]

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
  launchScreenResponse = $http.get("#{$base_url}")

  $cookies = launchScreenResponse.headers["set-cookie"]

  # Get csrf token from the html body
  @doc = Nokogiri::HTML(launchScreenResponse.body.to_s)
  csrf_token = @doc.at('input[name="_csrfToken"]').attr('value')

  puts "CSRF Token: #{csrf_token}"
  $cookies.push("csrfToken=#{csrf_token}")

  payload = {
    :username => $proofed_user,
    :password => $proofed_password,
    :_csrfToken => csrf_token,
    :_method => "POST"
  }

  puts payload

  # Perform login
  puts "Logging in"
  loginResponse = $http.headers(:Cookie => $cookies.join("; "))
      .post("#{$base_url}", :form => payload
  )

  puts loginResponse.code

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
        .get("#{$base_url}/dashboard")

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
        .get("#{$base_url}/dashboard")

    if dashboardResponse.code != 200
      puts "Error fetching dashboard"
      puts "Status: #{dashboardResponse.status}"
      send_error_push("Error checking dashboard.")
      sleep 60
      return
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
        send_push(doc_lengths)
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
    error_count = 0
    while error_count < 10  do
      puts "Polling checkDocumentActivity"
      puts "Last update time: #{$last_update_time}"
      pollResponse = $http.headers(
        :Cookie => $cookies.join("; "),
        "X-Requested-With" => "XMLHttpRequest"
      )
        .get("#{$base_url}/freelancers/checkDocumentActivity", :params => { :time => $last_update_time })

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
        begin
          check_dashboard()
          error_count = 0
          $last_update_time = responseBody["currentTime"]
          puts "Updated request time to: #{$last_update_time}"
        rescue => error
          message = "Error fetching the dashboard. Maybe there is a redeploy happening? Waiting 1 minute before resuming polling\n\n#{error.message}"
          error_count += 1
          puts message
          send_error_push(message)
          sleep 60
          next
        end
      end

      sleep 10
    end
  rescue => error
    send_error_push(error.message)
    raise
  end
end

def send_push(word_counts = [])
  message = "New document(s) available with lengths: #{word_counts} words."
  cmd = "apprise -v --title=\"#{message}\" --body=\"Open #{$base_url}/dashboard\" #{$documents_notification_channels}"
  system(cmd)
end

def send_error_push(error)
  send_system_push("Script error", error)
end

def send_init_push()
  message = "Starting the proofed dashboard poller."
  cmd = "apprise -v --body=\"#{message}\" #{$documents_notification_channels}"
  system(cmd)
end

def send_system_push(title, message)
  cmd = "apprise -v --title=\"#{title}\" --body=\"#{message}\" #{$system_notification_channels}"
  system(cmd)
end

send_init_push()
send_system_push("Starting the Proofed polling service.", "Open #{$base_url}/dashboard")

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

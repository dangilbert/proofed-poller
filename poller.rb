require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'json', require: false
  gem "http"
  gem 'logger'
  gem 'nokogiri'
end

logger = Logger.new(STDOUT)
http = HTTP #.use(logging: {logger: logger})

# Get initial cookies
puts "Fetching initial csrf cookies"
launchScreenResponse = http.get('https://app.proofreadmyessay.co.uk/freelance')

cookies = launchScreenResponse.headers["set-cookie"]
csrf_cookie = cookies.find { |cookie| cookie.include? "csrfToken" }
startSubstring = csrf_cookie.index('=') + 1
endSubstring = csrf_cookie.index(';') - csrf_cookie.index('=') - 1
csrf_token = csrf_cookie[startSubstring, endSubstring]

# Perform login
puts "Logging in"
loginResponse = http.headers(:Cookie => cookies.join("; "))
    .post('https://app.proofreadmyessay.co.uk/freelance', :form => {
  :username => "***REMOVED***", 
  :password => "***REMOVED***", 
  :_csrfToken => csrf_token, 
  :_method => "POST"
  }
)

if loginResponse.code != 302
  puts "Login failed"
  exit
end

loginCookie = loginResponse.headers["set-cookie"]
cookies = cookies.map { |cookie|
  if cookie.include? "CAKEPHP"
    loginCookie
  else
    cookie
  end
}

puts "Login success"

puts "Opening dashboard"

dashboardResponse = http.headers(:Cookie => cookies.join("; "))
    .get('https://app.proofreadmyessay.co.uk/freelance/dashboard')

if dashboardResponse.code != 200 
  puts "Error fetching dashboard"
  exit
end

@doc = Nokogiri::HTML(dashboardResponse.body.to_s)
documents_count_string = @doc.css("div.queue-doc-num h4").text

document_count = documents_count_string["Documents in the queue: ".length].to_i
puts "Documents: #{document_count}"

# If document count > 0 send a push

# Start polling

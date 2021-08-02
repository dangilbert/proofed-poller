# A poller and notifier for the Proofed editor platform

This project will check the proofed editor dashboard for your account every 10 seconds (same interval as the website).
In the case where a document appears on your dashboard it will send you a push notification

## Setup

1. Clone the repo
2. Copy the `config.sample.yml` to `config.yml` and fill in the details for your proofed account and minimum document length you wanted to be notified about
3. Copy the `apprise.sample.yml` to `apprise.yml` and add the URLs for your devices on which you want to receive the notifications.
    - You can use any notification platform that https://github.com/caronc/apprise supports
    - The `documents` tagged URL will receive notifications when a document appears on your dashboard
    - The `system` tagged URL will receive notifications when something happens in the script, such as errors which may need your attention to resolve
3. Run `docker-compose up` in the project root

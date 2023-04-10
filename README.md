# A poller and notifier for the Proofed editor platform

This project will check the proofed editor dashboard for your account every 10 seconds (same interval as the website).
In the case where a document appears on your dashboard it will send you a push notification via apprise

## Setup

### Docker compose

- Copy the `docker-compose.yml` to where you want to launch the service from.
- Either:
  - Copy the `.env.sample` to `.env` and fill in your details. Then uncomment the `env_file` line in `docker-compose.yml`
  - OR Update `docker-compose.yml` with the required environment variables
- Run `docker compose up`

### Apprise config

The service uses Apprise to send notifications and any service supported by apprise should work.

To see how to create the service URLs to be used in the DOCUMENTS_CHANNELS and SYSTEM_CHANNELS environment variables, see here:  
https://github.com/caronc/apprise

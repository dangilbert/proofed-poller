# A poller and notifier for the Proofed editor platform

This project will check the proofed editor dashboard for your account every 10 seconds (same interval as the website).
In the case where a document appears on your dashboard it will send you a push notification

## Setup

1. Clone the repo
2. Copy the `config.sample.yml` to `config.yml` and fill in the details for your proofed account and pushover account/device
3. Run `docker-compose up` in the project root

## TODO
- Swap out pushover notifications for something like AppRise?
FROM ruby:2.6.6-alpine3.13
RUN apk add expect build-base gcc musl-dev python3-dev libffi-dev openssl-dev cargo
RUN apk add --no-cache python3 py3-pip
RUN pip install apprise

 ADD poller.rb /usr/app/poller.rb
 
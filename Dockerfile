FROM ruby:3.1.2-slim

RUN apt-get update && \
    apt-get install -y cron build-essential libcurl4-openssl-dev
COPY jfbot-crontab /etc/cron.d/jfbot-crontab
RUN chmod 0644 /etc/cron.d/jfbot-crontab && crontab /etc/cron.d/jfbot-crontab

ENV GEM_HOME="/usr/local/bundle"
ENV PATH $GEM_HOME/bin:$GEM_HOME/gems/bin:$PATH

RUN mkdir -p /var/jfbot
COPY . /var/jfbot
WORKDIR /var/jfbot

RUN bundle install

ENTRYPOINT ["cron", "-f"]

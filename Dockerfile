FROM quay.io/ukhomeofficedigital/docker-aws-cli:v0.1

RUN apk update && \
    apk upgrade && \
    apk add bash

COPY ./scripts /scripts

USER 1000

ENTRYPOINT ["scripts/start-rds.sh"]

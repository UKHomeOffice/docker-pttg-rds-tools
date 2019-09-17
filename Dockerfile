FROM quay.io/ukhomeofficedigital/docker-aws-cli:v0.1

USER root
COPY ./scripts /scripts
RUN apk update && \
    apk upgrade && \
    apk add bash && \
    apk add jq

USER 1000

CMD source ./scripts/common.sh

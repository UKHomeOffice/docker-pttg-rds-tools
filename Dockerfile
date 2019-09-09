FROM quay.io/ukhomeofficedigital/docker-aws-cli:v0.1

COPY ./scripts /scripts

USER 1000

ENTRYPOINT ["start-rds.sh"]

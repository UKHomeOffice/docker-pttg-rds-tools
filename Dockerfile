FROM quay.io/ukhomeofficedigital/docker-aws-cli:v0.1

ADD ./scripts/ /

RUN chmod a+x scripts

USER 1000

ENTRYPOINT ["start-rds.sh"]

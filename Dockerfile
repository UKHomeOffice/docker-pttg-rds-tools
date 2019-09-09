FROM quay.io/ukhomeofficedigital/docker-aws-cli:v0.1

ENV USER pttg
ENV GROUP pttg

ADD ./scripts/ /

RUN groupadd -r ${GROUP} && \
    useradd -r -g ${GROUP} ${USER} -d /

USER ${USER}

ENTRYPOINT ["start-rds.sh"]

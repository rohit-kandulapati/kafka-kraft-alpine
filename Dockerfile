FROM alpine:3.20

ENV KAFKA_HOME=/opt/kafka 
ENV PATH="${KAFKA_HOME}/bin:${PATH}"

RUN apk add --no-cache \
    openjdk8-jre \
    bash \
    tar \
    gettext \
    && rm -rf /var/cache/apk/*

RUN addgroup -g 1001 kafka && \
    adduser -D -u 1001 -G kafka kafka

RUN mkdir -p ${KAFKA_HOME} /var/kafka-logs && \
    chown -R kafka:kafka ${KAFKA_HOME} /var/kafka-logs

COPY kafka_2.12-3.7.2.tgz /tmp/kafka.tgz

RUN tar -xzf /tmp/kafka.tgz -C ${KAFKA_HOME} --strip-components=1 && \
    rm /tmp/kafka.tgz && \
    chown -R kafka:kafka ${KAFKA_HOME}

## the configfile will be generated dynamically

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT [ "/usr/local/bin/docker-entrypoint.sh" ]

USER kafka
WORKDIR ${KAFKA_HOME}
EXPOSE 9092 9093 

CMD ["kafka-server-start.sh", "/opt/kafka/config/server.properties"]
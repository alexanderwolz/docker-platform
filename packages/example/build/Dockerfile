FROM alpine:3.17.2

RUN apk add --no-cache bash

WORKDIR /home/root

COPY example.sh example.sh

#run forever
ENTRYPOINT ["tail", "-f", "/dev/null"]
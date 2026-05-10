# source image
FROM alpine:latest

LABEL build_version="2026.05.09"
LABEL maintainer="blomstertj"

# install bash and natpmp
RUN echo "**** install packages ****"
RUN apk add --no-cache bash curl libnatpmp

RUN echo "**** cleanup ****"
RUN rm -rf /tmp/*

COPY alpine-nat-pmp/proton-natpmp-keepalive.sh /
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/proton-natpmp-keepalive.sh" ]

FROM nginx:1.19-alpine AS base

ENV BYPASS_CACHE 0
ENV IMAGINARY_URL "http://imaginary:9000"

RUN mkdir /certs
RUN mkdir /cache

RUN apk add dnsmasq

FROM base AS certs

RUN apk add openssl

RUN openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -keyout /certs/server.key -out /certs/server.crt \
        -subj "/C=DK/ST=Images/L=World/O=Dis/CN=imaginary"

FROM base AS prod

COPY --from=certs /certs/* /certs/
COPY nginx.conf /etc/nginx/nginx.conf
COPY imaginary.conf /etc/nginx/imaginary.conf
COPY init /init

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["/init"]

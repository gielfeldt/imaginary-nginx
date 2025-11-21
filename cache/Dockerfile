FROM nginx:1.25-alpine AS base

ENV BYPASS_CACHE 0
ENV IMAGINARY_URL "http://imaginary:9000"

RUN mkdir /certs /cache && \
    chown -R 101:101 /certs /cache && \
    chmod 700 /certs && \
    chmod 755 /cache

RUN apk add --no-cache dnsmasq

FROM base AS certs

RUN apk add --no-cache openssl

RUN openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -keyout /certs/server.key -out /certs/server.crt \
        -subj "/C=DK/ST=Images/L=World/O=Imaginary/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

FROM base AS prod

COPY --from=certs /certs/* /certs/
COPY nginx.conf /etc/nginx/nginx.conf
COPY imaginary.conf /etc/nginx/imaginary.conf
COPY init /init

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["/init"]

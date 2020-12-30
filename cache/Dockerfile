FROM nginx:1.19-alpine

ENV BYPASS_CACHE 0
ENV IMAGINARY_URL "http://imaginary:9000"

RUN mkdir /certs

COPY nginx.conf /etc/nginx/nginx.conf
COPY imaginary.conf /etc/nginx/imaginary.conf
COPY init /init

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["/init"]

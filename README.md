
# Development

To run:

```bash
docker-compose up -d
```

# Starting

docker run -d --name imaginary h2non/imaginary:1.2.4 -concurrency 10 -enable-url-source
docker run -d -p80:80 --link imaginary gielfeldt/imaginary-nginx

# Using

See usage at https://github.com/h2non/imaginary

```bash
curl -I 'http://localhost:<port>/thumbnail?width=640&quality=95&url=https://homepages.cae.wisc.edu/~ece533/images/baboon.png'
```

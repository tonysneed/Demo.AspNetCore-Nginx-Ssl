# ASP.NET Core 3.0 Web API with Nginx Reverse Proxy for SSL

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- .NET Core SDK version 3.0 or greater

## Web API Application

- Create a new Web API application.

```
mkdir HelloAspNetCore3 && cd HelloAspNetCore3
dotnet new sln --name HelloAspNetCore3
dotnet new webapi --name HelloAspNetCore3.Api
dotnet sln add HelloAspNetCore3.Api/HelloAspNetCore3.Api.csproj
```

- Insert the following code in the `Configure` method of `Startup`, after `app.UseDeveloperExceptionPage`.

```csharp
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});
```

## Web API Container

- Add **Api.Dockerfile** to the Web API project.

```docker
FROM mcr.microsoft.com/dotnet/core/aspnet:3.0-alpine AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/core/sdk:3.0-alpine AS build
WORKDIR /src
COPY ["HelloAspNetCore3.Api.csproj", "./"]
RUN dotnet restore "./HelloAspNetCore3.Api.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "HelloAspNetCore3.Api.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "HelloAspNetCore3.Api.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENV ASPNETCORE_URLS http://*:5000
ENTRYPOINT ["dotnet", "HelloAspNetCore3.Api.dll"]
```

- Open terminal at Web API project folder, build then run the container image.

```
docker build -t hello-aspnetcore3 -f Api.Dockerfile .
docker run -d -p 5000:5000 --name hello-aspnetcore3  hello-aspnetcore3
```

- Browse to: `http://localhost:5000/weatherforecast`

> **Note**: You need to build and run individual containers only to validate the image and application. The container and image can then me removed.

- Stop and remove the container and image.

```
docker rm -f hello-aspnetcore3
docker rmi hello-aspnetcore3
```

## Nginx Container

- Add **Nginx** folder at the solution level.
- Add **nginx.conf** file.

```conf
worker_processes 1;

events { worker_connections 1024; }

http {

    sendfile on;

    upstream web-api {
        server api:5000;
    }

    server {
        listen 80;
        server_name $hostname;
        location / {
            proxy_pass         http://web-api;
            proxy_redirect     off;
            proxy_http_version 1.1;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header   Upgrade $http_upgrade;
            proxy_set_header   Connection keep-alive;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
            proxy_set_header   X-Forwarded-Host $server_name;
        }
    }
}
```

- Add **Nginx.Dockerfile** file.

```docker
FROM nginx:latest

COPY nginx.conf /etc/nginx/nginx.conf
```

## Docker Compose

- Add **docker-compose.yml** at the solution level.

```yml
version: "3.7"

services:

  reverseproxy:
    build:
      context: ./Nginx
      dockerfile: Nginx.Dockerfile
    ports:
      - "80:80"
    restart: always

  api:
    depends_on:
      - reverseproxy
    build:
      context: ./HelloAspNetCore3.Api
      dockerfile: Api.Dockerfile
    expose:
      - "5000"
    restart: always
```

> **Note**: Specifying `depends_on` for the `api` service places it in the same bridge network as `reverseproxy`, so that nginx can forward requests to it via `proxy_pass`. For this to work, the `api` service name must match the upstream server specified in the `nginx.conf` file. While `reverseproxy` is exposed to the host via `ports`, `api` is only exposed to `reverseproxy`.

- Build **api** and **reverseproxy** images.

```
docker-compose build
```

- Run the containers via `docker-compose`.

```
docker-compose up -d
```

- Browse to `http://localhost/weatherforecast`
- Stop the containers.

```
docker-compose down
```

## SSL Setup

- Add **localhost.conf** to **Nginx** folder.

```conf
[req]
default_bits       = 2048
default_keyfile    = localhost.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
countryName                 = Country Name (2 letter code)
countryName_default         = US
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = Texas
localityName                = Locality Name (eg, city)
localityName_default        = Dallas
organizationName            = Organization Name (eg, company)
organizationName_default    = localhost
organizationalUnitName      = organizationalunit
organizationalUnitName_default = Development
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_default          = localhost
commonName_max              = 64

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = localhost
DNS.2   = 127.0.0.1
```

- Open terminal at **Nginx** folder to create certificate using OpenSSL.
  - Enter `Strong@Passw0rd` when prompted for export password.

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -config localhost.conf -passin pass:Strong@Passw0rd
sudo openssl pkcs12 -export -out localhost.pfx -inkey localhost.key -in localhost.crt
```

- Add the certificate to the trusted CA root store.
  - Open the KeyChain Access app (spotlight on MacOS).
  - Select System in the Keychains pane, and drag your .pfx certificate into the certificate list pane.
  - Double-click your certificate, and under the trust section select Always Trust.
- Update **Nginx.Dockerfile** to copy public and private key files.

```docker
COPY localhost.crt /etc/ssl/certs/localhost.crt
COPY localhost.key /etc/ssl/private/localhost.key
```

- Update **nginx.conf** to load certificate key pair.

```conf
worker_processes 1;

events { worker_connections 1024; }

http {

    sendfile on;

    upstream web-api {
        server api:5000;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            return 301 https://$host$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate /etc/ssl/certs/localhost.crt;
        ssl_certificate_key /etc/ssl/private/localhost.key;

        location / {
            proxy_pass         http://web-api;
            proxy_redirect     off;
            proxy_http_version 1.1;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header   Upgrade $http_upgrade;
            proxy_set_header   Connection keep-alive;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
            proxy_set_header   X-Forwarded-Host $server_name;
        }
    }
}
```

- Edit **docker-compose.yml** to map `reverseproxy` to port 443.

```docker
ports:
  - "80:80"
  - "443:443"
```

- Build images and run containers.

```
docker-compose build
docker-compose up -d
```

- Browse to: http://localhost/weatherforecast
- Stop containers.

```
docker-compose down
```

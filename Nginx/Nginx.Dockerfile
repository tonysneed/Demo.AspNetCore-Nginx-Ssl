FROM nginx:latest

COPY nginx.conf /etc/nginx/nginx.conf

# docker build -t nginx-reverseproxy -f Nginx.Dockerfile .
# docker run -d -p 80:80 --name nginx-reverseproxy  nginx-reverseproxy

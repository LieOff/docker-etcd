# appcelerator/etcd

etcd3 image based on Alpine Linux

## Usage

    docker run -d -p 2379:2379 -p 2380:2380 appcelerator/etcd

You can set the listen URLs for clients and peers:

    docker run -d -p 2379:2379 -p 2380:2380 appcelerator/etcd --listen-client-urls http://localhost:2379 --advertise-client-urls http://localhost:2379 --listen-peer-urls=http://localhost:2380 --initial-advertise-peer-urls=http://localhost:2380

## Heath check

the container is started with a ping message (pong), the health check consists in getting the ping message every 5 seconds.

## Tags

- 3.0, 3.0.15
- 3.1, 3.1.5, latest

# interact with letterbox using nodejs

A small set of modules to send UDP packets that consist of the contents of a node-canvas to the octopus server.

## setup

run `npm install`

## run examples

### render

stuff on canvas and send contents to octopus

- `node render.js [<host>]`

### scan image

load image stuff on canvas and send contents to octopus
preserves the image ratio and scans from top to bottom

- `node scan-image.js <path-to-image> [<host>]`


## convert protobuf schema 

There is a shell script to convert the latest .proto file to an es6 module used with all example scripts.
Calling this will output / overwrite [packet.js](./packet.js).

```
./convert-proto.js ../protobuf/schema.proto
```


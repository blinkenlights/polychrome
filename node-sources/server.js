import dgram from 'node:dgram'
import { encodePacket, decodePacket } from './packet.js';

export const client = dgram.createSocket('udp4');

let listeners = [
    msg => console.log(msg)
]

export function addListener (f) {
    listeners.push(f)
} 

client.on('message', function (msg, info) {
    const decoded = decodePacket(msg)
    listeners.map(f => f(decoded))
});


export const demoServer = 'remote-octopus.fly.dev'
export const port = 2342

export function frame (data, palette) {
    return encodePacket({ frame: { data, palette } })
}

export function rgbFrame (data) {
    return encodePacket({ rgb_frame: { data } })
}

export async function send(server, packet) {
    return new Promise((resolve, reject) => {
        client.send(packet, port, server, function(err, bytes) {
            if (err) reject(err)
            resolve(bytes)
        })
    })
}

export function close () {
    client.close()
}

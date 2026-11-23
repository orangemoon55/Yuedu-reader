#!/usr/bin/env python3
"""Loopback-only synthetic manga for native cache-button end-to-end tests (no accounts)."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import binascii
import json
import struct
import zlib

PORT=18779
HOST=f'http://localhost:{PORT}'

def png():
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',binascii.crc32(kind+data)&0xffffffff)
    width,height=160,260
    rows=b''.join(b'\x00'+bytes(([32,126,184] if y<130 else [214,147,61])*width) for y in range(height))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')

IMAGE=png()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url=urlparse(self.path)
        token=parse_qs(url.query).get('t',[''])[0]
        if url.path=='/health':answer={'ok':True}
        elif url.path=='/book':answer={'name':'Offline cache '+token,'author':'Synthetic author','cover':HOST+'/image.png','toc':HOST+'/toc?t='+token}
        elif url.path=='/toc':answer={'chapters':[{'title':f'第{i+1}话','url':HOST+f'/chapter/{i}?t='+token} for i in range(2)]}
        elif url.path.startswith('/chapter/'):
            answer={'title':'Synthetic chapter','content':f'<img src="{HOST}/image.png?t={token}">'}
        elif url.path=='/image.png':
            self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Content-Length',str(len(IMAGE)));self.end_headers();self.wfile.write(IMAGE);return
        else:
            self.send_error(404);return
        data=json.dumps(answer,ensure_ascii=False).encode()
        self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def log_message(self, fmt, *args):
        print('fixture',self.path.split('?')[0],fmt%args,flush=True)

if __name__=='__main__':
    server=ThreadingHTTPServer(('127.0.0.1',PORT),Handler)
    print('Synthetic manga fixture listening on loopback',PORT,flush=True)
    server.serve_forever()

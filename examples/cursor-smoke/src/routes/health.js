'use strict';

function healthHandler(_req, res) {
  const body = JSON.stringify({ ok: true, service: 'cursor-smoke' });
  res.writeHead(200, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

module.exports = { healthHandler };

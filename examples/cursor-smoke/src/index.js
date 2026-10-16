'use strict';

const http = require('http');
const { healthHandler } = require('./routes/health');

const port = Number(process.env.PORT || 3000);

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return healthHandler(req, res);
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('not found\n');
});

if (require.main === module) {
  server.listen(port, () => {
    process.stdout.write(`listening on ${port}\n`);
  });
}

module.exports = { server };

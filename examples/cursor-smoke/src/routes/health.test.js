'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { healthHandler } = require('./health');

test('healthHandler returns ok JSON', () => {
  const chunks = [];
  const res = {
    writeHead(status, headers) {
      this.status = status;
      this.headers = headers;
    },
    end(chunk) {
      chunks.push(chunk);
    },
  };

  healthHandler({}, res);

  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(chunks.join('')), {
    ok: true,
    service: 'cursor-smoke',
  });
});

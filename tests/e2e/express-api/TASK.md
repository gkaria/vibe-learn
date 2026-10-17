# Task: a two-route Express API

Work in this directory. Follow these steps in order, one at a time. Create and change files with your file tools (Write and Edit), never with shell redirection, `sed`, or heredocs. Run each command on its own, exactly as written: no pipes, no `&&`, no `cd`.

1. Run `npm init -y`, then `npm install express`.
2. Create `app.js` that exports an Express app (do not call `listen`) with two routes:
   - `GET /health` returns status 200 and JSON `{"ok": true}`
   - `GET /users/:id` returns status 200 and JSON `{"id": "<the id>"}`
3. Create `server.js` that starts the app on port 3000. Do not run it.
4. Create `test/app.test.js` with `node:test`, `node:assert`, and the global `fetch`. Start the app on port 0 in a `before` hook and close it in an `after` hook. Test both routes. In the `/health` test, expect status 201: this is wrong on purpose.
5. Set the `test` script in `package.json` to `node --test` and run `npm test`. It fails.
6. Change the wrong expectation to 200 and run `npm test` again. It passes.

# Session Digest — 17 Mar 2026, 14:32–14:50

> **Note:** This is an example of the Phase 3 AI-powered digest. Once vibe-learn Phase 3 is released, this file will be generated automatically at the end of every session and saved to `.vibe-learn/digests/`.

---

## What Was Built

A REST API built with Express and TypeScript, featuring JWT-based user authentication. The API includes user registration, login, and a protected route that requires a valid token to access.

**Files created:** 7
**Files modified:** 2
**Dependencies installed:** express, jsonwebtoken, bcryptjs, dotenv

---

## How It's Structured

```
src/
├── index.ts              — Express app entry point, registers routes
├── middleware/
│   └── auth.ts           — JWT verification middleware (runs before protected routes)
├── routes/
│   ├── auth.ts           — POST /register and POST /login endpoints
│   └── users.ts          — GET /me protected route (requires valid token)
├── db/
│   └── users.ts          — In-memory user store (simulates a database)
└── types/
    └── index.ts          — Shared TypeScript interfaces (User, JwtPayload)
```

---

## Key Decisions

**Why JWT instead of sessions?**
JWT (JSON Web Tokens) are stateless — the server doesn't need to store session data. Each token is self-contained and can be verified without a database lookup. This makes the API easier to scale horizontally.

**Why bcryptjs for password hashing?**
Storing passwords in plain text is a serious security risk. bcrypt applies a one-way hash with a "salt" (random noise) that prevents attackers from using precomputed rainbow tables. Even if your database is leaked, raw passwords are not exposed.

**Why a separate middleware file for auth?**
Claude pulled the JWT verification logic into its own middleware function rather than duplicating it in every route. This means you only need to write `app.use(authMiddleware)` once, and every subsequent route is protected automatically.

**Why .env.example instead of .env?**
The `.env` file contains your JWT secret key — a sensitive credential that should never be committed to git. The `.env.example` file shows collaborators which environment variables are needed without exposing actual values.

---

## Patterns Used

- **Middleware chain:** Express processes requests through a pipeline of functions. Auth middleware runs first, validates the token, then passes control to the route handler.
- **In-memory store:** The `users.ts` file uses a JavaScript array as a stand-in for a real database. Easy to swap out for PostgreSQL or MongoDB later.
- **Separation of concerns:** Routes, middleware, and data access are in separate files — each with a single responsibility.

---

## Things to Study

- [ ] **How JWT works** — Read about the three parts of a token: header, payload, signature. Try decoding one at [jwt.io](https://jwt.io)
- [ ] **Express middleware order** — Understand why `app.use(authMiddleware)` must come *before* the routes it should protect
- [ ] **bcrypt salt rounds** — The `10` in `bcrypt.hash(password, 10)` controls how long hashing takes. Higher = more secure but slower
- [ ] **Token expiry** — The `expiresIn: '24h'` option in `jwt.sign()` means tokens expire after a day. How would you implement refresh tokens?
- [ ] **TypeScript interfaces** — The `User` and `JwtPayload` types in `src/types/index.ts` enforce shape at compile time. Read about why this prevents runtime errors

---

## What to Try Next

1. Replace the in-memory user store with a real database (SQLite is easy to start with)
2. Add input validation (the `zod` library works well with Express)
3. Write a test for the auth middleware using Jest
4. Add rate limiting to the login route to prevent brute-force attacks

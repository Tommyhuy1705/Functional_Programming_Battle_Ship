# Database folder

This folder contains skeletons and helper modules for implementing player login/auth.

Suggested next steps:
- Choose a storage backend: sqlite, PostgreSQL, or file-based JSON for simplicity.
- Add dependencies (e.g., `sqlite-simple` or `persistent-sqlite`) to `package.yaml`.
- Implement user creation, password hashing (use `bcrypt`), and authentication.

Files:
- `Users.hs` — user model and CRUD functions.
- `Auth.hs`  — authentication helpers (verify password, session/token handling).
- `schema.sql` — example SQL schema for users table.

Security notes:
- Store only password hashes (bcrypt/argon2). Never store plain-text passwords.
- Use prepared statements to avoid SQL injection.

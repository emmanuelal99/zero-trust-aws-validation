# Logi-Track (Django app)

The SME logistics-tracking web application under test. Deployed identically to
Environment A and Environment B.

Place the Django project source here. The `compute` Terraform module expects, at minimum:

- A container image (recommended) **or** a source tree that the EC2 `user_data` can run
  with `gunicorn`.
- Environment variables for DB connection:
  - `DJANGO_SECRET_KEY`
  - `DATABASE_URL` (or `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT`)
  - `DJANGO_ALLOWED_HOSTS`

## Deployment contract

| Env A (baseline) | Env B (zero trust) |
|---|---|
| Secrets injected as plaintext env vars in user-data | Secrets pulled from AWS Secrets Manager at boot via instance role |
| Runs on port 8000, exposed via ALB | Same, but ALB is WAF-fronted and app SG only accepts ALB SG |

> TODO: add the Django source, `requirements.txt`, and `Dockerfile`.

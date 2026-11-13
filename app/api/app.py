import os
import uuid

import boto3
import psycopg2
from botocore.config import Config
from flask import Flask, jsonify, request

app = Flask(__name__)

REGION = os.environ.get("AWS_REGION", "ap-south-1")
UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
MAX_UPLOAD_BYTES = 50 * 1024 * 1024  # 50 MB

s3 = boto3.client(
    "s3",
    region_name=REGION,
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)


def get_db_password():
    # the password is never in code or env vars, only the secret's ARN is
    secrets = boto3.client("secretsmanager", region_name=REGION)
    secret = secrets.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    return secret["SecretString"]


DB_PASSWORD = get_db_password()


def run_sql(sql, params=()):
    # open a connection, run one statement, commit, return any rows
    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=DB_PASSWORD,
        connect_timeout=5,
    )
    try:
        with conn, conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall() if cur.description else []
    finally:
        conn.close()


def init_db():
    run_sql("""
        CREATE TABLE IF NOT EXISTS questions (
            id      SERIAL PRIMARY KEY,
            exam_id INT NOT NULL,
            text    TEXT NOT NULL
        )""")
    run_sql("""
        CREATE TABLE IF NOT EXISTS attempts (
            id         SERIAL PRIMARY KEY,
            exam_id    INT NOT NULL,
            started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            answers    TEXT NOT NULL DEFAULT '',
            saved_at   TIMESTAMPTZ
        )""")
    # a few seeded questions for exam 1
    run_sql("""
        INSERT INTO questions (id, exam_id, text) VALUES
            (1, 1, 'What is the difference between a public and a private subnet?'),
            (2, 1, 'Why does RDS Multi-AZ keep a standby in a second AZ?'),
            (3, 1, 'What does an SQS dead letter queue do?')
        ON CONFLICT (id) DO NOTHING""")


init_db()


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.post("/api/exams/<int:exam_id>/start")
def start_exam(exam_id):
    questions = run_sql("SELECT id, text FROM questions WHERE exam_id = %s ORDER BY id", (exam_id,))
    if not questions:
        return jsonify(error="exam not found"), 404
    rows = run_sql("INSERT INTO attempts (exam_id) VALUES (%s) RETURNING id, started_at", (exam_id,))
    attempt_id, started_at = rows[0]
    return jsonify(
        attempt_id=attempt_id,
        started_at=started_at.isoformat(),
        questions=[{"id": q[0], "text": q[1]} for q in questions],
    )


@app.put("/api/attempts/<int:attempt_id>/answers")
def save_answers(attempt_id):
    answers = (request.get_json(silent=True) or {}).get("answers", "")
    rows = run_sql(
        "UPDATE attempts SET answers = %s, saved_at = now() WHERE id = %s RETURNING saved_at",
        (answers, attempt_id),
    )
    if not rows:
        return jsonify(error="attempt not found"), 404
    return jsonify(saved_at=rows[0][0].isoformat())


@app.get("/api/attempts/<int:attempt_id>")
def get_attempt(attempt_id):
    rows = run_sql(
        "SELECT exam_id, started_at, answers, saved_at FROM attempts WHERE id = %s",
        (attempt_id,),
    )
    if not rows:
        return jsonify(error="attempt not found"), 404
    exam_id, started_at, answers, saved_at = rows[0]
    return jsonify(
        attempt_id=attempt_id,
        exam_id=exam_id,
        started_at=started_at.isoformat(),
        answers=answers,
        saved_at=saved_at.isoformat() if saved_at else None,
    )


@app.post("/api/assignments/<int:assignment_id>/upload-url")
def upload_url(assignment_id):
    filename = (request.get_json(silent=True) or {}).get("filename", "file")
    filename = os.path.basename(filename).replace(" ", "_")
    key = f"assignments/{assignment_id}/{uuid.uuid4().hex}-{filename}"
    # the browser uploads straight to S3, S3 rejects anything over 50 MB
    post = s3.generate_presigned_post(
        Bucket=UPLOAD_BUCKET,
        Key=key,
        Conditions=[["content-length-range", 1, MAX_UPLOAD_BYTES]],
        ExpiresIn=300,  # 5 minutes
    )
    return jsonify(url=post["url"], fields=post["fields"], key=key)

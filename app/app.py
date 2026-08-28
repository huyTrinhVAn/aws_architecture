import os

import boto3
import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)

s3 = boto3.client("s3")
RECEIPTS_BUCKET = os.environ.get("RECEIPTS_BUCKET", "")


def get_db_connection():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", 3306)),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        cursorclass=pymysql.cursors.DictCursor,
    )


@app.route("/health")
def health():
    return "ok", 200


@app.route("/expenses", methods=["POST"])
def create_expense():
    data = request.get_json(silent=True) or {}
    amount = data.get("amount")
    category_id = data.get("category_id")
    note = data.get("note")

    if amount is None or category_id is None:
        return jsonify({"error": "amount and category_id are required"}), 400

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO expenses (category_id, amount, note) VALUES (%s, %s, %s)",
                (category_id, amount, note),
            )
            conn.commit()
            expense_id = cursor.lastrowid

            cursor.execute("SELECT * FROM expenses WHERE id = %s", (expense_id,))
            expense = cursor.fetchone()
    finally:
        conn.close()

    expense["amount"] = float(expense["amount"])
    return jsonify(expense), 201


@app.route("/expenses", methods=["GET"])
def list_expenses():
    category_id = request.args.get("category_id")
    date_from = request.args.get("from")
    date_to = request.args.get("to")

    query = "SELECT * FROM expenses WHERE 1=1"
    params = []

    if category_id is not None:
        query += " AND category_id = %s"
        params.append(category_id)
    if date_from is not None:
        query += " AND created_at >= %s"
        params.append(date_from)
    if date_to is not None:
        query += " AND created_at <= %s"
        params.append(date_to)

    query += " ORDER BY created_at DESC"

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(query, params)
            expenses = cursor.fetchall()
    finally:
        conn.close()

    for expense in expenses:
        expense["amount"] = float(expense["amount"])

    return jsonify(expenses)


@app.route("/expenses/summary", methods=["GET"])
def expenses_summary():
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT c.name AS category, SUM(e.amount) AS total
                FROM expenses e
                JOIN categories c ON c.id = e.category_id
                GROUP BY c.name
                ORDER BY total DESC
                """
            )
            by_category = cursor.fetchall()

            cursor.execute(
                """
                SELECT DATE_FORMAT(created_at, '%Y-%m') AS month, SUM(amount) AS total
                FROM expenses
                GROUP BY month
                ORDER BY month DESC
                """
            )
            by_month = cursor.fetchall()
    finally:
        conn.close()

    for row in by_category:
        row["total"] = float(row["total"])
    for row in by_month:
        row["total"] = float(row["total"])

    return jsonify({"by_category": by_category, "by_month": by_month})


@app.route("/expenses/<int:expense_id>/receipt", methods=["POST"])
def upload_receipt(expense_id):
    if "file" not in request.files:
        return jsonify({"error": "no file provided (expected form field 'file')"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "empty filename"}), 400

    if not RECEIPTS_BUCKET:
        return jsonify({"error": "RECEIPTS_BUCKET is not configured"}), 500

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id FROM expenses WHERE id = %s", (expense_id,))
            if cursor.fetchone() is None:
                return jsonify({"error": "expense not found"}), 404

            s3_key = f"receipts/{expense_id}/{file.filename}"
            s3.upload_fileobj(file, RECEIPTS_BUCKET, s3_key)

            cursor.execute(
                "UPDATE expenses SET receipt_s3_key = %s WHERE id = %s",
                (s3_key, expense_id),
            )
            conn.commit()
    finally:
        conn.close()

    return jsonify({"expense_id": expense_id, "receipt_s3_key": s3_key}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("APP_PORT", 8080)))

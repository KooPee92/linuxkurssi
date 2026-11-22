from flask import Flask, render_template
from dotenv import load_dotenv
from pathlib import Path
import pymysql
import os

load_dotenv(Path(__file__).with_name(".env"))

app = Flask(__name__)


@app.route("/")
def home():
    # Connect to the local MariaDB replica
    try:
        connection = pymysql.connect(
            host="127.0.0.1",
            user="week4_reader",
            password=os.environ["WEEK4_DB_PASSWORD"],
            database="viikko2"
        )

        try:
            with connection.cursor() as cursor:
                # Read-only query: do not increase the counter
                cursor.execute(
                    "SELECT visits FROM visitor_counter WHERE id = 1"
                )
                result = cursor.fetchone()
        finally:
            connection.close()

    except pymysql.MySQLError:
        app.logger.exception("Database connection failed")
        return "Database temporarily unavailable", 503

    if result is None:
        return "Visitor counter not found", 503

    return render_template("index.html", visits=result[0])

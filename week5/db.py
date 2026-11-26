import os
from pathlib import Path

import pymysql
from dotenv import load_dotenv

# Load database settings from .env
load_dotenv(Path(__file__).with_name(".env"))


def get_connection():
    # Create a connection to the local MariaDB database
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        charset="utf8mb4",
        connect_timeout=5
    )


def get_messages(session_id, limit=10):
    # Read the latest messages from the database
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT role, content
                FROM messages
                WHERE session_id = %s
                ORDER BY id DESC
                LIMIT %s
                """,
                (session_id, limit)
            )

            rows = cursor.fetchall()

        # Return messages in chronological order
        return [
            {"role": role, "content": content}
            for role, content in reversed(rows)
        ]

    finally:
        connection.close()


def save_exchange(session_id, user_message, ai_response):
    # Save both messages in one transaction
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO messages (session_id, role, content)
                VALUES (%s, %s, %s)
                """,
                (session_id, "user", user_message)
            )

            cursor.execute(
                """
                INSERT INTO messages (session_id, role, content)
                VALUES (%s, %s, %s)
                """,
                (session_id, "assistant", ai_response)
            )

        connection.commit()

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()

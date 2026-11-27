import os
from pathlib import Path
from uuid import uuid4

import pymysql
import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request, session

from db import get_messages, save_exchange

# Load environment variables
load_dotenv(Path(__file__).with_name(".env"))

app = Flask(__name__)

# Secret key for signed session cookies
app.secret_key = os.getenv("FLASK_SECRET_KEY")
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:3b")


@app.route("/")
def home():
    return render_template("index.html")


@app.route("/api/history", methods=["GET"])
def history():
    # Get the current conversation ID
    session_id = session.get("chat_id")

    if not session_id:
        return jsonify({"messages": []})

    try:
        messages = get_messages(session_id, limit=50)
        return jsonify({"messages": messages})

    except pymysql.MySQLError:
        app.logger.exception("History loading failed")
        return jsonify({"error": "Database unavailable"}), 503


@app.route("/api/chat", methods=["POST"])
def chat():
    # Read and validate the user's message
    data = request.get_json(silent=True) or {}
    message = data.get("message", "")

    if not isinstance(message, str):
        return jsonify({"error": "Invalid message"}), 400

    message = message.strip()

    if not message or len(message) > 1000:
        return jsonify({
            "error": "Message must contain 1-1000 characters"
        }), 400

    # Reuse the existing conversation or create a new one
    session_id = session.get("chat_id") or str(uuid4())

    try:
        # Load previous messages from MariaDB
        previous_messages = get_messages(session_id, limit=10)

    except pymysql.MySQLError:
        app.logger.exception("History loading failed")
        return jsonify({"error": "Database unavailable"}), 503

    # Include conversation history in the Ollama request
    messages = [
        {
            "role": "system",
            "content": "You are a helpful AI assistant."
        }
    ]

    messages.extend(previous_messages)

    messages.append({
        "role": "user",
        "content": message
    })

    try:
        # Ask the local AI model
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": MODEL,
                "messages": messages,
                "stream": False,
                "options": {
                    "num_predict": 200
                }
            },
            timeout=180
        )

        response.raise_for_status()

        answer = response.json()["message"]["content"]

    except (requests.RequestException, KeyError, ValueError, TypeError):
        app.logger.exception("Ollama request failed")
        return jsonify({"error": "AI model unavailable"}), 503

    try:
        # Save the question and answer to MariaDB
        save_exchange(session_id, message, answer)

    except pymysql.MySQLError:
        app.logger.exception("Message saving failed")
        return jsonify({"error": "Database unavailable"}), 503

    # Remember the conversation in the browser session
    session["chat_id"] = session_id

    return jsonify({"reply": answer})


@app.get("/health")
def health():
    # Commit SHA is provided by the deployment pipeline
    commit_sha = os.getenv("DEPLOY_SHA", "not-deployed")

    return jsonify({
        "status": "ok",
        "commit": commit_sha
    })

-- Week 5 - AI Chat Database Schema

CREATE DATABASE IF NOT EXISTS week5_chat
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE week5_chat;

-- Store conversations from different browser sessions
CREATE TABLE IF NOT EXISTS messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    session_id CHAR(36) NOT NULL,
    role ENUM('user', 'assistant') NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX (session_id, id)
);

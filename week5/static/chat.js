// Week 5 - AI Chat

const chatMessages = document.getElementById("chat-messages");
const chatForm = document.getElementById("chat-form");
const messageInput = document.getElementById("message");
const sendButton = document.getElementById("send-button");
const statusText = document.getElementById("status");


// Add a message to the conversation window
function addMessage(role, content) {
    const messageDiv = document.createElement("div");

    messageDiv.className = "message " + role;

    const heading = document.createElement("strong");
    heading.textContent = role === "user" ? "You" : "AI Assistant";

    const text = document.createElement("span");
    text.textContent = content;

    messageDiv.appendChild(heading);
    messageDiv.appendChild(text);

    chatMessages.appendChild(messageDiv);

    // Scroll to the newest message
    chatMessages.scrollTop = chatMessages.scrollHeight;
}


// Load previous messages from MariaDB through Flask
async function loadHistory() {
    statusText.textContent = "Loading conversation history...";

    try {
        const response = await fetch("api/history");

        if (!response.ok) {
            throw new Error("Could not load conversation history");
        }

        const data = await response.json();

        chatMessages.replaceChildren();

        for (const message of data.messages) {
            addMessage(message.role, message.content);
        }

        statusText.textContent = "";

    } catch (error) {
        statusText.textContent = error.message;
    }
}


// Send a message to the AI
chatForm.addEventListener("submit", async function(event) {
    event.preventDefault();

    const message = messageInput.value.trim();

    if (!message) {
        return;
    }

    sendButton.disabled = true;
    messageInput.disabled = true;

    addMessage("user", message);

    messageInput.value = "";
    statusText.textContent = "AI is thinking...";

    try {
        const response = await fetch("api/chat", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                message: message
            })
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || "Something went wrong");
        }

        addMessage("assistant", data.reply);

        statusText.textContent = "";

    } catch (error) {
        statusText.textContent = "Error: " + error.message;

    } finally {
        sendButton.disabled = false;
        messageInput.disabled = false;
        messageInput.focus();
    }
});


// Load conversation history when the page opens
loadHistory();

import asyncio
import websockets
import json
import time
import logging
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
HARDCODED_TOKEN = "secure_chat_token_9999"

# Rate limiting for connections only
connection_attempts = defaultdict(lambda: {'count': 0, 'reset_time': time.time() + 60})
MAX_CONNECTIONS_PER_MINUTE = 10
MAX_TOTAL_CLIENTS = 100  # Maximum total concurrent clients
MAX_MESSAGE_RATE = 60  # Maximum messages per minute per client

clients = {}  # Maps user IDs to WebSocket connections
client_message_rates = defaultdict(lambda: {'count': 0, 'reset_time': time.time() + 60})

def is_valid_token(token):
    """Validate authentication token"""
    try:
        return token == HARDCODED_TOKEN
    except Exception:
        return False

def check_connection_rate_limit(client_ip):
    """Check if client IP is within connection rate limits"""
    try:
        current_time = time.time()
        client_limit = connection_attempts[client_ip]
        
        if current_time > client_limit['reset_time']:
            # Reset the rate limit window
            client_limit['count'] = 0
            client_limit['reset_time'] = current_time + 60
        
        if client_limit['count'] >= MAX_CONNECTIONS_PER_MINUTE:
            return False
        
        client_limit['count'] += 1
        return True
    except Exception as e:
        logger.error(f"Error in connection rate limit check: {e}")
        return True  # Allow connection on error to avoid blocking legitimate users

def check_message_rate_limit(client_id):
    """Check if client is within message rate limits"""
    try:
        current_time = time.time()
        client_limit = client_message_rates[client_id]
        
        if current_time > client_limit['reset_time']:
            client_limit['count'] = 0
            client_limit['reset_time'] = current_time + 60
        
        if client_limit['count'] >= MAX_MESSAGE_RATE:
            return False
        
        client_limit['count'] += 1
        return True
    except Exception as e:
        logger.error(f"Error in message rate limit check: {e}")
        return True

def sanitize_input(text):
    """Basic input sanitization"""
    try:
        if not isinstance(text, str):
            return ""
        # Remove any null bytes and limit length
        return text.replace('\x00', '').strip()[:1000]
    except Exception:
        return ""

async def send_error(websocket, error_msg):
    """Send error message to client"""
    try:
        await asyncio.wait_for(
            websocket.send(json.dumps({
                "type": "error",
                "message": error_msg
            })),
            timeout=5.0
        )
    except Exception as e:
        logger.debug(f"Failed to send error message: {e}")

async def authenticate_client(websocket, client_ip):
    """Handle client authentication and return client_id if successful"""
    try:
        # Check total client limit
        if len(clients) >= MAX_TOTAL_CLIENTS:
            await send_error(websocket, "Server at capacity. Please try again later.")
            return None
        
        # Check connection rate limit first
        if not check_connection_rate_limit(client_ip):
            await send_error(websocket, "Too many connection attempts. Please wait.")
            return None
        
        # Wait for authentication message with timeout
        auth_message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
        
        # Limit auth message size
        if len(auth_message) > 1000:
            await send_error(websocket, "Authentication message too large")
            return None
            
        auth_data = json.loads(auth_message)
        
        token = auth_data.get('token')
        client_id = sanitize_input(auth_data.get('client_id', ''))
        
        # Validate authentication data
        if not token or not client_id:
            await send_error(websocket, "Invalid authentication format. Expected: {\"token\": \"your_token\", \"client_id\": \"your_id\"}")
            return None
            
        if not is_valid_token(token):
            await send_error(websocket, "Invalid authentication token")
            return None
            
        if len(client_id) < 3 or len(client_id) > 50:
            await send_error(websocket, "Client ID must be between 3-50 characters")
            return None
            
        if client_id in clients:
            await send_error(websocket, "Client ID already in use")
            return None
        
        return client_id
        
    except asyncio.TimeoutError:
        await send_error(websocket, "Authentication timeout")
        return None
    except json.JSONDecodeError:
        await send_error(websocket, "Invalid JSON format for authentication")
        return None
    except Exception as e:
        logger.debug(f"Authentication error: {e}")
        await send_error(websocket, "Authentication error")
        return None

async def process_message(websocket, client_id, message):
    """Process a single message from a client"""
    try:
        # Check message rate limit
        if not check_message_rate_limit(client_id):
            await send_error(websocket, "Message rate limit exceeded. Please slow down.")
            return
        
        # Limit message size
        if len(message) > 2000:
            await send_error(websocket, "Message too large")
            return
            
        message = sanitize_input(message)
        if not message:
            return
            
        logger.info(f"Received from {client_id}: {message[:100]}...")  # Truncate log message
        
        # Parse message format: target_id::message
        if "::" not in message:
            await send_error(websocket, "Invalid format. Use: target_id::your_message")
            return
        
        parts = message.split("::", 1)
        if len(parts) != 2:
            await send_error(websocket, "Invalid message format")
            return
            
        target_id, real_msg = parts
        target_id = sanitize_input(target_id)
        real_msg = sanitize_input(real_msg)
        
        if not target_id or not real_msg:
            await send_error(websocket, "Target ID and message cannot be empty")
            return
        
        # Send message to target
        target_ws = clients.get(target_id)
        if target_ws:
            try:
                await asyncio.wait_for(
                    target_ws.send(json.dumps({
                        "type": "message",
                        "from": client_id,
                        "message": real_msg,
                        "timestamp": int(time.time())
                    })),
                    timeout=5.0
                )
                
                # Send delivery confirmation
                await asyncio.wait_for(
                    websocket.send(json.dumps({
                        "type": "delivered",
                        "to": target_id,
                        "message": "Message delivered successfully"
                    })),
                    timeout=5.0
                )
            except asyncio.TimeoutError:
                await send_error(websocket, "Message delivery timeout")
            except Exception as e:
                logger.error(f"Error delivering message: {e}")
                await send_error(websocket, "Message delivery failed")
        else:
            await send_error(websocket, f"Target '{target_id}' is not connected")
            
    except Exception as e:
        logger.error(f"Error processing message from {client_id}: {e}")
        await send_error(websocket, "Error processing message")

async def handler(websocket):
    """Main WebSocket connection handler"""
    client_id = None
    client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
    
    try:
        logger.info(f"New connection attempt from {client_ip}")
        
        # Authenticate the client
        client_id = await authenticate_client(websocket, client_ip)
        if not client_id:
            logger.warning(f"Authentication failed for {client_ip}")
            return  # Authentication failed
        
        # Store client connection
        clients[client_id] = websocket
        logger.info(f"{client_id} connected from {client_ip}")
        
        # Send connection confirmation
        try:
            await asyncio.wait_for(
                websocket.send(json.dumps({
                    "type": "connected",
                    "message": f"Successfully connected as {client_id}",
                    "active_clients": len(clients)
                })),
                timeout=5.0
            )
        except asyncio.TimeoutError:
            logger.warning(f"Timeout sending connection confirmation to {client_id}")

        # Handle incoming messages with protection
        try:
            async for message in websocket:
                await process_message(websocket, client_id, message)
        except websockets.exceptions.ConnectionClosed:
            pass  # Normal disconnection
        except Exception as e:
            logger.error(f"Error in message loop for {client_id}: {e}")

    except websockets.exceptions.ConnectionClosedError:
        if client_id:
            logger.info(f"{client_id} disconnected (connection closed)")
        else:
            logger.debug(f"Connection from {client_ip} closed during handshake")
    except websockets.exceptions.ConnectionClosedOK:
        if client_id:
            logger.info(f"{client_id} disconnected (connection closed OK)")
        else:
            logger.debug(f"Connection from {client_ip} closed OK during handshake")
    except EOFError:
        # This is common for health checks or incomplete connections
        logger.debug(f"EOF error from {client_ip} - likely a health check or incomplete connection")
    except Exception as e:
        if client_id:
            logger.error(f"Unexpected error for {client_id}: {e}")
        else:
            logger.debug(f"Handshake error from {client_ip}: {e}")
    finally:
        # Clean up client connection - always ensure cleanup happens
        try:
            if client_id and client_id in clients:
                clients.pop(client_id, None)
                logger.info(f"Cleaned up connection for {client_id}")
        except Exception as e:
            logger.error(f"Error during cleanup for {client_id}: {e}")

async def main():
    logger.info("Starting secure WebSocket server at ws://0.0.0.0:8765")
    logger.info(f"Authentication token: {HARDCODED_TOKEN}")
    logger.info(f"Connection rate limit: {MAX_CONNECTIONS_PER_MINUTE} connections per minute per IP")
    logger.info(f"Maximum concurrent clients: {MAX_TOTAL_CLIENTS}")
    logger.info(f"Message rate limit: {MAX_MESSAGE_RATE} messages per minute per client")
    
    try:
        # Create WebSocket server with proper error handling
        async with websockets.serve(
            handler, 
            "0.0.0.0", 
            8765,
            # Add connection timeout and other settings
            close_timeout=10,
            max_size=2**20,  # 1MB max message size
            max_queue=32,    # Max queued messages
            compression=None,  # Disable compression for better performance
            ping_interval=20,  # Send ping every 20 seconds
            ping_timeout=10    # Wait 10 seconds for pong
        ):
            logger.info("WebSocket server started successfully")
            await asyncio.Future()  # run forever
    except Exception as e:
        logger.error(f"Server error: {e}")
        # Don't let the server crash, just log and continue

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server shutdown requested")
    except Exception as e:
        logger.error(f"Server startup failed: {e}")
        # Exit gracefully instead of crashing
        exit(1)


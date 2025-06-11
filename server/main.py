import asyncio
import websockets
import json
import time
from collections import defaultdict

# Configuration
HARDCODED_TOKEN = "secure_chat_token_9999"

# Rate limiting for connections only
connection_attempts = defaultdict(lambda: {'count': 0, 'reset_time': time.time() + 60})
MAX_CONNECTIONS_PER_MINUTE = 10

clients = {}  # Maps user IDs to WebSocket connections

def is_valid_token(token):
    """Validate authentication token"""
    return token == HARDCODED_TOKEN

def check_connection_rate_limit(client_ip):
    """Check if client IP is within connection rate limits"""
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

def sanitize_input(text):
    """Basic input sanitization"""
    if not isinstance(text, str):
        return ""
    # Remove any null bytes and limit length
    return text.replace('\x00', '').strip()[:1000]

async def send_error(websocket, error_msg):
    """Send error message to client"""
    try:
        await websocket.send(json.dumps({
            "type": "error",
            "message": error_msg
        }))
    except:
        pass

async def authenticate_client(websocket, client_ip):
    """Handle client authentication and return client_id if successful"""
    try:
        # Check connection rate limit first
        if not check_connection_rate_limit(client_ip):
            await send_error(websocket, "Too many connection attempts. Please wait.")
            return None
        
        # Wait for authentication message
        auth_message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
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
        await send_error(websocket, "Authentication error")
        return None

async def process_message(websocket, client_id, message):
    """Process a single message from a client"""
    try:
        message = sanitize_input(message)
        if not message:
            return
            
        print(f"Received from {client_id}: {message}")
        
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
            await target_ws.send(json.dumps({
                "type": "message",
                "from": client_id,
                "message": real_msg,
                "timestamp": int(time.time())
            }))
            
            # Send delivery confirmation
            await websocket.send(json.dumps({
                "type": "delivered",
                "to": target_id,
                "message": "Message delivered successfully"
            }))
        else:
            await send_error(websocket, f"Target '{target_id}' is not connected")
            
    except Exception as e:
        print(f"Error processing message from {client_id}: {e}")
        await send_error(websocket, "Error processing message")

async def handler(websocket, path):
    """Main WebSocket connection handler"""
    client_id = None
    client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
    
    try:
        # Authenticate the client
        client_id = await authenticate_client(websocket, client_ip)
        if not client_id:
            return  # Authentication failed
        
        # Store client connection
        clients[client_id] = websocket
        print(f"{client_id} connected from {client_ip} at {time.ctime()}")
        
        # Send connection confirmation
        await websocket.send(json.dumps({
            "type": "connected",
            "message": f"Successfully connected as {client_id}",
            "active_clients": len(clients)
        }))

        # Handle incoming messages
        async for message in websocket:
            await process_message(websocket, client_id, message)

    except websockets.exceptions.ConnectionClosed:
        if client_id:
            print(f"{client_id} disconnected at {time.ctime()}")
    except Exception as e:
        print(f"Connection error for {client_id if client_id else 'unknown'}: {e}")
    finally:
        # Clean up client connection
        if client_id and client_id in clients:
            clients.pop(client_id, None)
            print(f"Cleaned up connection for {client_id}")

async def main():
    print("Starting secure WebSocket server at ws://0.0.0.0:8765")
    print(f"Authentication token: {HARDCODED_TOKEN}")
    print(f"Connection rate limit: {MAX_CONNECTIONS_PER_MINUTE} connections per minute per IP")
    
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())


import asyncio
import websockets

clients = {}  # Maps user IDs to WebSocket connections

async def handler(websocket, path):
    try:
        # First message is the client ID
        client_id = await websocket.recv()
        clients[client_id] = websocket
        print(f"{client_id} connected.")

        async for message in websocket:
            print(f"Received from {client_id}: {message}")
            # Expecting messages in format: target_id::message
            if "::" in message:
                target_id, real_msg = message.split("::", 1)
                target_ws = clients.get(target_id)
                if target_ws:
                    await target_ws.send(f"{client_id} says: {real_msg}")
                else:
                    await websocket.send("Target not connected.")
            else:
                await websocket.send("Invalid format. Use target_id::message")

    except websockets.exceptions.ConnectionClosed:
        print(f"{client_id} disconnected.")
    finally:
        clients.pop(client_id, None)

async def main():
    print("Starting WebSocket server at ws://0.0.0.0:8765")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())


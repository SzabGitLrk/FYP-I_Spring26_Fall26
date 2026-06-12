import socket

# This matches the channel the robot is listening to
UDP_IP = "127.0.0.1" 
UDP_PORT = 5052

print("🤖 Python-to-Unity Bridge Online!")
print("Type a word and press Enter (Type 'quit' to exit)")

# Create the invisible network cable
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

while True:
    word = input("You: ").lower().strip()
    
    if word == 'quit':
        break
    
    # Shout the word over the network!
    sock.sendto(word.encode(), (UDP_IP, UDP_PORT))
    print(f"Sent command: {word}")
import socket
import time
import re

# Network Setup
UDP_IP = "127.0.0.1"
UDP_PORT = 5052
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# The ASL "Stop Words" (Words we delete because they don't exist in ASL)
stop_words = [ "an", "the", "is", "am", "are", "to", "be"]

# Our current Dictionary (The animations Unity actually knows)
# We map variations of words to the exact trigger name in Unity
word_map = {
    "drink": "drink",
    "drinking": "drink",
    "yes": "yes",
    "yeah": "yes",
    "please": "please",
    "plz": "please",
    "bbq": "bbq",
    "b": "b",  # <-- ADD THIS LINE
    "c": "c",
    "a": "a",
    "d": "d",
    "e": "e",
    "f": "f",
    "g": "g",
    "h": "h",
    "i": "i",
    "j": "j",
    "k": "k",
    "l": "l",
    "m": "m",
    "n": "n",
    "o": "o",
    "p": "p",
    "q": "q",
    "r": "r",
    "s": "s",
    "t": "t",
    "u": "u",
    "v": "v",
    "w": "w",
    "x": "x",
    "y": "y",
    "z": "z"
}

def translate_to_asl(english_sentence):
    # 1. Make everything lowercase and remove punctuation
    clean_text = re.sub(r'[^\w\s]', '', english_sentence.lower())
    words = clean_text.split()
    
    # 2. Remove English stop words
    asl_words = [word for word in words if word not in stop_words]
    
    # 3. Map to our known dictionary triggers OR fingerspell
    animation_queue = []
    
    for word in asl_words:
        # If we know the whole word (e.g., "drink"), add it to the queue
        if word in word_map:
            animation_queue.append(word_map[word])
        
        # If we DON'T know the word, we Fingerspell it!
        else:
            print(f"⚠️ Word '{word}' not in dictionary. Switching to fingerspelling...")
            # Break the word into letters
            for letter in word:
                # Add a special command for letters (e.g., "letter_s", "letter_o")
                animation_queue.append(f"letter_{letter}")
                
    return animation_queue

print("🤖 Text-to-Sign NLP Pipeline Online!")
print("Type a sentence (e.g., 'Yes I want to drink'). Type 'quit' to exit.")

while True:
    user_input = input("\nEnter English text: ")
    
    if user_input.lower() == 'quit':
        break
        
    # Translate the sentence into an array of ASL commands
    command_queue = translate_to_asl(user_input)
    
    print(f"🧠 Translated ASL Sequence: {command_queue}")
    
    # Send the commands to Unity one by one
    for command in command_queue:
        print(f"📡 Sending command: {command}")
        sock.sendto(command.encode(), (UDP_IP, UDP_PORT))
        
        # We MUST pause so Unity has time to play the animation before the next one starts!
        # Adjust this sleep time based on how long your animations take (e.g., 2.5 seconds)
        time.sleep(2.5) 

print("Pipeline shut down safely.")


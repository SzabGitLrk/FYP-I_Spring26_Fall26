import importlib.util
packages = ['customtkinter','langchain','chromadb','sentence_transformers','unstructured','sounddevice','soundfile','ollama','pytest','docx','pptx','requests']
print({p: importlib.util.find_spec(p) is not None for p in packages})

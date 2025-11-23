from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    hostname = os.uname().nodename
    return f"Hello, Kubernetes World! From Pod: {hostname}\n"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
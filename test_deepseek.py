from openai import OpenAI
from dotenv import load_dotenv
import os
import sys

# Load environment variables from .env
load_dotenv()

# Get API key from environment
api_key = os.getenv('DEEPSEEK_API_KEY')
if not api_key:
    print("Error: DEEPSEEK_API_KEY not found in .env file")
    sys.exit(1)

client = OpenAI(api_key=api_key, base_url="https://api.deepseek.com")

def process_stream_response(response):
    reasoning_content = ""
    content = ""
    for chunk in response:
        if chunk.choices[0].delta.reasoning_content:
            reasoning_content += chunk.choices[0].delta.reasoning_content
        elif chunk.choices[0].delta.content:
            content += chunk.choices[0].delta.content
    return reasoning_content, content

def main():
    # Round 1
    messages = [{"role": "user", "content": "9.11 and 9.8, which is greater?"}]
    response = client.chat.completions.create(
        model="deepseek-reasoner",
        messages=messages,
        stream=True
    )

    reasoning_content, content = process_stream_response(response)
    print("\nRound 1:")
    if reasoning_content:
        print(f"Reasoning: {reasoning_content}")
    print(f"Answer: {content}\n")

    # Round 2
    messages.append({"role": "assistant", "content": content})
    messages.append({'role': 'user', 'content': "How many Rs are there in the word 'strawberry'?"})
    response = client.chat.completions.create(
        model="deepseek-reasoner",
        messages=messages,
        stream=True
    )

    reasoning_content, content = process_stream_response(response)
    print("Round 2:")
    if reasoning_content:
        print(f"Reasoning: {reasoning_content}")
    print(f"Answer: {content}")

if __name__ == "__main__":
    main()
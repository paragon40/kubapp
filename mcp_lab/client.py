import asyncio
import json
import sys

import httpx

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "qwen2.5:3b"


async def ask_ollama(messages, tools=None):
    payload = {
        "model": MODEL,
        "messages": messages,
        "stream": False,
    }

    if tools:
        payload["tools"] = tools

    async with httpx.AsyncClient() as client:
        response = await client.post(
            OLLAMA_URL,
            json=payload,
            timeout=120.0,
        )
        response.raise_for_status()
        return response.json()


async def main():
    server_params = StdioServerParameters(
        command=sys.executable,
        args=["server.py"],
    )

    async with stdio_client(server_params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:

            await session.initialize()

            mcp_tools = await session.list_tools()

            print("MCP tools:")
            for tool in mcp_tools.tools:
                print(f"  - {tool.name}")

            # Convert MCP tools into Ollama tool definitions.
            ollama_tools = []

            for tool in mcp_tools.tools:
                ollama_tools.append(
                    {
                        "type": "function",
                        "function": {
                            "name": tool.name,
                            "description": tool.description or "",
                            "parameters": tool.input_schema,
                        },
                    }
                )

            messages = [
                {
                    "role": "system",
                    "content": (
                        "You are a local systems assistant. "
                        "You have access to tools through MCP. "
                        "Use the available tools when they provide "
                        "information you cannot reliably know yourself."
                    ),
                },
                {
                    "role": "user",
                    "content": "What machine am I running on?",
                },
            ]

            print("\nAsking Qwen...\n")

            response = await ask_ollama(
                messages,
                ollama_tools,
            )

            assistant_message = response["message"]

            print("Qwen response:")
            print(json.dumps(assistant_message, indent=2))

            # Check whether Qwen requested a tool.
            tool_calls = assistant_message.get("tool_calls", [])

            if not tool_calls:
                print("\nQwen did not request a tool.")
                print(assistant_message.get("content", ""))
                return

            messages.append(assistant_message)

            # Execute each requested MCP tool.
            for call in tool_calls:
                function = call["function"]
                name = function["name"]
                arguments = function.get("arguments", {})

                print(f"\nQwen requested MCP tool: {name}")
                print(f"Arguments: {arguments}")

                result = await session.call_tool(
                    name,
                    arguments,
                )

                tool_text = "\n".join(
                    item.text
                    for item in result.content
                    if hasattr(item, "text")
                )

                print("\nMCP returned:")
                print(tool_text)

                messages.append(
                    {
                        "role": "tool",
                        "content": tool_text,
                    }
                )

            final_response = await ask_ollama(messages)

            print("\nFinal Qwen answer:")
            print(final_response["message"]["content"])


if __name__ == "__main__":
    asyncio.run(main())

import asyncio
import os
import platform

from mcp.server.mcpserver import MCPServer


server = MCPServer(
    name="local-system-server",
    version="0.1.0",
)


@server.tool(
    name="get_system_info",
    description="Return basic information about the local machine.",
)
async def get_system_info() -> str:
    return (
        f"Hostname: {platform.node()}\n"
        f"OS: {platform.system()} {platform.release()}\n"
        f"Architecture: {platform.machine()}\n"
        f"CPU cores: {os.cpu_count()}\n"
    )


async def main():
    await server.run_stdio_async()


if __name__ == "__main__":
    asyncio.run(main())

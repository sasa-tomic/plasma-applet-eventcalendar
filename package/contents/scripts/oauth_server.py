#!/usr/bin/env python3
"""
OAuth Loopback Server for Google Calendar Authentication
Replaces the deprecated OOB (out-of-band) flow with a local HTTP server.
"""

import sys
import json
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import time


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    """HTTP request handler for OAuth callback."""

    auth_code = None
    error = None

    def do_GET(self):
        """Handle GET request from OAuth redirect."""
        parsed_path = urlparse(self.path)
        query_params = parse_qs(parsed_path.query)

        if "code" in query_params:
            # Success - capture the authorization code
            OAuthCallbackHandler.auth_code = query_params["code"][0]
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            success_page = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Authentication Successful</title>
                <style>
                    body {
                        font-family: Arial, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background-color: #f5f5f5;
                    }
                    .container {
                        text-align: center;
                        padding: 40px;
                        background: white;
                        border-radius: 8px;
                        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    }
                    h1 { color: #4285f4; }
                    p { color: #5f6368; }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>✅ Authentication Successful</h1>
                    <p>You have successfully authorized KDE Event Calendar.</p>
                    <p>You can close this window and return to the settings.</p>
                </div>
            </body>
            </html>
            """
            self.wfile.write(success_page.encode())

        elif "error" in query_params:
            # Error - capture the error message
            OAuthCallbackHandler.error = query_params["error"][0]
            error_description = query_params.get(
                "error_description", ["Unknown error"]
            )[0]

            self.send_response(400)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            error_page = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Authentication Failed</title>
                <style>
                    body {{
                        font-family: Arial, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background-color: #f5f5f5;
                    }}
                    .container {{
                        text-align: center;
                        padding: 40px;
                        background: white;
                        border-radius: 8px;
                        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    }}
                    h1 {{ color: #d93025; }}
                    p {{ color: #5f6368; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>? Authentication Failed</h1>
                    <p>Error: {error_description}</p>
                    <p>You can close this window and try again.</p>
                </div>
            </body>
            </html>
            """
            self.wfile.write(error_page.encode())
        else:
            # Unknown request
            self.send_response(400)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Invalid OAuth callback")

    def log_message(self, format, *args):
        """Suppress default HTTP server logs."""
        pass


def find_free_port():
    """Find an available port on localhost."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]


def start_oauth_server(timeout=180):
    """
    Start HTTP server and wait for OAuth callback.

    Args:
        timeout: Maximum time to wait for callback (seconds)

    Returns:
        dict with 'port', 'code' (if successful), 'error' (if failed)
    """
    port = find_free_port()
    server = HTTPServer(("127.0.0.1", port), OAuthCallbackHandler)

    # Output port immediately so QML can construct the redirect URL
    result = {"port": port}
    print(json.dumps(result), flush=True)

    # Run server in a thread with timeout
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    # Wait for callback or timeout
    start_time = time.time()
    while time.time() - start_time < timeout:
        if OAuthCallbackHandler.auth_code:
            server.shutdown()
            return {
                "port": port,
                "code": OAuthCallbackHandler.auth_code,
                "success": True,
            }
        elif OAuthCallbackHandler.error:
            server.shutdown()
            return {"port": port, "error": OAuthCallbackHandler.error, "success": False}
        time.sleep(0.1)

    # Timeout
    server.shutdown()
    return {"port": port, "error": "timeout", "success": False}


def main():
    """Main entry point."""
    try:
        result = start_oauth_server()
        print(json.dumps(result))
        sys.stdout.flush()
        sys.exit(0 if result.get("success") else 1)
    except Exception as e:
        error_result = {
            "error": "server_error",
            "error_description": str(e),
            "success": False,
        }
        print(json.dumps(error_result))
        sys.stdout.flush()
        sys.exit(1)


if __name__ == "__main__":
    main()

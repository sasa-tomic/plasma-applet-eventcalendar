#!/usr/bin/python3
"""
Fetch plasmashell logs for debugging the Event Calendar applet.

This script automatically detects the best log source:
1. journalctl (systemd-based: Arch, Fedora, newer Ubuntu/Kubuntu)
2. ~/.xsession-errors (older Ubuntu/Kubuntu, some other distros)

Usage:
    python3 fetchlogs.py [options]

Options:
    --filter TEXT       Filter logs containing TEXT (default: 'eventcalendar')
    --lines N           Maximum number of lines to return (default: 500)
    --since TIME        Show logs since TIME (e.g., '1 hour ago', '2024-01-01')
    --no-filter         Show all plasmashell logs without filtering
    --command CMD       Custom command to fetch logs (overrides auto-detection)
"""

import argparse
import subprocess
import sys
import shutil
import os


def detect_log_source():
    """
    Automatically detect the best log source for the current system.
    Returns a tuple of (command_list, source_description).
    """
    sources_tried = []
    
    # Try 1: journalctl (systemd-based systems)
    if shutil.which('journalctl'):
        # Check if journalctl actually has plasmashell logs
        try:
            result = subprocess.run(
                ['journalctl', '-b0', '_COMM=plasmashell', '--no-pager', '-n', '1'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                return (
                    ['journalctl', '-b0', '_COMM=plasmashell', '--no-pager'],
                    'journalctl (systemd)'
                )
            sources_tried.append('journalctl (no plasmashell logs found)')
        except Exception as e:
            sources_tried.append(f'journalctl (error: {e})')
    else:
        sources_tried.append('journalctl (not installed)')
    
    # Try 2: ~/.xsession-errors (common on Kubuntu and some other distros)
    xsession_errors = os.path.expanduser('~/.xsession-errors')
    if os.path.exists(xsession_errors):
        try:
            # Check if file is readable and not empty
            if os.path.getsize(xsession_errors) > 0:
                return (
                    ['cat', xsession_errors],
                    f'~/.xsession-errors'
                )
            sources_tried.append('~/.xsession-errors (file is empty)')
        except Exception as e:
            sources_tried.append(f'~/.xsession-errors (error: {e})')
    else:
        sources_tried.append('~/.xsession-errors (file not found)')
    
    # Try 3: journalctl without _COMM filter (might catch some logs)
    if shutil.which('journalctl'):
        try:
            result = subprocess.run(
                ['journalctl', '-b0', '--no-pager', '-n', '1', '-g', 'plasma'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return (
                    ['journalctl', '-b0', '--no-pager'],
                    'journalctl (all logs)'
                )
        except:
            pass
    
    return None, 'No log source found. Tried: ' + ', '.join(sources_tried)


def fetch_logs(command=None, filter_text=None, max_lines=500, since=None):
    """
    Fetch logs using the specified or auto-detected command.
    
    Args:
        command: Custom command to run (as string or list)
        filter_text: Text to filter logs by (e.g., 'eventcalendar')
        max_lines: Maximum number of lines to return
        since: Time specification for --since (journalctl only)
    
    Returns:
        tuple: (stdout, stderr, return_code, source_description)
    """
    source_desc = ''
    
    if command:
        if isinstance(command, str):
            # Use shell=True for custom commands to handle pipes, etc.
            cmd = command
            use_shell = True
        else:
            cmd = list(command)
            use_shell = False
        source_desc = 'custom command'
    else:
        cmd, source_desc = detect_log_source()
        use_shell = False
        
        if cmd is None:
            return '', source_desc, 1, 'none'
    
    # Add --since option for journalctl if specified
    if since and not use_shell and len(cmd) > 0 and cmd[0] == 'journalctl':
        cmd = list(cmd) + ['--since', since]
    
    try:
        if use_shell:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                shell=True
            )
        else:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
        
        output = result.stdout
        
        # Filter if requested
        if filter_text:
            lines = output.split('\n')
            filtered_lines = [line for line in lines if filter_text.lower() in line.lower()]
            output = '\n'.join(filtered_lines)
        
        # Limit number of lines (take the last N lines, most recent)
        if max_lines and max_lines > 0:
            lines = output.split('\n')
            if len(lines) > max_lines:
                lines = lines[-max_lines:]
                output = '\n'.join(lines)
        
        # Add header with source info
        header = f"# Log source: {source_desc}\n# Filter: {filter_text or 'none'}\n# Lines: {len(output.split(chr(10)))}\n\n"
        
        return header + output, result.stderr, result.returncode, source_desc
        
    except subprocess.TimeoutExpired:
        return '', 'Command timed out after 30 seconds', 1, source_desc
    except FileNotFoundError as e:
        return '', f'Command not found: {e}', 1, source_desc
    except Exception as e:
        return '', f'Error running command: {e}', 1, source_desc


def main():
    parser = argparse.ArgumentParser(
        prog='fetchlogs.py',
        description='Fetch plasmashell logs for debugging the Event Calendar applet.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Log Source Auto-Detection:
  The script automatically tries these sources in order:
  1. journalctl -b0 _COMM=plasmashell (systemd-based: Arch, Fedora, Ubuntu 16.04+)
  2. ~/.xsession-errors (Kubuntu, older Ubuntu, some other distros)
  
Examples:
  %(prog)s                          # Auto-detect, filter for 'eventcalendar'
  %(prog)s --no-filter              # Show all plasmashell logs
  %(prog)s --filter "error"         # Filter for 'error'
  %(prog)s --lines 100              # Show last 100 matching lines
  %(prog)s --command "dmesg"        # Use custom command
'''
    )
    parser.add_argument(
        '--filter', '-f',
        dest='filter_text',
        default='eventcalendar',
        help='Filter logs containing TEXT (default: eventcalendar)'
    )
    parser.add_argument(
        '--lines', '-n',
        type=int,
        default=500,
        help='Maximum number of lines to return (default: 500)'
    )
    parser.add_argument(
        '--since', '-s',
        help='Show logs since TIME (e.g., "1 hour ago", "2024-01-01") - journalctl only'
    )
    parser.add_argument(
        '--no-filter',
        dest='no_filter',
        action='store_true',
        help='Show all plasmashell logs without filtering'
    )
    parser.add_argument(
        '--command', '-c',
        help='Custom command to fetch logs (overrides auto-detection)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output in JSON format for programmatic use'
    )
    parser.add_argument(
        '--detect-only',
        dest='detect_only',
        action='store_true',
        help='Only detect and print the log source, do not fetch logs'
    )

    args = parser.parse_args()
    
    # Detect-only mode
    if args.detect_only:
        cmd, desc = detect_log_source()
        if cmd:
            print(f"Detected: {desc}")
            print(f"Command: {' '.join(cmd)}")
            sys.exit(0)
        else:
            print(f"Error: {desc}", file=sys.stderr)
            sys.exit(1)
    
    filter_text = None if args.no_filter else args.filter_text
    
    stdout, stderr, returncode, source = fetch_logs(
        command=args.command,
        filter_text=filter_text,
        max_lines=args.lines,
        since=args.since
    )
    
    if args.json:
        import json
        result = {
            'stdout': stdout,
            'stderr': stderr,
            'returncode': returncode,
            'source': source,
            'success': returncode == 0
        }
        print(json.dumps(result))
    else:
        if stdout:
            print(stdout)
        if stderr:
            print(stderr, file=sys.stderr)
    
    sys.exit(returncode)


if __name__ == '__main__':
    main()

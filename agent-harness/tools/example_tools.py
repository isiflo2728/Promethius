"""Example tools to pass into Agent(tools=[...]).

Each tool is: a plain Python function that returns a string, plus a Tool
wrapper describing it to the model. Keep the functions themselves boring —
all the interesting harness logic lives in agent.py, not here.
"""

import json

from tool import Tool


def read_file(path: str) -> str:
    """Read a file's contents and return them as a JSON string result.

    TODO:
      - open and read `path`
      - handle the file-not-found / permission-error case — return
        json.dumps({"error": ...}) rather than letting the exception
        propagate (Agent._dispatch should also guard this, but tools
        should be well-behaved on their own too)
      - on success return something like json.dumps({"content": <text>})
    """
    raise NotImplementedError


def run_shell_command(command: str) -> str:
    """Run a shell command and return its output as a JSON string result.

    TODO:
      - use subprocess to run `command`
      - capture stdout/stderr and the return code
      - think about a timeout — an agent-issued shell command should not be
        allowed to hang forever
      - return something like
        json.dumps({"stdout": ..., "stderr": ..., "returncode": ...})

    Careful: this tool lets the model execute arbitrary shell commands.
    Fine for a local learning harness; not something you'd expose to
    untrusted input without a sandbox/approval step.
    """
    raise NotImplementedError


# TODO: wrap each function above in a Tool(...), including the JSON Schema
# for its parameters. Example shape for read_file's `parameters`:
#
# {
#     "type": "object",
#     "properties": {
#         "path": {"type": "string", "description": "Path to the file to read"},
#     },
#     "required": ["path"],
# }
#
# read_file_tool = Tool(name=..., description=..., parameters=..., fn=read_file)
# run_shell_command_tool = Tool(name=..., description=..., parameters=..., fn=run_shell_command)

"""The Tool abstraction: what you pass into an Agent.

A Tool is a name + description + JSON Schema for its arguments + the actual
Python function to run. The Agent should never know what a tool *does* — it
only needs to be able to describe it to the model and call it by name.
"""

from dataclasses import dataclass
from typing import Callable


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict  # JSON Schema object describing the function's arguments
    fn: Callable[..., str]  # the function to call; must return a string

    def to_schema(self) -> dict:
        """Return this tool as an OpenAI-format tool schema dict.

        This is what gets sent to the model on every request so it knows
        the tool exists and what arguments it takes.

        Shape to produce:
        {
            "type": "function",
            "function": {
                "name": ...,
                "description": ...,
                "parameters": ...,
            },
        }
        """
        raise NotImplementedError

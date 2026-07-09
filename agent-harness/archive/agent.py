"""The harness itself.

Agent takes a model name and a list of Tools at construction time. It should
know nothing about what any specific tool does — only how to:
  1. send the conversation + tool schemas to the model
  2. check whether the model asked to call a tool
  3. dispatch the call by name and append the result as a message
  4. repeat until the model returns plain text, or max_iterations is hit

This is the whole loop. Everything else (registry auto-discovery, prompt
caching, persistence, multi-provider adapters) is a later refactor you earn
once this hurts — not a day-one requirement.
"""

from openai import OpenAI

from tool import Tool


class Agent:
    def __init__(
        self,
        model: str,
        tools: list[Tool] | None = None,
        base_url: str = "http://localhost:11434/v1",
        api_key: str = "ollama",  # Ollama ignores the key; the SDK just requires a non-empty string
        system_prompt: str | None = None,
        max_iterations: int = 10,
    ):
        # TODO: store an OpenAI client pointed at base_url/api_key
        # TODO: store model, max_iterations
        # TODO: build self.tools as a dict[str, Tool] keyed by tool.name
        #       (dict lookup instead of if/elif dispatch)
        # TODO: initialize self.messages as a list; if system_prompt is given,
        #       seed it as the first {"role": "system", "content": ...} message
        raise NotImplementedError

    def add_tool(self, tool: Tool) -> None:
        """Register a tool after construction. Nothing else about the Agent
        should need to change when this is called."""
        raise NotImplementedError

    def _tool_schemas(self) -> list[dict]:
        """Return self.tools.values() converted to OpenAI tool schemas via
        Tool.to_schema(). Return None/[] if there are no tools."""
        raise NotImplementedError

    def _dispatch(self, name: str, arguments: dict) -> str:
        """Look up `name` in self.tools and call its .fn(**arguments).

        Must NOT raise — catch exceptions and return a JSON string error
        instead (e.g. '{"error": "..."}') so a broken tool can't crash the
        loop or take down the whole agent.
        """
        raise NotImplementedError

    def run(self, user_message: str) -> str:
        """Send one user message through the loop; return the model's final
        text reply.

        Pseudocode:
            append user_message to self.messages

            loop up to self.max_iterations times:
                call self.client.chat.completions.create(
                    model=self.model,
                    messages=self.messages,
                    tools=self._tool_schemas(),
                )
                msg = response.choices[0].message

                if msg has no tool_calls:
                    append msg as an assistant message to self.messages
                    return msg.content   # done

                # otherwise: the model wants to call one or more tools
                append the assistant's tool_call request to self.messages
                for each tool_call in msg.tool_calls:
                    parse tool_call.function.arguments (JSON string -> dict)
                    result = self._dispatch(tool_call.function.name, args)
                    append a {"role": "tool", "tool_call_id": ..., "content": result}
                    message to self.messages
                # then loop again — send the updated messages back to the model

            return something indicating max_iterations was hit without a final answer
        """
        raise NotImplementedError

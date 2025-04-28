defmodule MCPServer do
  @moduledoc """
  Behaviour definition for implementing MCP (Model Context Protocol) servers.
  Provides a standardized interface for handling MCP messages and tools.

  ## Example

      defmodule YourApp.YourMCPServer do
        use MCPServer
        require Logger

        @protocol_version "2024-11-05"

        @impl true
        def handle_ping(request_id) do
          {:ok, %{jsonrpc: "2.0", id: request_id, result: %{}}}
        end

        @impl true
        def handle_initialize(request_id, params) do
          Logger.info("Client initialization params: \#{inspect(params, pretty: true)}")

          case validate_protocol_version(params["protocolVersion"]) do
            :ok ->
              {:ok,
               %{
                 jsonrpc: "2.0",
                 id: request_id,
                 result: %{
                   protocolVersion: @protocol_version,
                   capabilities: %{
                     tools: %{
                       listChanged: true
                     }
                   },
                   serverInfo: %{
                     name: "Your MCP Server",
                     version: "0.1.0"
                   }
                 }
               }}

            {:error, reason} ->
              {:error, reason}
          end
        end

        @impl true
        def handle_list_tools(request_id, _params) do
          {:ok,
           %{
             jsonrpc: "2.0",
             id: request_id,
             result: %{
               tools: [
                 %{
                   name: "upcase",
                   description: "Converts text to uppercase",
                   inputSchema: %{
                     type: "object",
                     required: ["text"],
                     properties: %{
                       text: %{
                         type: "string",
                         description: "The text to convert to uppercase"
                       }
                     }
                   },
                   outputSchema: %{
                     type: "object",
                     required: ["output"],
                     properties: %{
                       output: %{
                         type: "string",
                         description: "The uppercase version of the input text"
                       }
                     }
                   }
                 }
               ]
             }
           }}
        end

        @impl true
        def handle_call_tool(request_id, %{"name" => "upcase", "arguments" => %{"text" => text}} = params) do
          Logger.debug("Handling upcase tool call with params: \#{inspect(params, pretty: true)}")

          {:ok,
           %{
             jsonrpc: "2.0",
             id: request_id,
             result: %{
               content: [
                 %{
                   type: "text",
                   text: String.upcase(text)
                 }
               ]
             }
           }}
        end

        def handle_call_tool(request_id, %{"name" => unknown_tool} = params) do
          Logger.warning("Unknown tool called: \#{unknown_tool} with params: \#{inspect(params, pretty: true)}")

          {:error,
           %{
             jsonrpc: "2.0",
             id: request_id,
             error: %{
               code: -32601,
               message: "Method not found",
               data: %{
                 name: unknown_tool
               }
             }
           }}
        end

        # implementations of other calls for resources, prompts, etc.
      end
  """

  @protocol_version "2024-11-05"

  defmacro __using__(_opts) do
    quote do
      @behaviour MCPServer
      require Logger

      # Built-in message routing
      def handle_message(_assigns, %{"method" => "notifications/initialized"} = message) do
        Logger.info("Received initialized notification")
        Logger.debug("Full message: #{inspect(message, pretty: true)}")
        {:ok, nil}
      end

      def handle_message(assigns, %{"method" => method, "id" => id} = message) do
        Logger.info("Routing MCP message - Method: #{method}, ID: #{id}")
        Logger.debug("Full message: #{inspect(message, pretty: true)}")

        case method do
          "ping" ->
            Logger.debug("Handling ping request")
            handle_ping(assigns, id)

          "initialize" ->
            Logger.info(
              "Handling initialize request with params: #{inspect(message["params"], pretty: true)}"
            )

            handle_initialize(assigns, id, message["params"])

          "completion/complete" ->
            Logger.debug(
              "Handling complete request with params: #{inspect(message["params"], pretty: true)}"
            )

            handle_complete(assigns, id, message["params"])

          "prompts/list" ->
            Logger.debug("Handling prompts list request")
            handle_list_prompts(assigns, id, message["params"])

          "prompts/get" ->
            Logger.debug(
              "Handling prompt get request with params: #{inspect(message["params"], pretty: true)}"
            )

            handle_get_prompt(assigns, id, message["params"])

          "resources/list" ->
            Logger.debug("Handling resources list request")
            handle_list_resources(assigns, id, message["params"])

          "resources/read" ->
            Logger.debug(
              "Handling resource read request with params: #{inspect(message["params"], pretty: true)}"
            )

            handle_read_resource(assigns, id, message["params"])

          "tools/list" ->
            Logger.debug("Handling tools list request")
            handle_list_tools(assigns, id, message["params"])

          "tools/call" ->
            Logger.debug(
              "Handling tool call request with params: #{inspect(message["params"], pretty: true)}"
            )

            handle_call_tool(assigns, id, message["params"])

          other ->
            Logger.warning("Received unsupported method: #{other}")

            {:error,
             %{
               jsonrpc: "2.0",
               id: id,
               error: %{
                 code: -32601,
                 message: "Method not found",
                 data: %{
                   name: other
                 }
               }
             }}
        end
      end

      def handle_message(_assigns, unknown_message) do
        Logger.error("Received invalid message format: #{inspect(unknown_message, pretty: true)}")

        {:error,
         %{
           jsonrpc: "2.0",
           id: nil,
           error: %{
             code: -32600,
             message: "Invalid Request",
             data: %{
               received: unknown_message
             }
           }
         }}
      end

      # Default implementations for optional callbacks
      def handle_complete(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_list_prompts(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_get_prompt(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_list_resources(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_read_resource(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_list_tools(_assigns, _request_id, _params), do: {:error, "Not implemented"}
      def handle_call_tool(_assigns, _request_id, _params), do: {:error, "Not implemented"}

      # Allow overriding any of the defaults
      defoverridable handle_complete: 3,
                     handle_list_prompts: 3,
                     handle_get_prompt: 3,
                     handle_list_resources: 3,
                     handle_read_resource: 3,
                     handle_list_tools: 3,
                     handle_call_tool: 3

      # Helper functions
      def validate_protocol_version(client_version) do
        cond do
          is_nil(client_version) ->
            {:error, "Protocol version is required"}

          client_version != unquote(@protocol_version) ->
            {:error,
             "Unsupported protocol version. Server supports: #{unquote(@protocol_version)}"}

          true ->
            :ok
        end
      end
    end
  end

  # Required Callbacks
  @callback handle_ping(assigns :: Map.t(), request_id :: String.t() | integer()) ::
              {:ok, map()} | {:error, String.t()}
  @callback handle_initialize(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  # Optional Callbacks
  @callback handle_complete(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_list_prompts(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_get_prompt(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_list_resources(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_read_resource(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_list_tools(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @callback handle_call_tool(assigns :: Map.t(), request_id :: String.t() | integer(), params :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @optional_callbacks [
    handle_complete: 3,
    handle_list_prompts: 3,
    handle_get_prompt: 3,
    handle_list_resources: 3,
    handle_read_resource: 3,
    handle_list_tools: 3,
    handle_call_tool: 3
  ]
end

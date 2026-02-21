# Broadway API Reference

Source: https://hexdocs.pm/broadway/Broadway.html (v1.2.1)

Broadway is a concurrent, multi-stage data ingestion and processing library for Elixir built on top of GenStage.

---

## Broadway.start_link/2

```elixir
@spec start_link(module(), keyword()) :: on_start()
```

Starts a Broadway pipeline linked to the current process. Requires a module implementing the `Broadway` behaviour and a keyword list of options.

### Top-Level Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `:name` | atom or `{:via, module, term}` | Yes | -- | Used for process registration |
| `:shutdown` | pos_integer | No | 30000 | Graceful shutdown time in milliseconds |
| `:max_restarts` | non_neg_integer | No | 3 | Maximum restart count |
| `:max_seconds` | pos_integer | No | 5 | Time window for restart counting |
| `:resubscribe_interval` | non_neg_integer | No | 100 | Resubscription delay (ms) after producer failure |
| `:context` | term | No | `:context_not_set` | User-defined data passed to all callbacks |
| `:producer` | keyword | Yes | -- | Producer configuration (see below) |
| `:processors` | keyword | Yes | -- | Processor configuration (see below) |
| `:batchers` | keyword | No | `[]` | Batcher configuration (see below) |
| `:partition_by` | `(Broadway.Message.t() -> term)` | No | -- | Default partitioning function for all stages |
| `:spawn_opt` | keyword | No | -- | Low-level process spawn options |
| `:hibernate_after` | pos_integer | No | 15000 | Memory compaction interval (ms) |

### Producer Options

Nested under the `:producer` key.

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `:module` | `{module, arg}` | Yes | -- | GenStage producer module and its init argument |
| `:concurrency` | pos_integer | No | 1 | Number of concurrent producer processes |
| `:transformer` | `{module, function, opts}` | No | -- | Transforms raw events into `Broadway.Message` structs |
| `:spawn_opt` | keyword | No | -- | Overrides top-level `:spawn_opt` for producers |
| `:hibernate_after` | pos_integer | No | -- | Overrides top-level `:hibernate_after` for producers |
| `:rate_limiting` | keyword | No | -- | Rate limiting (see sub-options below) |

#### Rate Limiting Sub-options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `:allowed_messages` | pos_integer | Yes | Messages permitted per interval |
| `:interval` | pos_integer | Yes | Time window in milliseconds |

### Processor Options

Nested under the `:processors` key. Each key is a processor name (e.g., `:default`).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:concurrency` | pos_integer | `System.schedulers_online() * 2` | Number of concurrent processor processes |
| `:min_demand` | non_neg_integer | -- | Minimum demand threshold |
| `:max_demand` | non_neg_integer | 10 | Maximum demand threshold |
| `:partition_by` | `(Broadway.Message.t() -> term)` | -- | Overrides top-level `:partition_by` for this processor |
| `:spawn_opt` | keyword | -- | Overrides top-level `:spawn_opt` |
| `:hibernate_after` | pos_integer | -- | Overrides top-level `:hibernate_after` |

### Batcher Options

Nested under the `:batchers` key. Each key is a batcher name (e.g., `:default`, `:s3`).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:concurrency` | pos_integer | 1 | Number of concurrent batch processor processes |
| `:batch_size` | integer or `{init_acc, fun}` | 100 | Target batch size or custom accumulator function |
| `:max_demand` | pos_integer | batch_size value | Maximum demand from batcher to processor |
| `:batch_timeout` | pos_integer | 1000 | Flush timeout in milliseconds |
| `:partition_by` | `(Broadway.Message.t() -> term)` | -- | Overrides top-level `:partition_by` for this batcher |
| `:spawn_opt` | keyword | -- | Overrides top-level `:spawn_opt` |
| `:hibernate_after` | pos_integer | -- | Overrides top-level `:hibernate_after` |

---

## Partitioning (`:partition_by`)

The `:partition_by` option accepts a function that receives a `Broadway.Message` and returns any term. Messages that return the same term are guaranteed to be processed by the same processor (or batcher), ensuring ordered, serialized processing for that partition key.

Can be set at:
- **Top level** — applies to all processors and batchers
- **Per processor** — overrides the top-level for that processor
- **Per batcher** — overrides the top-level for that batcher

### Example

```elixir
Broadway.start_link(MyBroadway,
  name: MyBroadway,
  producer: [module: {MyProducer, []}],
  processors: [
    default: [
      concurrency: 4,
      partition_by: fn %Broadway.Message{data: data} ->
        data.user_id
      end
    ]
  ]
)
```

### Caveats

- **Performance:** Using `:partition_by` with very high concurrency can be detrimental. All N processors must make progress simultaneously.
- **Demand:** Avoid `:partition_by` with `max_demand: 1` (implies `min_demand: 0`). Each processor gets a single message and blocks until all processors complete.
- **Error semantics:** If a message fails, the partition continues processing subsequent messages. If the producer retries the failed message, it may arrive out of order.

---

## Callbacks

### handle_message/3 (required)

```elixir
@callback handle_message(
  processor :: atom(),
  message :: Broadway.Message.t(),
  context :: term()
) :: Broadway.Message.t()
```

Processes individual messages from the producer. This is where you transform data, apply business logic, and optionally route messages to batchers.

- Use `Broadway.Message.update_data/2` to transform message data
- Use `Broadway.Message.put_batcher/2` to route to a specific batcher
- Use `Broadway.Message.failed/2` to explicitly fail a message
- If the callback raises/crashes, the message is marked as failed and does not proceed downstream

### handle_batch/4 (required if batchers are configured)

```elixir
@callback handle_batch(
  batcher :: atom(),
  messages :: [Broadway.Message.t()],
  batch_info :: Broadway.BatchInfo.t(),
  context :: term()
) :: [Broadway.Message.t()]
```

Processes a batch of messages. All received messages must be returned. If the callback crashes, the entire batch fails. The callback traps exits to prevent cascading failures.

### handle_failed/2 (optional)

```elixir
@callback handle_failed(
  messages :: [Broadway.Message.t()],
  context :: term()
) :: [Broadway.Message.t()]
```

Called for messages that failed in `handle_message/3` or `handle_batch/4`, before acknowledgment. Use for dead-letter queuing or error logging.

### prepare_messages/2 (optional)

```elixir
@callback prepare_messages(
  messages :: [Broadway.Message.t()],
  context :: term()
) :: [Broadway.Message.t()]
```

Called before `handle_message/3` with the full list of messages received from the producer. Use for batch-level preparation (e.g., preloading data for all messages at once).

---

## Key Functions

### Broadway.Message functions

| Function | Description |
|----------|-------------|
| `Message.update_data(msg, fun)` | Transforms the message data |
| `Message.put_batcher(msg, batcher)` | Routes message to a named batcher |
| `Message.put_batch_key(msg, key)` | Groups messages within a batcher |
| `Message.put_batch_mode(msg, mode)` | Sets `:bulk` or `:flush` mode |
| `Message.failed(msg, reason)` | Explicitly marks a message as failed |
| `Message.configure_ack(msg, opts)` | Configures acknowledgment behavior |

### Pipeline control

| Function | Description |
|----------|-------------|
| `Broadway.producer_names(broadway)` | Returns registered producer names |
| `Broadway.all_running()` | Returns all running Broadway instances |
| `Broadway.get_rate_limiter(broadway)` | Returns the rate limiter name (if configured) |

### Testing

| Function | Description |
|----------|-------------|
| `Broadway.test_message(broadway, data, opts)` | Sends a test message (use with `Broadway.DummyProducer`) |
| `Broadway.test_batch(broadway, data, opts)` | Sends a test batch |

---

## Complete Example

```elixir
defmodule MyBroadway do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Counter, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ],
      batchers: [
        sqs: [concurrency: 2, batch_size: 10],
        s3: [concurrency: 1, batch_size: 10]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: data} = message, _) do
    message
    |> Broadway.Message.update_data(&process/1)
    |> Broadway.Message.put_batcher(:sqs)
  end

  @impl true
  def handle_batch(:sqs, messages, _batch_info, _context) do
    # Process the SQS batch
    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    # Custom failure handling
    messages
  end
end
```

---

## Custom Producer

A Broadway producer is a GenStage producer. Implement `c:GenStage.init/1` and `c:GenStage.handle_demand/2`. Optionally implement `c:Broadway.Producer.prepare_for_draining/1` for graceful shutdown.

For polling-based producers, use `:timer.send_interval/2` or `Process.send_after/3` in `init/1` and handle the timer in `handle_info/2`, buffering events and dispatching on demand.
